import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

import 'config.dart';
import 'issue_event_source.dart';
import 'issue_tracker_client.dart';

class GiteaGosmeeIssueEventSource implements IssueEventSource {
  GiteaGosmeeIssueEventSource({
    required this.issueTrackerClient,
    required this.gosmeeCommand,
    required Logger logger,
  }) : _logger = logger;

  static const Duration _webhookCoalescingWindow = Duration(milliseconds: 500);

  final IssueTrackerClient issueTrackerClient;
  final String gosmeeCommand;
  final Logger _logger;
  final Map<String, _QueuedGiteaIssue> _queuedIssues = {};
  final Set<Future<void>> _activeDispatches = <Future<void>>{};
  final Map<String, Process> _gosmeeProcesses = {};
  final Map<String, int> _webhookIdsByProject = {};
  final Map<String, RepositorySlug> _repoSlugsByProject = {};

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

    final giteaProjects = projects
        .where((project) => project.provider == IssueTrackerProvider.gitea)
        .toList(growable: false);
    if (giteaProjects.isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _runCompleter = completer;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final repoToProject = {
      for (final project in giteaProjects) project.repo: project,
    };
    for (final project in giteaProjects) {
      _repoSlugsByProject[project.key] = project.repoSlug;
    }
    server.listen(
      (request) => unawaited(
        _handleWebhookRequest(
          request: request,
          repoToProject: repoToProject,
          onBatch: onBatch,
        ),
      ),
      onError: (Object error, StackTrace stackTrace) {
        _logError('gitea/gosmee server error=$error');
        if (!_isClosing && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    final localUrl =
        'http://${server.address.address}:${server.port}/gitea/webhooks';
    for (final project in giteaProjects) {
      final publicUrl = await _createGosmeeChannelUrl(localUrl);
      final webhookId = await issueTrackerClient.createGiteaIssueWebhook(
        repo: project.repoSlug,
        url: publicUrl,
      );
      _webhookIdsByProject[project.key] = webhookId;
      final process = await Process.start(gosmeeCommand, [
        'client',
        publicUrl,
        localUrl,
      ]);
      _gosmeeProcesses[project.key] = process;
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
          _gosmeeProcesses.remove(project.key);
          _log(
            'gitea/gosmee process project=${project.key} exit_code=$exitCode',
          );
          if (!_isClosing && !completer.isCompleted) {
            completer.completeError(
              StateError(
                'gosmee client exited for project=${project.key} '
                'with code $exitCode.',
              ),
            );
          }
        }),
      );
    }

    try {
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
      'gitea/gosmee does not support runOnce; use polling instead.',
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

    final processes = _gosmeeProcesses.values.toList(growable: false);
    _gosmeeProcesses.clear();
    for (final process in processes) {
      process.kill();
    }
    for (final process in processes) {
      await process.exitCode.catchError((_) => 0);
    }

    final webhookIds = Map<String, int>.from(_webhookIdsByProject);
    _webhookIdsByProject.clear();
    for (final entry in webhookIds.entries) {
      try {
        await issueTrackerClient.deleteGiteaWebhook(
          repo: _repoSlugsByProject[entry.key]!,
          webhookId: entry.value,
        );
      } catch (error) {
        _logError(
          'gitea/gosmee delete webhook project=${entry.key} '
          'webhook_id=${entry.value} error=$error',
        );
      }
    }
    _repoSlugsByProject.clear();

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
    if (request.method != 'POST') {
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
      if (project != null &&
          issueNode is Map<String, dynamic> &&
          (issueNode['pull_request'] == null)) {
        final issue = GitHubIssueSummary.fromRepositoryJson(
          project.repoSlug,
          issueNode,
        );
        if (issue.state == 'open') {
          _queuedIssues['${project.key}#${issue.number}'] = _QueuedGiteaIssue(
            project: project,
            issue: issue,
            onBatch: onBatch,
          );
          _scheduleFlush();
        }
      }

      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
    } catch (error) {
      _logError('gitea/gosmee payload error=$error');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid webhook payload.');
      await request.response.close();
    }
  }

  Future<String> _createGosmeeChannelUrl(String localUrl) async {
    final result = await Process.run(gosmeeCommand, [
      '--output',
      'json',
      'client',
      '--new-url',
      localUrl,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        gosmeeCommand,
        ['--output', 'json', 'client', '--new-url', localUrl],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    final stdoutText = result.stdout.toString().trim();
    if (stdoutText.isEmpty) {
      throw const FormatException('gosmee did not print a public URL.');
    }
    try {
      final decodedJson = jsonDecode(stdoutText);
      if (decodedJson is Map<String, dynamic>) {
        final publicUrl = decodedJson['url']?.toString().trim();
        if (publicUrl == null || publicUrl.isEmpty) {
          throw const FormatException(
            'gosmee JSON output did not contain a valid public URL.',
          );
        }
        return publicUrl;
      }
      if (decodedJson is String) {
        final publicUrl = decodedJson.trim();
        if (publicUrl.isEmpty) {
          throw const FormatException('gosmee did not print a public URL.');
        }
        return publicUrl;
      }
    } on FormatException {
      if (Uri.tryParse(stdoutText)?.hasScheme ?? false) {
        return stdoutText;
      }
    }
    throw const FormatException('gosmee did not print a valid public URL.');
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
    final groupedIssues = <String, _QueuedGiteaBatch>{};
    for (final queuedIssue in queuedIssues) {
      groupedIssues.update(
        queuedIssue.project.key,
        (existing) => existing.add(queuedIssue.issue),
        ifAbsent: () => _QueuedGiteaBatch(
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
          'gitea/gosmee project=${batch.project.key} '
          'fetched_issues=${batch.issues.length}',
        );
        await batch.onBatch(
          IssueEventBatch(
            project: batch.project,
            issues: batch.issues,
            latestSeenUpdatedAt: batch.issues.last.updatedAt,
            sourceKind: 'gitea/gosmee',
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
    utf8.decoder
        .bind(stream)
        .transform(const LineSplitter())
        .listen(
          (line) => _log('gitea/gosmee project=${project.key} $level=$line'),
        );
  }

  void _log(String message) {
    _logger.info(message);
  }

  void _logError(String message) {
    _logger.warning(message);
  }
}

class _QueuedGiteaIssue {
  _QueuedGiteaIssue({
    required this.project,
    required this.issue,
    required this.onBatch,
  });

  final ProjectConfig project;
  final GitHubIssueSummary issue;
  final IssueEventBatchHandler onBatch;
}

class _QueuedGiteaBatch {
  _QueuedGiteaBatch({
    required this.project,
    required this.onBatch,
    required this.issues,
  });

  final ProjectConfig project;
  final IssueEventBatchHandler onBatch;
  final List<GitHubIssueSummary> issues;

  _QueuedGiteaBatch add(GitHubIssueSummary issue) {
    issues.add(issue);
    return this;
  }
}
