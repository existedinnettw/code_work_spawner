import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';

import '../../config/app_logger.dart';
import '../../config/config.dart';
import '../client.dart';
import '../models.dart';
import '../../core/process_launcher.dart';
import 'base.dart';

class GitHubGosmeeIssueEventSource implements IssueEventSource {
  GitHubGosmeeIssueEventSource({
    required this.issueTrackerClient,
    required this.gosmeeCommand,
    required this.commandExecutor,
    required AppLogger logger,
  }) : _logger = logger;

  static const Duration _webhookCoalescingWindow = Duration(milliseconds: 500);

  final IssueTrackerClient issueTrackerClient;
  final String gosmeeCommand;
  final ExternalCommandExecutor commandExecutor;
  final AppLogger _logger;
  final Map<String, _QueuedGitHubIssue> _queuedIssues = {};
  final Set<Future<void>> _activeDispatches = <Future<void>>{};
  final Map<String, StartedExternalCommand> _gosmeeProcesses = {};
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
      'github/gosmee starting projects=${githubProjects.length} '
      'keys=${githubProjects.map((project) => project.key).join(",")}',
    );
    final repoToProject = {
      for (final project in githubProjects) project.repo: project,
    };
    for (final project in githubProjects) {
      _repoSlugsByProject[project.key] = project.requiredRepoSlug;
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
        _logError('github/gosmee server error=$error');
        if (!_isClosing && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    final localUrl =
        'http://${server.address.address}:${server.port}/github/webhooks';
    _log(
      'github/gosmee listening local_url=$localUrl '
      'projects=${githubProjects.map((project) => project.key).join(",")}',
    );
    try {
      for (final project in githubProjects) {
        var setupStep = 'create_channel';
        try {
          _log(
            'github/gosmee project=${project.key} setup_start '
            'repo=${project.repo} local_url=$localUrl',
          );
          _log(
            'github/gosmee project=${project.key} create_channel '
            'command="$gosmeeCommand --output json client --new-url $localUrl"',
          );
          final publicUrl = await _createGosmeeChannelUrl(localUrl);
          _log(
            'github/gosmee project=${project.key} channel_ready '
            'public_url=$publicUrl local_url=$localUrl',
          );
          setupStep = 'register_webhook';
          final webhookId = await issueTrackerClient.createGitHubIssueWebhook(
            repo: project.requiredRepoSlug,
            url: publicUrl,
          );
          _webhookIdsByProject[project.key] = webhookId;
          _log(
            'github/gosmee project=${project.key} webhook_registered '
            'webhook_id=$webhookId repo=${project.repo}',
          );
          setupStep = 'start_client';
          _log(
            'github/gosmee project=${project.key} start_client '
            'command="$gosmeeCommand client $publicUrl $localUrl"',
          );
          final process = await commandExecutor.start(gosmeeCommand, [
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
                'github/gosmee process project=${project.key} exit_code=$exitCode',
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
          _log(
            'github/gosmee project=${project.key} setup_complete '
            'repo=${project.repo}',
          );
        } catch (error, stackTrace) {
          _logError(
            'github/gosmee project=${project.key} setup_failed '
            'step=$setupStep error=$error',
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
      'github/gosmee does not support runOnce; use polling instead.',
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
        _log(
          'github/gosmee project=${entry.key} webhook_delete '
          'webhook_id=${entry.value}',
        );
        await issueTrackerClient.deleteGitHubWebhook(
          repo: _repoSlugsByProject[entry.key]!,
          webhookId: entry.value,
        );
      } catch (error) {
        _logError(
          'github/gosmee delete webhook project=${entry.key} '
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
    _logDebug(
      'github/gosmee webhook request method=${request.method} '
      'path=${request.uri.path} event=${request.headers.value("X-GitHub-Event") ?? "(missing)"}',
    );
    if (request.method != 'POST') {
      _log(
        'github/gosmee webhook ignored method=${request.method} '
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
          'github/gosmee webhook accepted project=${project.key} '
          'repo=$fullName action=$action issue=${issue.number} state=${issue.state}',
        );
        if (issue.state == 'open') {
          _queuedIssues['${project.key}#${issue.number}'] = _QueuedGitHubIssue(
            project: project,
            issue: issue,
            onBatch: onBatch,
          );
          _scheduleFlush();
        }
      } else {
        _log(
          'github/gosmee webhook ignored repo=${fullName ?? "(missing)"} '
          'action=$action matched_project=${project != null} '
          'has_issue=${issueNode is Map<String, dynamic>} '
          'is_pull_request=${issueNode is Map<String, dynamic> && issueNode["pull_request"] != null}',
        );
      }

      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
    } catch (error) {
      _logError('github/gosmee payload error=$error');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid webhook payload.');
      await request.response.close();
    }
  }

  Future<String> _createGosmeeChannelUrl(String localUrl) async {
    final result = await commandExecutor.run(gosmeeCommand, [
      '--output',
      'json',
      'client',
      '--new-url',
      localUrl,
    ]);
    _logDebug(
      'github/gosmee channel_command_result local_url=$localUrl '
      'exit_code=${result.exitCode} stdout=${_summarizeText(result.stdout.toString())} '
      'stderr=${_summarizeText(result.stderr.toString())}',
    );
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
    _log(
      'github/gosmee channel_raw_output local_url=$localUrl stdout=$stdoutText',
    );

    try {
      final decoded = jsonDecode(stdoutText);
      if (decoded is Map<String, dynamic>) {
        final url = decoded['url']?.toString().trim();
        if (url == null || url.isEmpty) {
          throw const FormatException(
            'gosmee JSON output did not contain a valid public URL.',
          );
        }
        return url;
      }
      if (decoded is String) {
        final url = decoded.trim();
        if (url.isEmpty) {
          throw const FormatException('gosmee did not print a public URL.');
        }
        return url;
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
    final groupedIssues = <String, _QueuedGitHubBatch>{};
    for (final queuedIssue in queuedIssues) {
      groupedIssues.update(
        queuedIssue.project.key,
        (existing) => existing.add(queuedIssue.issue),
        ifAbsent: () => _QueuedGitHubBatch(
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
          'github/gosmee project=${batch.project.key} '
          'fetched_issues=${batch.issues.length}',
        );
        await batch.onBatch(
          IssueEventBatch(
            project: batch.project,
            issues: batch.issues,
            latestSeenUpdatedAt: batch.issues.last.updatedAt,
            sourceKind: 'github/gosmee',
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
    utf8.decoder.bind(stream).transform(const LineSplitter()).listen((line) {
      final message = 'github/gosmee project=${project.key} $level=$line';
      if (level == 'stderr') {
        _logger.error(message);
      } else {
        _logger.info(message);
      }
    });
  }

  void _log(String message) => _logger.info(message);

  void _logDebug(String message) => _logger.debug(message);

  void _logError(String message) => _logger.error(message);

  String _summarizeText(String value) {
    final singleLine = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= 240) {
      return singleLine.isEmpty ? '(empty)' : singleLine;
    }
    return '${singleLine.substring(0, 240)}...';
  }
}

class _QueuedGitHubIssue {
  _QueuedGitHubIssue({
    required this.project,
    required this.issue,
    required this.onBatch,
  });

  final ProjectConfig project;
  final GitHubIssueSummary issue;
  final IssueEventBatchHandler onBatch;
}

class _QueuedGitHubBatch {
  _QueuedGitHubBatch({
    required this.project,
    required this.onBatch,
    required List<GitHubIssueSummary> issues,
  }) : issues = List<GitHubIssueSummary>.from(issues);

  final ProjectConfig project;
  final IssueEventBatchHandler onBatch;
  final List<GitHubIssueSummary> issues;

  _QueuedGitHubBatch add(GitHubIssueSummary issue) {
    issues.removeWhere((existing) => existing.number == issue.number);
    issues.add(issue);
    return this;
  }
}
