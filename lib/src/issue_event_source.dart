import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

import 'config.dart';
import 'database.dart';
import 'issue_tracker_client.dart';

typedef IssueEventBatchHandler = Future<void> Function(IssueEventBatch batch);

class IssueEventBatch {
  IssueEventBatch({
    required this.project,
    required this.issues,
    required this.latestSeenUpdatedAt,
    required this.sourceKind,
  });

  final ProjectConfig project;
  final List<GitHubIssueSummary> issues;
  final DateTime? latestSeenUpdatedAt;
  final String sourceKind;
}

abstract class IssueEventSource {
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  });

  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  });

  Future<void> close();
}

class RoutedIssueEventSource implements IssueEventSource {
  RoutedIssueEventSource({
    required this.pollingSource,
    required this.githubWebhookForwardSource,
  });

  final PollingIssueEventSource pollingSource;
  final GitHubWebhookForwardIssueEventSource githubWebhookForwardSource;

  @override
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    final pollingProjects = projects
        .where(
          (project) =>
              project.issueAssistant.eventSource ==
              IssueAssistantEventSourceKind.polling,
        )
        .toList(growable: false);
    final githubWebhookForwardProjects = projects
        .where(
          (project) =>
              project.issueAssistant.eventSource ==
              IssueAssistantEventSourceKind.githubWebhookForward,
        )
        .toList(growable: false);

    await Future.wait([
      if (pollingProjects.isNotEmpty)
        pollingSource.run(projects: pollingProjects, onBatch: onBatch),
      if (githubWebhookForwardProjects.isNotEmpty)
        githubWebhookForwardSource.run(
          projects: githubWebhookForwardProjects,
          onBatch: onBatch,
        ),
    ]);
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) {
    return pollingSource.runOnce(projects: projects, onBatch: onBatch);
  }

  @override
  Future<void> close() async {
    await githubWebhookForwardSource.close();
    await pollingSource.close();
  }
}

class PollingIssueEventSource implements IssueEventSource {
  PollingIssueEventSource({
    required this.database,
    required this.issueTrackerClient,
    required Logger logger,
  }) : _logger = logger;

  static const Duration _pollCoalescingWindow = Duration(seconds: 2);

  final AppDatabase database;
  final IssueTrackerClient issueTrackerClient;
  final Logger _logger;
  final Map<String, _ProjectPollState> _projectPollStates = {};
  final Set<Future<void>> _activePolls = <Future<void>>{};
  Timer? _schedulerTimer;
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

    final completer = Completer<void>();
    _runCompleter = completer;

    final now = DateTime.now();
    for (final project in projects) {
      _projectPollStates.putIfAbsent(
        project.key,
        () => _ProjectPollState(project: project, nextDueAt: now),
      );
    }
    unawaited(
      _triggerDueProjectPolls(
        source: 'startup',
        projects: projects,
        onBatch: onBatch,
      ),
    );

    try {
      await completer.future;
    } finally {
      _cancelScheduler();
    }
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    _log('starting poll cycle projects=${projects.length}');
    await _pollProjects(projects, onBatch: onBatch);
    _log('poll cycle completed');
  }

  @override
  Future<void> close() async {
    if (_isClosed || _isClosing) {
      return;
    }

    _isClosing = true;
    _cancelScheduler();
    _completeRunIfPending();
    await Future.wait(_activePolls.toList(growable: false));
    _isClosed = true;
    _isClosing = false;
  }

  Future<void> _triggerDueProjectPolls({
    required String source,
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    if (_isClosing || _isClosed) {
      return;
    }

    final now = DateTime.now();
    final dueStates = _projectPollStates.values
        .where((state) => !state.isRunning && !state.nextDueAt.isAfter(now))
        .toList(growable: false);
    if (dueStates.isEmpty) {
      _scheduleNextPoll(projects: projects, onBatch: onBatch);
      return;
    }

    late final Future<void> pollFuture;
    pollFuture = () async {
      for (final state in dueStates) {
        state.isRunning = true;
      }
      final stopwatch = Stopwatch()..start();
      final dueProjects = dueStates
          .map((state) => state.project)
          .toList(growable: false);
      _log(
        'poll tick source=$source projects=${dueProjects.map((p) => p.key).join(",")}',
      );
      try {
        await _pollProjects(dueProjects, onBatch: onBatch);
        stopwatch.stop();
        final batchCompletedAt = DateTime.now();
        for (final state in dueStates) {
          while (!state.nextDueAt.isAfter(batchCompletedAt)) {
            state.nextDueAt = state.nextDueAt.add(
              state.project.issueAssistant.pollInterval,
            );
          }
        }
        _log(
          'poll tick source=$source projects=${dueProjects.map((p) => p.key).join(",")} '
          'duration_ms=${stopwatch.elapsedMilliseconds}',
        );
      } catch (error, stackTrace) {
        stopwatch.stop();
        _logError(
          'poll tick source=$source projects=${dueProjects.map((p) => p.key).join(",")} '
          'duration_ms=${stopwatch.elapsedMilliseconds} error=$error',
        );
        if (_runCompleter != null) {
          _logError(
            'poll tick source=$source will_retry=true '
            'next_run=scheduled stack_trace=$stackTrace',
          );
        }
      } finally {
        for (final state in dueStates) {
          state.isRunning = false;
        }
        _activePolls.remove(pollFuture);
        _scheduleNextPoll(projects: projects, onBatch: onBatch);
      }
    }();

    _activePolls.add(pollFuture);
    await pollFuture;
  }

  Future<void> _pollProjects(
    List<ProjectConfig> projects, {
    required IssueEventBatchHandler onBatch,
  }) async {
    final pollRunIds = <String, int>{};
    final projectsByRepo = <String, ProjectConfig>{
      for (final project in projects) _projectRepoKey(project): project,
    };
    final sinceByProject = <String, DateTime?>{};
    final latestSeenByProject = <String, DateTime?>{};

    for (final project in projects) {
      pollRunIds[project.key] = await database.startPollRun(project.key);
      final repoDirectory = Directory(project.path);
      final repoExists = await repoDirectory.exists();
      final projectState = await database.findProjectState(project.key);
      final since = projectState?.lastSeenUpdatedAt == null
          ? null
          : DateTime.parse(projectState!.lastSeenUpdatedAt!);
      sinceByProject[project.key] = since;
      latestSeenByProject[project.key] = since;
      _log(
        'poll project=${project.key} repo=${project.repo} '
        'path=${project.path} path_exists=$repoExists '
        'since=${since?.toUtc().toIso8601String() ?? "initial"}',
      );
    }

    try {
      final issuesByProject = <String, List<GitHubIssueSummary>>{
        for (final project in projects) project.key: <GitHubIssueSummary>[],
      };
      for (final provider in IssueTrackerProvider.values) {
        final providerProjects = projects
            .where((project) => project.provider == provider)
            .toList(growable: false);
        if (providerProjects.isEmpty) {
          continue;
        }
        final providerSince = providerProjects
            .map((project) => sinceByProject[project.key])
            .whereType<DateTime>()
            .fold<DateTime?>(null, (current, next) {
              if (current == null || next.isBefore(current)) {
                return next;
              }
              return current;
            });

        final issues = await issueTrackerClient.fetchUpdatedIssuesForRepos(
          provider: provider,
          repos: providerProjects.map((project) => project.repoSlug),
          since: providerSince,
        );
        for (final issue in issues) {
          final project =
              projectsByRepo[_providerRepoKey(provider, issue.repoSlug)];
          if (project == null) {
            continue;
          }
          final since = sinceByProject[project.key];
          if (since != null && !issue.updatedAt.isAfter(since)) {
            continue;
          }
          issuesByProject[project.key]!.add(issue);
          final latestSeen = latestSeenByProject[project.key];
          if (latestSeen == null || issue.updatedAt.isAfter(latestSeen)) {
            latestSeenByProject[project.key] = issue.updatedAt;
          }
        }
      }

      for (final project in projects) {
        final projectIssues = issuesByProject[project.key]!;
        _log('project=${project.key} fetched_issues=${projectIssues.length}');
        _log(
          'project=${project.key} issue_queue=${projectIssues.length} '
          'max_concurrent=${project.issueAssistant.maxConcurrentIssues}',
        );
        await onBatch(
          IssueEventBatch(
            project: project,
            issues: projectIssues,
            latestSeenUpdatedAt: latestSeenByProject[project.key],
            sourceKind: 'polling',
          ),
        );

        await database.upsertProjectState(
          projectKey: project.key,
          repo: project.repo,
          lastSeenUpdatedAt: latestSeenByProject[project.key],
        );
        await database.finishPollRun(
          pollRunId: pollRunIds.remove(project.key)!,
          success: true,
        );
        _log(
          'poll project=${project.key} completed latest_seen='
          '${latestSeenByProject[project.key]?.toUtc().toIso8601String() ?? "unchanged"}',
        );
      }
    } catch (error) {
      for (final entry in pollRunIds.entries) {
        await database.finishPollRun(
          pollRunId: entry.value,
          success: false,
          error: error.toString(),
        );
        _log('poll project=${entry.key} failed error=$error');
      }
      rethrow;
    }
  }

  void _cancelScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }

  void _scheduleNextPoll({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) {
    if (_isClosing || _isClosed || _runCompleter == null) {
      return;
    }
    _cancelScheduler();

    DateTime? nextDueAt;
    for (final state in _projectPollStates.values) {
      if (state.isRunning) {
        continue;
      }
      if (nextDueAt == null || state.nextDueAt.isBefore(nextDueAt)) {
        nextDueAt = state.nextDueAt;
      }
    }
    if (nextDueAt == null) {
      return;
    }

    final scheduledAt = nextDueAt.add(_pollCoalescingWindow);
    final delay = scheduledAt.difference(DateTime.now());
    _schedulerTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(
        _triggerDueProjectPolls(
          source: 'interval',
          projects: projects,
          onBatch: onBatch,
        ),
      ),
    );
  }

  void _completeRunIfPending() {
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  String _projectRepoKey(ProjectConfig project) {
    return _providerRepoKey(project.provider, project.repoSlug);
  }

  String _providerRepoKey(
    IssueTrackerProvider provider,
    RepositorySlug repoSlug,
  ) {
    return '${provider.name}:${repoSlug.fullName}';
  }

  void _log(String message) {
    _logger.info(message);
  }

  void _logError(String message) {
    _logger.severe(message);
  }
}

class GitHubWebhookForwardIssueEventSource implements IssueEventSource {
  GitHubWebhookForwardIssueEventSource({
    required this.issueTrackerClient,
    required Logger logger,
  }) : _logger = logger;

  static const Duration _webhookCoalescingWindow = Duration(milliseconds: 500);

  final IssueTrackerClient issueTrackerClient;
  final Logger _logger;
  final Map<String, _QueuedWebhookIssue> _queuedIssues = {};
  final Set<Future<void>> _activeDispatches = <Future<void>>{};
  final Map<String, Process> _forwardProcesses = {};

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
    for (final project in githubProjects) {
      final process = await Process.start(issueTrackerClient.ghCommand, [
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
          _queuedIssues['${project.key}#${issue.number}'] = _QueuedWebhookIssue(
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
      _log('github/webhook-forward project=${project.key} $level=$line');
    });
  }

  void _log(String message) {
    _logger.info(message);
  }

  void _logError(String message) {
    _logger.severe(message);
  }
}

class _ProjectPollState {
  _ProjectPollState({required this.project, required this.nextDueAt});

  final ProjectConfig project;
  DateTime nextDueAt;
  bool isRunning = false;
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
