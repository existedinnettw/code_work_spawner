import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_logger.dart';
import '../../config/config.dart';
import '../client.dart';
import '../models.dart';
import '../../core/process_launcher.dart';
import 'base.dart';

class GitHubWebhookForwardIssueEventSource implements IssueEventSource {
  GitHubWebhookForwardIssueEventSource({
    required this.issueTrackerClient,
    required this.commandExecutor,
    required AppLogger logger,
  }) : _logger = logger;

  static const Duration _webhookCoalescingWindow = Duration(milliseconds: 500);

  final IssueTrackerClient issueTrackerClient;
  final ExternalCommandExecutor commandExecutor;
  final AppLogger _logger;
  final Map<String, _QueuedWebhookIssue> _queuedIssues = {};
  final Set<Future<void>> _activeDispatches = <Future<void>>{};
  final Map<String, StartedExternalCommand> _forwardProcesses = {};

  HttpServer? _server;
  Timer? _flushTimer;
  Completer<void>? _runCompleter;
  bool _isClosing = false;
  bool _isClosed = false;

  @override
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    if (_isClosed) {
      throw StateError('IssueEventSource is already closed.');
    }
    if (_runCompleter != null) {
      return _runCompleter!.future;
    }

    final githubProjects = projects
        .where((project) => project.provider == IssueTrackerProvider.github)
        .toList(growable: false);
    if (githubProjects.isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _runCompleter = completer;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _log(
      'github/webhook-forward starting projects=${githubProjects.length} '
      'keys=${githubProjects.map((project) => project.key).join(",")}',
    );
    final repoToProject = {
      for (final project in githubProjects) project.repo: project,
    };
    server.listen(
      (request) => unawaited(
        _handleWebhookRequest(
          request: request,
          repoToProject: repoToProject,
          onBatch: onBatch,
        ),
      ),
      onError: (Object error, StackTrace stackTrace) {
        _logError('github/webhook-forward server error=$error');
        if (!_isClosing && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    final url =
        'http://${server.address.address}:${server.port}/github/webhooks';
    _log(
      'github/webhook-forward listening local_url=$url '
      'projects=${githubProjects.map((project) => project.key).join(",")}',
    );
    try {
      for (final project in githubProjects) {
        try {
          _log(
            'github/webhook-forward project=${project.key} setup_start '
            'repo=${project.repo} local_url=$url',
          );
          _log(
            'github/webhook-forward project=${project.key} start_forwarder '
            'command="${issueTrackerClient.ghCommand} webhook forward --events=issues,issue_comment --repo=${project.repo} --url=$url"',
          );
          final process = await commandExecutor
              .start(issueTrackerClient.ghCommand, [
                'webhook',
                'forward',
                '--events=issues,issue_comment',
                '--repo=${project.repo}',
                '--url=$url',
              ]);
          _forwardProcesses[project.key] = process;
          _pipeProcessLogs(
            project: project,
            stream: process.stdout,
            level: 'stdout',
          );
          _pipeProcessLogs(
            project: project,
            stream: process.stderr,
            level: 'stderr',
          );
          unawaited(
            process.exitCode.then((exitCode) {
              _forwardProcesses.remove(project.key);
              _log(
                'github/webhook-forward process project=${project.key} '
                'exit_code=$exitCode',
              );
              if (!_isClosing && !completer.isCompleted) {
                completer.completeError(
                  StateError(
                    'gh webhook forward exited for project=${project.key} '
                    'with code $exitCode.',
                  ),
                );
              }
            }),
          );
          _log(
            'github/webhook-forward project=${project.key} setup_complete '
            'repo=${project.repo}',
          );
        } catch (error, stackTrace) {
          _logError(
            'github/webhook-forward project=${project.key} setup_failed '
            'step=start_forwarder error=$error',
          );
          Error.throwWithStackTrace(error, stackTrace);
        }
      }

      await completer.future;
    } finally {
      await close();
    }
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    throw UnsupportedError(
      'github/webhook-forward does not support runOnce; use polling instead.',
    );
  }

  @override
  Future<void> close() async {
    if (_isClosed || _isClosing) {
      return;
    }

    _isClosing = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _runCompleter = null;

    final server = _server;
    _server = null;
    await server?.close(force: true);

    final processes = _forwardProcesses.values.toList(growable: false);
    _forwardProcesses.clear();
    for (final process in processes) {
      process.kill();
    }
    for (final process in processes) {
      await process.exitCode.catchError((_) => 0);
    }

    await _flushQueuedIssues();
    await Future.wait(_activeDispatches.toList(growable: false));

    _isClosed = true;
    _isClosing = false;
  }

  Future<void> _handleWebhookRequest({
    required HttpRequest request,
    required Map<String, ProjectConfig> repoToProject,
    required IssueEventBatchHandler onBatch,
  }) async {
    _logDebug(
      'github/webhook-forward webhook request method=${request.method} '
      'path=${request.uri.path} event=${request.headers.value("X-GitHub-Event") ?? "(missing)"}',
    );
    if (request.method != 'POST') {
      _log(
        'github/webhook-forward webhook ignored method=${request.method} '
        'path=${request.uri.path}',
      );
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Only POST is supported.');
      await request.response.close();
      return;
    }

    try {
      final payloadText = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(payloadText);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Webhook payload must be a JSON object.');
      }
      final repository = payload['repository'];
      final fullName = repository is Map<String, dynamic>
          ? repository['full_name']?.toString()
          : null;
      final project = fullName == null ? null : repoToProject[fullName];
      final issueNode = payload['issue'];
      final action = payload['action']?.toString() ?? 'unknown';
      if (project != null &&
          issueNode is Map<String, dynamic> &&
          (issueNode['pull_request'] == null)) {
        final issue = GitHubIssueSummary.fromRepositoryJson(
          project.requiredRepoSlug,
          issueNode,
        );
        _log(
          'github/webhook-forward webhook accepted project=${project.key} '
          'repo=$fullName action=$action issue=${issue.number} state=${issue.state}',
        );
        if (issue.state == 'open') {
          _queuedIssues['${project.key}#${issue.number}'] = _QueuedWebhookIssue(
            project: project,
            issue: issue,
            onBatch: onBatch,
          );
          _scheduleFlush();
        }
      } else {
        _log(
          'github/webhook-forward webhook ignored repo=${fullName ?? "(missing)"} '
          'action=$action matched_project=${project != null} '
          'has_issue=${issueNode is Map<String, dynamic>} '
          'is_pull_request=${issueNode is Map<String, dynamic> && issueNode["pull_request"] != null}',
        );
      }

      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
    } catch (error) {
      _logError('github/webhook-forward payload error=$error');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid webhook payload.');
      await request.response.close();
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_webhookCoalescingWindow, () {
      _flushTimer = null;
      unawaited(_flushQueuedIssues());
    });
  }

  Future<void> _flushQueuedIssues() async {
    if (_queuedIssues.isEmpty) {
      return;
    }

    final queuedIssues = _queuedIssues.values.toList(growable: false);
    _queuedIssues.clear();
    final groupedIssues = <String, _QueuedWebhookBatch>{};
    for (final queuedIssue in queuedIssues) {
      groupedIssues.update(
        queuedIssue.project.key,
        (existing) => existing.add(queuedIssue.issue),
        ifAbsent: () => _QueuedWebhookBatch(
          project: queuedIssue.project,
          onBatch: queuedIssue.onBatch,
          issues: [queuedIssue.issue],
        ),
      );
    }

    late final Future<void> dispatchFuture;
    dispatchFuture = () async {
      for (final batch in groupedIssues.values) {
        batch.issues.sort(
          (left, right) => left.updatedAt.compareTo(right.updatedAt),
        );
        _log(
          'github/webhook-forward project=${batch.project.key} '
          'fetched_issues=${batch.issues.length}',
        );
        await batch.onBatch(
          IssueEventBatch(
            project: batch.project,
            issues: batch.issues,
            latestSeenUpdatedAt: batch.issues.last.updatedAt,
            sourceKind: 'github/webhook-forward',
          ),
        );
      }
    }();

    _activeDispatches.add(dispatchFuture);
    try {
      await dispatchFuture;
    } finally {
      _activeDispatches.remove(dispatchFuture);
    }
  }

  void _pipeProcessLogs({
    required ProjectConfig project,
    required Stream<List<int>> stream,
    required String level,
  }) {
    stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      final message =
          'github/webhook-forward project=${project.key} $level=$line';
      if (level == 'stderr') {
        _logError(message);
        return;
      }
      _log(message);
    });
  }

  void _log(String message) {
    _logger.info(message);
  }

  void _logDebug(String message) {
    _logger.debug(message);
  }

  void _logError(String message) {
    _logger.error(message);
  }
}

class _QueuedWebhookIssue {
  _QueuedWebhookIssue({
    required this.project,
    required this.issue,
    required this.onBatch,
  });

  final ProjectConfig project;
  final GitHubIssueSummary issue;
  final IssueEventBatchHandler onBatch;
}

class _QueuedWebhookBatch {
  _QueuedWebhookBatch({
    required this.project,
    required this.onBatch,
    required this.issues,
  });

  final ProjectConfig project;
  final IssueEventBatchHandler onBatch;
  final List<GitHubIssueSummary> issues;

  _QueuedWebhookBatch add(GitHubIssueSummary issue) {
    issues.removeWhere((existing) => existing.number == issue.number);
    issues.add(issue);
    return this;
  }
}
