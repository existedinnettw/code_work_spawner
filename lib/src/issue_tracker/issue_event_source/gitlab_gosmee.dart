import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_logger.dart';
import '../../config/config.dart';
import '../../core/process_launcher.dart';
import '../client.dart';
import '../models.dart';
import 'base.dart';

class GitLabGosmeeIssueEventSource implements IssueEventSource {
  GitLabGosmeeIssueEventSource({
    required this.issueTrackerClient,
    required this.gosmeeCommand,
    required this.commandExecutor,
    required AppLogger logger,
  }) : _logger = logger;

  static const Duration _webhookCoalescingWindow = Duration(milliseconds: 500);
  static const Duration _processShutdownTimeout = Duration(seconds: 2);

  final IssueTrackerClient issueTrackerClient;
  final String gosmeeCommand;
  final ExternalCommandExecutor commandExecutor;
  final AppLogger _logger;
  final Map<String, _QueuedGitLabIssue> _queuedIssues = {};
  final Set<Future<void>> _activeDispatches = <Future<void>>{};
  final Map<String, StartedExternalCommand> _gosmeeProcesses = {};
  final Map<String, int> _webhookIdsByProject = {};
  final Map<String, String> _trackerProjectsByProject = {};

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

    final gitLabProjects = projects
        .where((project) => project.provider == IssueTrackerProvider.gitlab)
        .toList(growable: false);
    if (gitLabProjects.isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _runCompleter = completer;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _log(
      'gitlab/gosmee starting projects=${gitLabProjects.length} '
      'keys=${gitLabProjects.map((project) => project.key).join(",")}',
    );
    final repoToProject = {
      for (final project in gitLabProjects) project.repo: project,
    };
    for (final project in gitLabProjects) {
      _trackerProjectsByProject[project.key] = project.repo;
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
        _logError('gitlab/gosmee server error=$error');
        if (!_isClosing && !completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    final localUrl =
        'http://${server.address.address}:${server.port}/gitlab/webhooks';
    _log(
      'gitlab/gosmee listening local_url=$localUrl '
      'projects=${gitLabProjects.map((project) => project.key).join(",")}',
    );
    try {
      for (final project in gitLabProjects) {
        var setupStep = 'create_channel';
        try {
          _log(
            'gitlab/gosmee project=${project.key} setup_start '
            'repo=${project.repo} local_url=$localUrl',
          );
          _log(
            'gitlab/gosmee project=${project.key} create_channel '
            'command="$gosmeeCommand --output json client --new-url $localUrl"',
          );
          final publicUrl = await _createGosmeeChannelUrl(localUrl);
          _log(
            'gitlab/gosmee project=${project.key} channel_ready '
            'public_url=$publicUrl local_url=$localUrl',
          );
          setupStep = 'register_webhook';
          final webhookId = await issueTrackerClient.createGitLabIssueWebhook(
            trackerProject: project.repo,
            url: publicUrl,
          );
          _webhookIdsByProject[project.key] = webhookId;
          _log(
            'gitlab/gosmee project=${project.key} webhook_registered '
            'webhook_id=$webhookId repo=${project.repo}',
          );
          setupStep = 'start_client';
          _log(
            'gitlab/gosmee project=${project.key} start_client '
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
                'gitlab/gosmee process project=${project.key} exit_code=$exitCode',
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
            'gitlab/gosmee project=${project.key} setup_complete '
            'repo=${project.repo}',
          );
        } catch (error, stackTrace) {
          _logError(
            'gitlab/gosmee project=${project.key} setup_failed '
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
      'gitlab/gosmee does not support runOnce; use polling instead.',
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
    await _terminateProcesses(processes);

    final webhookIds = Map<String, int>.from(_webhookIdsByProject);
    _webhookIdsByProject.clear();
    for (final entry in webhookIds.entries) {
      try {
        _log(
          'gitlab/gosmee project=${entry.key} webhook_delete '
          'webhook_id=${entry.value}',
        );
        await issueTrackerClient.deleteGitLabWebhook(
          trackerProject: _trackerProjectsByProject[entry.key]!,
          webhookId: entry.value,
        );
      } catch (error) {
        _logError(
          'gitlab/gosmee delete webhook project=${entry.key} '
          'webhook_id=${entry.value} error=$error',
        );
      }
    }
    _trackerProjectsByProject.clear();

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
      'gitlab/gosmee webhook request method=${request.method} '
      'path=${request.uri.path} event=${request.headers.value("X-Gitlab-Event") ?? "(missing)"}',
    );
    if (request.method != 'POST') {
      _log(
        'gitlab/gosmee webhook ignored method=${request.method} '
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
      final projectNode = payload['project'];
      final fullName = projectNode is Map<String, dynamic>
          ? projectNode['path_with_namespace']?.toString()
          : null;
      final project = fullName == null ? null : repoToProject[fullName];
      final issue = _parseIssueFromPayload(payload, trackerProject: fullName);
      final objectKind = payload['object_kind']?.toString() ?? 'unknown';
      final action = _webhookAction(payload);
      if (project != null && issue != null) {
        _log(
          'gitlab/gosmee webhook accepted project=${project.key} '
          'repo=$fullName object_kind=$objectKind action=$action '
          'issue=${issue.number} state=${issue.state}',
        );
        if (issue.state == 'open' || issue.state == 'opened') {
          _queuedIssues['${project.key}#${issue.number}'] = _QueuedGitLabIssue(
            project: project,
            issue: issue,
            onBatch: onBatch,
          );
          _scheduleFlush();
        }
      } else {
        _log(
          'gitlab/gosmee webhook ignored repo=${fullName ?? "(missing)"} '
          'object_kind=$objectKind action=$action matched_project=${project != null} '
          'has_issue=${issue != null}',
        );
      }

      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
    } catch (error) {
      _logError('gitlab/gosmee payload error=$error');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('Invalid webhook payload.');
      await request.response.close();
    }
  }

  GitHubIssueSummary? _parseIssueFromPayload(
    Map<String, dynamic> payload, {
    required String? trackerProject,
  }) {
    if (trackerProject == null || trackerProject.isEmpty) {
      return null;
    }

    final issueNode = payload['issue'];
    if (issueNode is Map<String, dynamic>) {
      return GitHubIssueSummary.fromGitLabJson(trackerProject, issueNode);
    }

    final objectAttributes = payload['object_attributes'];
    if (objectAttributes is! Map<String, dynamic>) {
      return null;
    }
    final issueJson = <String, dynamic>{
      ...objectAttributes,
      if (!objectAttributes.containsKey('description') &&
          payload['description'] != null)
        'description': payload['description'],
      if (!objectAttributes.containsKey('author') && payload['user'] != null)
        'author': payload['user'],
      if (!objectAttributes.containsKey('web_url') &&
          objectAttributes['url'] != null)
        'web_url': objectAttributes['url'],
    };
    if (!issueJson.containsKey('iid') || !issueJson.containsKey('updated_at')) {
      return null;
    }
    return GitHubIssueSummary.fromGitLabJson(trackerProject, issueJson);
  }

  String _webhookAction(Map<String, dynamic> payload) {
    final objectAttributes = payload['object_attributes'];
    if (objectAttributes is Map<String, dynamic>) {
      final action = objectAttributes['action']?.toString().trim();
      if (action != null && action.isNotEmpty) {
        return action;
      }
    }
    return payload['action']?.toString() ?? 'unknown';
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
      'gitlab/gosmee channel_command_result local_url=$localUrl '
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
      'gitlab/gosmee channel_raw_output local_url=$localUrl stdout=$stdoutText',
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
    final groupedIssues = <String, _QueuedGitLabBatch>{};
    for (final queuedIssue in queuedIssues) {
      groupedIssues.update(
        queuedIssue.project.key,
        (existing) => existing.add(queuedIssue.issue),
        ifAbsent: () => _QueuedGitLabBatch(
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
          'gitlab/gosmee project=${batch.project.key} '
          'fetched_issues=${batch.issues.length}',
        );
        await batch.onBatch(
          IssueEventBatch(
            project: batch.project,
            issues: batch.issues,
            latestSeenUpdatedAt: batch.issues.last.updatedAt,
            sourceKind: 'gitlab/gosmee',
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
      final message = 'gitlab/gosmee project=${project.key} $level=$line';
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

  Future<void> _terminateProcesses(
    List<StartedExternalCommand> processes,
  ) async {
    for (final process in processes) {
      process.kill();
    }
    for (final process in processes) {
      await _awaitProcessExit(process);
    }
  }

  Future<void> _awaitProcessExit(StartedExternalCommand process) async {
    try {
      await process.exitCode.timeout(_processShutdownTimeout);
      return;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      return;
    }

    try {
      await process.exitCode.timeout(_processShutdownTimeout);
    } on TimeoutException {
      _logError(
        'gitlab/gosmee process did not exit after sigkill '
        'timeout_ms=${_processShutdownTimeout.inMilliseconds}',
      );
    } catch (_) {}
  }

  String _summarizeText(String value) {
    final singleLine = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= 240) {
      return singleLine.isEmpty ? '(empty)' : singleLine;
    }
    return '${singleLine.substring(0, 240)}...';
  }
}

class _QueuedGitLabIssue {
  _QueuedGitLabIssue({
    required this.project,
    required this.issue,
    required this.onBatch,
  });

  final ProjectConfig project;
  final GitHubIssueSummary issue;
  final IssueEventBatchHandler onBatch;
}

class _QueuedGitLabBatch {
  _QueuedGitLabBatch({
    required this.project,
    required this.onBatch,
    required List<GitHubIssueSummary> issues,
  }) : issues = List<GitHubIssueSummary>.from(issues);

  final ProjectConfig project;
  final IssueEventBatchHandler onBatch;
  final List<GitHubIssueSummary> issues;

  _QueuedGitLabBatch add(GitHubIssueSummary issue) {
    if (issues.every((existing) => existing.number != issue.number)) {
      issues.add(issue);
    }
    return this;
  }
}
