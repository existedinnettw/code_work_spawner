import 'dart:async';
import 'dart:io';

import '../../config/app_logger.dart';
import '../../config/config.dart';
import '../../core/database.dart';
import '../client.dart';
import '../models.dart';

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
  RoutedIssueEventSource({required this.sources, required AppLogger logger})
    : _logger = logger;

  final Map<IssueTrackerEventSourceKind, IssueEventSource> sources;
  final AppLogger _logger;

  @override
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    for (final project in projects) {
      _log(_routeLogMessage(project));
    }
    final startupReconcileProjects = projects
        .where(_shouldRunStartupReconciliation)
        .toList(growable: false);
    if (startupReconcileProjects.isNotEmpty) {
      _log(
        'route startup_reconciliation projects=${startupReconcileProjects.map((project) => project.key).join(",")}',
      );
      await sources[IssueTrackerEventSourceKind.ghPolling]!.runOnce(
        projects: startupReconcileProjects,
        onBatch: onBatch,
      );
    }

    final projectsBySource = <IssueTrackerEventSourceKind, List<ProjectConfig>>{
      for (final eventSource in sources.keys) eventSource: <ProjectConfig>[],
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

    final routedEntries = projectsBySource.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    for (final entry in routedEntries) {
      _log(
        'route source=${_eventSourceKindValue(entry.key)} '
        'projects=${entry.value.map((project) => project.key).join(",")}',
      );
    }

    await Future.wait(
      routedEntries.map(
        (entry) =>
            sources[entry.key]!.run(projects: entry.value, onBatch: onBatch),
      ),
    );
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) {
    for (final project in projects) {
      _log('run_once ${_routeLogMessage(project)}');
    }
    return sources[IssueTrackerEventSourceKind.ghPolling]!.runOnce(
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

  Iterable<IssueTrackerEventSourceKind> _registeredSourcesFor(
    ProjectConfig project,
  ) sync* {
    switch (project.issueAssistant.eventSource.type) {
      case IssueTrackerEventSourceKind.ghPolling:
        yield IssueTrackerEventSourceKind.ghPolling;
      case IssueTrackerEventSourceKind.glabPolling:
        yield IssueTrackerEventSourceKind.glabPolling;
      case IssueTrackerEventSourceKind.teaPolling:
        yield IssueTrackerEventSourceKind.teaPolling;
      case IssueTrackerEventSourceKind.opPolling:
        yield IssueTrackerEventSourceKind.opPolling;
      case IssueTrackerEventSourceKind.ghGosmee:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueTrackerEventSourceKind.ghPolling;
        }
        yield IssueTrackerEventSourceKind.ghGosmee;
      case IssueTrackerEventSourceKind.glabGosmee:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueTrackerEventSourceKind.glabPolling;
        }
        yield IssueTrackerEventSourceKind.glabGosmee;
      case IssueTrackerEventSourceKind.ghWebhookForward:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueTrackerEventSourceKind.ghPolling;
        }
        yield IssueTrackerEventSourceKind.ghWebhookForward;
      case IssueTrackerEventSourceKind.teaGosmee:
        if (_shouldRunContinuousReconciliation(project)) {
          yield IssueTrackerEventSourceKind.teaPolling;
        }
        yield IssueTrackerEventSourceKind.teaGosmee;
    }
  }

  bool _shouldRunStartupReconciliation(ProjectConfig project) =>
      project.issueAssistant.eventSource.usesChannelEventSource;

  bool _shouldRunContinuousReconciliation(ProjectConfig project) =>
      project.issueAssistant.eventSource.usesChannelEventSource &&
      project.issueAssistant.eventSource is ChannelIssueEventSourceConfig &&
      (project.issueAssistant.eventSource as ChannelIssueEventSourceConfig)
              .reconciliation ==
          IssueTrackerReconciliationKind.continuous;

  String _routeLogMessage(ProjectConfig project) {
    final eventSource = project.issueAssistant.eventSource;
    final routedSources = _registeredSourcesFor(
      project,
    ).map(_eventSourceKindValue).join(',');
    return 'route project=${project.key} '
        'provider=${project.provider.name} '
        'event_source=${_eventSourceKindValue(eventSource.type)} '
        'startup_reconciliation=${_shouldRunStartupReconciliation(project)} '
        'continuous_reconciliation=${_shouldRunContinuousReconciliation(project)} '
        '${_eventSourceSettings(eventSource)} '
        'routed_sources=$routedSources';
  }

  String _eventSourceSettings(IssueEventSourceConfig eventSource) {
    return switch (eventSource) {
      PollingIssueEventSourceConfig(:final pollInterval) =>
        'poll_interval=$pollInterval',
      ChannelIssueEventSourceConfig(
        :final reconciliation,
        :final reconcileInterval,
      ) =>
        'reconciliation=${_reconciliationKindValue(reconciliation)} '
            'reconcile_interval=$reconcileInterval',
    };
  }

  void _log(String message) {
    _logger.info(message);
  }
}

class PollingIssueEventSource implements IssueEventSource {
  PollingIssueEventSource({
    required this.database,
    required this.issueTrackerClient,
    required AppLogger logger,
  }) : _logger = logger;

  static const Duration _pollCoalescingWindow = Duration(seconds: 2);

  final AppDatabase database;
  final IssueTrackerClient issueTrackerClient;
  final AppLogger _logger;
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
          trackerProjects: providerProjects.map((project) => project.repo),
          since: providerSince,
        );
        for (final issue in issues) {
          final project =
              projectsByRepo[_providerRepoKey(provider, issue.trackerProject)];
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
    return _providerRepoKey(project.provider, project.repo);
  }

  String _providerRepoKey(
    IssueTrackerProvider provider,
    String trackerProject,
  ) {
    return '${provider.name}:$trackerProject';
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

String _eventSourceKindValue(IssueTrackerEventSourceKind value) {
  return switch (value) {
    IssueTrackerEventSourceKind.ghPolling => 'gh/polling',
    IssueTrackerEventSourceKind.glabPolling => 'glab/polling',
    IssueTrackerEventSourceKind.teaPolling => 'tea/polling',
    IssueTrackerEventSourceKind.opPolling => 'op/polling',
    IssueTrackerEventSourceKind.ghGosmee => 'gh/gosmee',
    IssueTrackerEventSourceKind.glabGosmee => 'glab/gosmee',
    IssueTrackerEventSourceKind.ghWebhookForward => 'gh/webhook-forward',
    IssueTrackerEventSourceKind.teaGosmee => 'tea/gosmee',
  };
}

String _reconciliationKindValue(IssueTrackerReconciliationKind value) {
  return switch (value) {
    IssueTrackerReconciliationKind.startupOnly => 'startup-only',
    IssueTrackerReconciliationKind.continuous => 'continuous',
  };
}
