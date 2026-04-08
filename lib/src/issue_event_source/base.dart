import 'dart:async';
import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

import '../config.dart';
import '../database.dart';
import '../issue_tracker_client.dart';

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
  RoutedIssueEventSource({required this.sources});

  final Map<IssueAssistantEventSourceKind, IssueEventSource> sources;

  @override
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    final startupReconcileProjects = projects
        .where(_shouldRunStartupReconciliation)
        .toList(growable: false);
    if (startupReconcileProjects.isNotEmpty) {
      await sources[IssueAssistantEventSourceKind.ghPolling]!.runOnce(
        projects: startupReconcileProjects,
        onBatch: onBatch,
      );
    }

    final projectsBySource =
        <IssueAssistantEventSourceKind, List<ProjectConfig>>{
          for (final eventSource in sources.keys)
            eventSource: <ProjectConfig>[],
        };
    for (final project in projects) {
      for (final projectSource in _registeredSourcesFor(project)) {
        final sourceProjects = projectsBySource[projectSource];
        if (sourceProjects == null) {
          throw StateError(
            'No issue event source registered for ${projectSource.name}.',
          );
        }
        sourceProjects.add(project);
      }
    }

    await Future.wait(
      projectsBySource.entries
          .where((entry) => entry.value.isNotEmpty)
          .map(
            (entry) => sources[entry.key]!.run(
              projects: entry.value,
              onBatch: onBatch,
            ),
          ),
    );
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) {
    return sources[IssueAssistantEventSourceKind.ghPolling]!.runOnce(
      projects: projects,
      onBatch: onBatch,
    );
  }

  @override
  Future<void> close() async {
    for (final source in sources.values) {
      await source.close();
    }
  }

  Iterable<IssueAssistantEventSourceKind> _registeredSourcesFor(
    ProjectConfig project,
  ) sync* {
    switch (project.issueAssistant.eventSource.type) {
      case IssueAssistantEventSourceKind.ghPolling:
        yield IssueAssistantEventSourceKind.ghPolling;
      case IssueAssistantEventSourceKind.teaPolling:
        yield IssueAssistantEventSourceKind.teaPolling;
      case IssueAssistantEventSourceKind.ghGosmee:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueAssistantEventSourceKind.ghPolling;
        }
        yield IssueAssistantEventSourceKind.ghGosmee;
      case IssueAssistantEventSourceKind.ghWebhookForward:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueAssistantEventSourceKind.ghPolling;
        }
        yield IssueAssistantEventSourceKind.ghWebhookForward;
      case IssueAssistantEventSourceKind.teaGosmee:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueAssistantEventSourceKind.teaPolling;
        }
        yield IssueAssistantEventSourceKind.teaGosmee;
    }
  }

  bool _shouldRunStartupReconciliation(ProjectConfig project) =>
      project.issueAssistant.eventSource.usesChannelEventSource;

  bool _shouldRunContinuousReconciliation(ProjectConfig project) =>
      project.issueAssistant.eventSource.usesChannelEventSource &&
      project.issueAssistant.eventSource is ChannelIssueEventSourceConfig &&
      (project.issueAssistant.eventSource as ChannelIssueEventSourceConfig)
              .reconciliation ==
          IssueAssistantReconciliationKind.continuous;
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
              switch (state.project.issueAssistant.eventSource) {
                PollingIssueEventSourceConfig(:final pollInterval) =>
                  pollInterval,
                ChannelIssueEventSourceConfig(:final reconcileInterval) =>
                  reconcileInterval,
              },
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

class _ProjectPollState {
  _ProjectPollState({required this.project, required this.nextDueAt});

  final ProjectConfig project;
  DateTime nextDueAt;
  bool isRunning = false;
}
