import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'cli_responder.dart';
import 'config.dart';
import 'database.dart';
import 'github_client.dart';
import 'notifier.dart';
import 'workspace_manager.dart';

class IssueAssistantApp {
  static final Logger _logger = Logger('code_work_spawner.app');
  static const Duration _pollCoalescingWindow = Duration(seconds: 2);

  IssueAssistantApp._({
    required this.config,
    required this.database,
    required this.githubClient,
    required this.responderRunner,
    required this.workspaceManager,
    required this.notifierRegistryFactory,
  });

  final AppConfig config;
  final AppDatabase database;
  final GitHubClient githubClient;
  final CliResponderRunner responderRunner;
  final WorkspaceManager workspaceManager;
  final NotifierRegistry Function(ProjectConfig project)
  notifierRegistryFactory;
  final Map<String, _ProjectPollState> _projectPollStates = {};
  final Set<Future<void>> _activePolls = <Future<void>>{};
  Timer? _schedulerTimer;
  Completer<void>? _runCompleter;
  bool _isClosing = false;
  bool _isClosed = false;

  static Future<IssueAssistantApp> open({
    required AppConfig config,
    required String databasePath,
    String ghCommand = 'gh',
  }) async {
    final database = AppDatabase.open(databasePath);
    return IssueAssistantApp._(
      config: config,
      database: database,
      githubClient: GitHubClient(ghCommand: ghCommand),
      responderRunner: CliResponderRunner(),
      workspaceManager: WorkspaceManager(worktreeRoot: config.worktreeDir),
      notifierRegistryFactory: (project) => NotifierRegistry.fromConfigs(
        project.issueAssistant.notifications,
        log: _logger.warning,
      ),
    );
  }

  Future<void> run() async {
    if (_isClosed) {
      throw StateError('IssueAssistantApp is already closed.');
    }
    if (_runCompleter != null) {
      return _runCompleter!.future;
    }

    final enabledProjects = config.projects.values
        .where((project) => project.issueAssistant.enabled)
        .toList(growable: false);
    if (enabledProjects.isEmpty) {
      _log('no enabled projects configured');
      return;
    }

    final completer = Completer<void>();
    _runCompleter = completer;

    final now = DateTime.now();
    for (final project in enabledProjects) {
      _projectPollStates.putIfAbsent(
        project.key,
        () => _ProjectPollState(project: project, nextDueAt: now),
      );
    }
    unawaited(_triggerDueProjectPolls(source: 'startup'));

    try {
      await completer.future;
    } finally {
      _cancelScheduler();
    }
  }

  Future<void> runOnce() async {
    _log('starting poll cycle projects=${config.projects.length}');
    final enabledProjects = <ProjectConfig>[];
    for (final project in config.projects.values) {
      if (!project.issueAssistant.enabled) {
        _log('skip project=${project.key} reason=issue_assistant_disabled');
        continue;
      }
      enabledProjects.add(project);
    }
    if (enabledProjects.isEmpty) {
      _log('no enabled projects configured');
      return;
    }
    await _pollProjects(enabledProjects);
    _log('poll cycle completed');
  }

  Future<void> close() async {
    if (_isClosed || _isClosing) {
      return;
    }

    _isClosing = true;
    _cancelScheduler();
    _completeRunIfPending();
    await Future.wait(_activePolls.toList(growable: false));
    await database.close();
    _isClosed = true;
    _isClosing = false;
  }

  Future<void> _triggerDueProjectPolls({required String source}) async {
    if (_isClosing || _isClosed) {
      return;
    }

    final now = DateTime.now();
    final dueStates = _projectPollStates.values
        .where((state) => !state.isRunning && !state.nextDueAt.isAfter(now))
        .toList(growable: false);
    if (dueStates.isEmpty) {
      _scheduleNextPoll();
      return;
    }

    late final Future<void> pollFuture;
    pollFuture = () async {
      for (final state in dueStates) {
        state.isRunning = true;
      }
      final stopwatch = Stopwatch()..start();
      final projects = dueStates
          .map((state) => state.project)
          .toList(growable: false);
      _log(
        'poll tick source=$source projects=${projects.map((p) => p.key).join(",")}',
      );
      try {
        await _pollProjects(projects);
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
          'poll tick source=$source projects=${projects.map((p) => p.key).join(",")} '
          'duration_ms=${stopwatch.elapsedMilliseconds}',
        );
      } catch (error, stackTrace) {
        stopwatch.stop();
        _logError(
          'poll tick source=$source projects=${projects.map((p) => p.key).join(",")} '
          'duration_ms=${stopwatch.elapsedMilliseconds} error=$error',
        );
        _cancelScheduler();
        if (!(_runCompleter?.isCompleted ?? true)) {
          _runCompleter!.completeError(error, stackTrace);
        }
      } finally {
        for (final state in dueStates) {
          state.isRunning = false;
        }
        _activePolls.remove(pollFuture);
        _scheduleNextPoll();
      }
    }();

    _activePolls.add(pollFuture);
    await pollFuture;
  }

  void _cancelScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }

  void _scheduleNextPoll() {
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
      () => unawaited(_triggerDueProjectPolls(source: 'interval')),
    );
  }

  void _completeRunIfPending() {
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _pollProjects(List<ProjectConfig> projects) async {
    final pollRunIds = <String, int>{};
    final projectsByRepo = <String, ProjectConfig>{
      for (final project in projects) project.repoSlug.fullName: project,
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
      final batchSince = sinceByProject.values
          .whereType<DateTime>()
          .fold<DateTime?>(null, (current, next) {
            if (current == null || next.isBefore(current)) {
              return next;
            }
            return current;
          });
      final issues = await githubClient.fetchUpdatedIssuesForRepos(
        repos: projects.map((project) => project.repoSlug),
        since: batchSince,
      );
      final issuesByProject = <String, List<GitHubIssueSummary>>{
        for (final project in projects) project.key: <GitHubIssueSummary>[],
      };
      for (final issue in issues) {
        final project = projectsByRepo[issue.repoSlug.fullName];
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

      for (final project in projects) {
        final projectIssues = issuesByProject[project.key]!;
        _log('project=${project.key} fetched_issues=${projectIssues.length}');
        _log(
          'project=${project.key} issue_queue=${projectIssues.length} '
          'max_concurrent=${project.issueAssistant.maxConcurrentIssues}',
        );
        await _processIssuesConcurrently(project, projectIssues);

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

  Future<void> _processIssuesConcurrently(
    ProjectConfig project,
    List<GitHubIssueSummary> issues,
  ) async {
    if (issues.isEmpty) {
      return;
    }

    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= issues.length) {
          return;
        }
        nextIndex += 1;
        final activeCount =
            currentIndex + 1 <= project.issueAssistant.maxConcurrentIssues
            ? currentIndex + 1
            : project.issueAssistant.maxConcurrentIssues;
        _log(
          'project=${project.key} process_issue issue=${issues[currentIndex].number} '
          'queue_index=${currentIndex + 1}/${issues.length} active_limit=$activeCount',
        );
        await _processIssue(project, issues[currentIndex]);
      }
    }

    final workerCount =
        issues.length < project.issueAssistant.maxConcurrentIssues
        ? issues.length
        : project.issueAssistant.maxConcurrentIssues;
    await Future.wait([for (var i = 0; i < workerCount; i += 1) worker()]);
  }

  Future<void> _processIssue(
    ProjectConfig project,
    GitHubIssueSummary issue,
  ) async {
    final notifierRegistry = notifierRegistryFactory(project);
    final thread = await githubClient.fetchThread(
      repo: project.repoSlug,
      issue: issue,
    );
    final fingerprint = _fingerprintThread(thread);
    final record = await database.findIssueThread(project.key, issue.number);
    if (record?.lastEvaluatedFingerprint == fingerprint) {
      _log(
        'skip issue=${project.key}#${issue.number} reason=fingerprint_unchanged',
      );
      return;
    }

    final trigger = _determineTrigger(project, thread);
    _log(
      'evaluate issue=${project.key}#${issue.number} '
      'comments=${thread.comments.length} trigger=$trigger',
    );
    final baseNotificationContext = NotificationContext(
      projectKey: project.key,
      repo: project.repo,
      issueNumber: issue.number,
      issueTitle: thread.issue.title,
      issueUrl: thread.issue.url,
      trigger: trigger,
    );
    if (trigger == 'mention') {
      await notifierRegistry.notify(
        event: NotificationEvent.mentionDetected,
        context: baseNotificationContext,
      );
    }
    final jobId = await database.createJob(
      projectKey: project.key,
      issueNumber: issue.number,
      fingerprint: fingerprint,
      trigger: trigger,
      status: JobStatus.queued,
    );

    await database.upsertIssueThread(
      projectKey: project.key,
      issueNumber: issue.number,
      fingerprint: fingerprint,
      updatedAt: issue.updatedAt,
      lastEvaluatedFingerprint: record?.lastEvaluatedFingerprint,
      lastDecision: record?.lastDecision,
      lastCommentId: record?.lastCommentId,
      lastCommentUrl: record?.lastCommentUrl,
    );

    await database.updateJobStatus(jobId, JobStatus.running);
    final forceReply = trigger == 'mention';
    final prompt = _buildPrompt(
      project: project,
      thread: thread,
      trigger: trigger,
    );

    if (project.issueAssistant.responders.isEmpty) {
      _logError(
        'issue=${project.key}#${issue.number} '
        'skipped no_responders_configured',
      );
      await database.upsertIssueThread(
        projectKey: project.key,
        issueNumber: issue.number,
        fingerprint: fingerprint,
        updatedAt: issue.updatedAt,
        lastEvaluatedFingerprint: fingerprint,
        lastDecision: record?.lastDecision,
        lastCommentId: record?.lastCommentId,
        lastCommentUrl: record?.lastCommentUrl,
      );
      await database.updateJobStatus(jobId, JobStatus.skipped);
      return;
    }

    ResponderResult? selectedResult;
    Object? lastError;
    final needsWorktree = _looksLikeBugVerification(thread);
    final workspacePath = await workspaceManager.createEphemeralWorktree(
      project.path,
    );
    _log(
      'issue=${project.key}#${issue.number} workspace_mode='
      'worktree workspace=$workspacePath',
    );

    try {
      for (final responder in project.issueAssistant.responders) {
        _log(
          'run responder=${responder.id} issue=${project.key}#${issue.number} '
          'mode_hint=${needsWorktree ? "bug_verification" : "planning"} '
          'workspace=$workspacePath',
        );

        try {
          final result = await responderRunner.run(
            responder: responder,
            project: project,
            thread: thread,
            prompt: prompt,
            forceReply: forceReply,
            workspacePath: workspacePath,
          );
          await database.addExecutionRun(
            jobId: jobId,
            responderId: result.responderId,
            mode: result.mode,
            decision: result.decision,
            success: true,
            workspacePath: workspacePath,
            stdout: result.rawStdout,
            stderr: result.rawStderr,
          );
          _logResponderOutput(
            responderId: responder.id,
            issueKey: '${project.key}#${issue.number}',
            stdout: result.rawStdout,
            stderr: result.rawStderr,
          );
          _log(
            'responder=${responder.id} issue=${project.key}#${issue.number}, '
            'title="${thread.issue.title}", '
            'decision=${result.decision}, mode=${result.mode}',
          );
          selectedResult = forceReply && !result.shouldReply
              ? result.forceReply()
              : result;
          if (forceReply && !result.shouldReply) {
            _log(
              'responder=${responder.id} issue=${project.key}#${issue.number} '
              'override=force_reply original_decision=${result.decision}',
            );
          }
          break;
        } catch (error) {
          lastError = error;
          final rawStdout = switch (error) {
            CliResponderExecutionException(:final rawStdout) => rawStdout,
            _ => '',
          };
          final rawStderr = switch (error) {
            CliResponderExecutionException(:final rawStderr) => rawStderr,
            _ => error.toString(),
          };
          _logResponderOutput(
            responderId: responder.id,
            issueKey: '${project.key}#${issue.number}',
            stdout: rawStdout,
            stderr: rawStderr,
          );
          _log(
            'responder=${responder.id} issue=${project.key}#${issue.number} '
            'failed error=$error',
          );
          await notifierRegistry.notify(
            event: NotificationEvent.responderFailed,
            context: NotificationContext(
              projectKey: project.key,
              repo: project.repo,
              issueNumber: issue.number,
              issueTitle: thread.issue.title,
              issueUrl: thread.issue.url,
              trigger: trigger,
              responderId: responder.id,
              errorSummary: error.toString(),
            ),
          );
          await database.addExecutionRun(
            jobId: jobId,
            responderId: responder.id,
            mode: 'error',
            decision: 'no_reply',
            success: false,
            workspacePath: workspacePath,
            stdout: rawStdout,
            stderr: rawStderr,
          );
        }
      }
    } finally {
      await workspaceManager.disposeEphemeralWorktree(workspacePath);
    }

    if (selectedResult == null) {
      await database.updateJobStatus(jobId, JobStatus.failed);
      _log(
        'issue=${project.key}#${issue.number} failed no_responder_succeeded',
      );
      throw StateError(
        'All responders failed for ${project.key}#${issue.number}: $lastError',
      );
    }

    if (!selectedResult.shouldReply) {
      await database.upsertIssueThread(
        projectKey: project.key,
        issueNumber: issue.number,
        fingerprint: fingerprint,
        updatedAt: issue.updatedAt,
        lastEvaluatedFingerprint: fingerprint,
        lastDecision: selectedResult.decision,
        lastCommentId: record?.lastCommentId,
        lastCommentUrl: record?.lastCommentUrl,
      );
      await database.updateJobStatus(jobId, JobStatus.completed);
      _log('issue=${project.key}#${issue.number} completed decision=no_reply');
      await notifierRegistry.notify(
        event: NotificationEvent.noReply,
        context: NotificationContext(
          projectKey: project.key,
          repo: project.repo,
          issueNumber: issue.number,
          issueTitle: thread.issue.title,
          issueUrl: thread.issue.url,
          trigger: trigger,
          mode: selectedResult.mode,
          responderId: selectedResult.responderId,
          decision: selectedResult.decision,
          summary: selectedResult.summary,
        ),
      );
      return;
    }

    final commentBody = await _decorateComment(
      project: project,
      issueNumber: issue.number,
      trigger: trigger,
      fingerprint: fingerprint,
      markdown: selectedResult.markdown,
    );
    final posted = await githubClient.createIssueComment(
      repo: project.repoSlug,
      issueNumber: issue.number,
      body: commentBody,
    );

    await database.addCommentRecord(
      projectKey: project.key,
      issueNumber: issue.number,
      fingerprint: fingerprint,
      githubCommentId: posted.id,
      githubCommentUrl: posted.url,
      body: posted.body,
    );
    await database.upsertIssueThread(
      projectKey: project.key,
      issueNumber: issue.number,
      fingerprint: fingerprint,
      updatedAt: issue.updatedAt,
      lastEvaluatedFingerprint: fingerprint,
      lastDecision: selectedResult.decision,
      lastCommentId: posted.id,
      lastCommentUrl: posted.url,
    );
    await database.updateJobStatus(jobId, JobStatus.completed);
    _log('issue=${project.key}#${issue.number} posted_comment_id=${posted.id}');
    await notifierRegistry.notify(
      event: NotificationEvent.replyPosted,
      context: NotificationContext(
        projectKey: project.key,
        repo: project.repo,
        issueNumber: issue.number,
        issueTitle: thread.issue.title,
        issueUrl: thread.issue.url,
        trigger: trigger,
        mode: selectedResult.mode,
        responderId: selectedResult.responderId,
        decision: selectedResult.decision,
        summary: selectedResult.summary,
      ),
    );
  }

  String _buildPrompt({
    required ProjectConfig project,
    required IssueThread thread,
    required String trigger,
  }) {
    final payload = <String, String>{
      'repo': project.repo,
      'project_key': project.key,
      'project_path': project.path,
      'issue_number': thread.issue.number.toString(),
      'issue_title': thread.issue.title,
      'issue_body': thread.issue.body,
      'issue_url': thread.issue.url,
      'thread_json': const JsonEncoder.withIndent(
        '  ',
      ).convert(thread.toJson()),
      'mention_triggers': project.issueAssistant.mentionTriggers.join(', '),
      'trigger': trigger,
      'capabilities': project.issueAssistant.capabilities
          .map((capability) => capability.name)
          .join(', '),
    };
    return renderTemplate(project.issueAssistant.prompt, payload);
  }

  String _determineTrigger(ProjectConfig project, IssueThread thread) {
    final latestText = thread.latestComment?.body ?? thread.issue.body;
    final latestAuthor =
        thread.latestComment?.userLogin ?? thread.issue.userLogin;
    final latestTextLower = latestText.toLowerCase();
    final mention = project.issueAssistant.mentionTriggers.any(
      (trigger) => latestTextLower.contains(trigger.toLowerCase()),
    );
    if (mention && !_looksLikeBot(project, latestAuthor)) {
      return 'mention';
    }
    return 'update';
  }

  bool _looksLikeBot(ProjectConfig project, String login) {
    final lower = login.toLowerCase();
    if (lower.endsWith('[bot]')) {
      return true;
    }
    return lower.contains(project.issueAssistant.commentTag.toLowerCase());
  }

  bool _looksLikeBugVerification(IssueThread thread) {
    final text = [
      thread.issue.title,
      thread.issue.body,
      if (thread.latestComment != null) thread.latestComment!.body,
    ].join('\n').toLowerCase();
    return text.contains('bug') &&
        (text.contains('verify') ||
            text.contains('test') ||
            text.contains('reproduce'));
  }

  String _fingerprintThread(IssueThread thread) {
    final bytes = utf8.encode(jsonEncode(thread.toJson()));
    return sha256.convert(bytes).toString();
  }

  Future<String> _decorateComment({
    required ProjectConfig project,
    required int issueNumber,
    required String trigger,
    required String fingerprint,
    required String markdown,
  }) async {
    var ghLogin = 'unknown';
    try {
      ghLogin = await githubClient.getAuthenticatedLogin() ?? 'unknown';
    } catch (error) {
      _log(
        'comment_identity_lookup_failed project=${project.key} '
        'issue=$issueNumber error=$error',
      );
    }

    final templateValues = <String, String>{
      'repo': project.repo,
      'project_key': project.key,
      'issue_number': issueNumber.toString(),
      'trigger': trigger,
      'comment_tag': project.issueAssistant.commentTag,
      'fingerprint': fingerprint,
      'gh_login': ghLogin,
    };
    final prefix = renderTemplate(
      project.issueAssistant.commentPrefixTemplate,
      templateValues,
    ).trim();
    final footer = renderTemplate(
      project.issueAssistant.commentFooterTemplate,
      templateValues,
    ).trim();

    final sections = <String>[
      if (prefix.isNotEmpty) prefix,
      markdown.trim(),
      if (footer.isNotEmpty) footer,
      '<!-- ${project.issueAssistant.commentTag}:$fingerprint -->',
    ];
    return sections.where((section) => section.isNotEmpty).join('\n\n');
  }

  void _log(String message) {
    _logger.info(message);
  }

  void _logError(String message) {
    _logger.severe(message);
  }

  void _logResponderOutput({
    required String responderId,
    required String issueKey,
    required String stdout,
    required String stderr,
  }) {
    if (stdout.isNotEmpty) {
      _log('responder=$responderId issue=$issueKey stream=stdout\n$stdout');
    }
    if (stderr.isNotEmpty) {
      _log('responder=$responderId issue=$issueKey stream=stderr\n$stderr');
    }
  }
}

class _ProjectPollState {
  _ProjectPollState({required this.project, required this.nextDueAt});

  final ProjectConfig project;
  DateTime nextDueAt;
  bool isRunning = false;
}
