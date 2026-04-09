import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'app_logger.dart';
import 'cli_responder.dart';
import 'config.dart';
import 'database.dart';
import 'issue_event_source/base.dart';
import 'issue_event_source/gitea_gosmee.dart';
import 'issue_event_source/github_gosmee.dart';
import 'issue_event_source/github_webhook_forward.dart';
import 'issue_tracker_client.dart';
import 'notifier.dart';
import 'workspace_manager.dart';

class IssueAssistantApp {
  static final AppLogger _logger = AppLogger('code_work_spawner.app');

  IssueAssistantApp._({
    required this.config,
    required this.database,
    required this.issueTrackerClient,
    required this.issueEventSource,
    required this.responderRunner,
    required this.workspaceManager,
    required this.notifierRegistryFactory,
  });

  final AppConfig config;
  final AppDatabase database;
  final IssueTrackerClient issueTrackerClient;
  final IssueEventSource issueEventSource;
  final CliResponderRunner responderRunner;
  final WorkspaceManager workspaceManager;
  final Map<String, Future<void>> _issueProcessingFutures = {};
  final NotifierRegistry Function(ProjectConfig project)
  notifierRegistryFactory;

  static Future<IssueAssistantApp> open({
    required AppConfig config,
    required String databasePath,
    String ghCommand = 'gh',
    String glabCommand = 'glab',
    String gosmeeCommand = 'gosmee',
    String teaCommand = 'tea',
  }) async {
    final database = AppDatabase.open(databasePath);
    final issueTrackerClient = IssueTrackerClient(
      ghCommand: ghCommand,
      glabCommand: glabCommand,
      teaCommand: teaCommand,
    );
    final pollingIssueEventSource = PollingIssueEventSource(
      database: database,
      issueTrackerClient: issueTrackerClient,
      logger: _logger,
    );
    return IssueAssistantApp._(
      config: config,
      database: database,
      issueTrackerClient: issueTrackerClient,
      issueEventSource: RoutedIssueEventSource(
        sources: {
          IssueAssistantEventSourceKind.ghPolling: pollingIssueEventSource,
          IssueAssistantEventSourceKind.glabPolling: pollingIssueEventSource,
          IssueAssistantEventSourceKind.teaPolling: pollingIssueEventSource,
          IssueAssistantEventSourceKind.opPolling: pollingIssueEventSource,
          IssueAssistantEventSourceKind.ghGosmee: GitHubGosmeeIssueEventSource(
            issueTrackerClient: issueTrackerClient,
            gosmeeCommand: gosmeeCommand,
            logger: _logger,
          ),
          IssueAssistantEventSourceKind.ghWebhookForward:
              GitHubWebhookForwardIssueEventSource(
                issueTrackerClient: issueTrackerClient,
                logger: _logger,
              ),
          IssueAssistantEventSourceKind.teaGosmee: GiteaGosmeeIssueEventSource(
            issueTrackerClient: issueTrackerClient,
            gosmeeCommand: gosmeeCommand,
            logger: _logger,
          ),
        },
      ),
      responderRunner: CliResponderRunner(),
      workspaceManager: WorkspaceManager(worktreeRoot: config.worktreeDir),
      notifierRegistryFactory: (project) => NotifierRegistry.fromConfigs(
        project.issueAssistant.notifications,
        log: _logger.warning,
      ),
    );
  }

  Future<void> run() async {
    final enabledProjects = config.projects.values
        .where((project) => project.issueAssistant.enabled)
        .toList(growable: false);
    if (enabledProjects.isEmpty) {
      _log('no enabled projects configured');
      return;
    }
    await issueEventSource.run(
      projects: enabledProjects,
      onBatch: _processBatch,
    );
  }

  Future<void> runOnce() async {
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
    await issueEventSource.runOnce(
      projects: enabledProjects,
      onBatch: _processBatch,
    );
  }

  Future<void> close() async {
    await issueEventSource.close();
    await database.close();
  }

  Future<void> _processBatch(IssueEventBatch batch) {
    _log(
      'project=${batch.project.key} tracker_source=${batch.sourceKind} '
      'fetched_issues=${batch.issues.length}',
    );
    return _processIssuesConcurrently(batch.project, batch.issues);
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
        await _processIssueSerialized(project, issues[currentIndex]);
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
    final thread = await issueTrackerClient.fetchThread(
      provider: project.provider,
      trackerProject: project.repo,
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
    final workspacePath = await workspaceManager.createEphemeralWorkspace(
      project,
    );
    _log(
      'issue=${project.key}#${issue.number} workspace_mode='
      'worktree scm=${project.scm.provider.name} workspace=$workspacePath',
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
      await workspaceManager.disposeEphemeralWorkspace(project, workspacePath);
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
    final posted = await issueTrackerClient.createIssueComment(
      provider: project.provider,
      trackerProject: project.repo,
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

  Future<void> _processIssueSerialized(
    ProjectConfig project,
    GitHubIssueSummary issue,
  ) async {
    final issueKey = '${project.key}#${issue.number}';
    final previous = _issueProcessingFutures[issueKey];

    late final Future<void> current;
    current = () async {
      if (previous != null) {
        await previous.catchError((_) {});
      }
      await _processIssue(project, issue);
    }();

    _issueProcessingFutures[issueKey] = current;
    try {
      await current;
    } finally {
      if (identical(_issueProcessingFutures[issueKey], current)) {
        _issueProcessingFutures.remove(issueKey);
      }
    }
  }

  String _buildPrompt({
    required ProjectConfig project,
    required IssueThread thread,
    required String trigger,
  }) {
    final payload = <String, String>{
      'repo': project.repo,
      'tracker_provider': project.provider.name,
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
    var trackerLogin = 'unknown';
    try {
      trackerLogin =
          await issueTrackerClient.getAuthenticatedLogin(
            provider: project.provider,
          ) ??
          'unknown';
    } catch (error) {
      _log(
        'comment_identity_lookup_failed project=${project.key} '
        'issue=$issueNumber error=$error',
      );
    }

    final trackerCli = issueTrackerClient.trackerCliName(project.provider);
    final templateValues = <String, String>{
      'repo': project.repo,
      'project_key': project.key,
      'issue_number': issueNumber.toString(),
      'trigger': trigger,
      'comment_tag': project.issueAssistant.commentTag,
      'fingerprint': fingerprint,
      'tracker_cli': trackerCli,
      'tracker_login': trackerLogin,
      'gh_login': trackerLogin,
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
