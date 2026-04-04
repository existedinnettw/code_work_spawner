import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'cli_responder.dart';
import 'config.dart';
import 'database.dart';
import 'github_client.dart';
import 'workspace_manager.dart';

class IssueAssistantApp {
  static final Logger _logger = Logger('code_work_spawner.app');

  IssueAssistantApp._({
    required this.config,
    required this.database,
    required this.githubClient,
    required this.responderRunner,
    required this.workspaceManager,
  });

  final AppConfig config;
  final AppDatabase database;
  final GitHubClient githubClient;
  final CliResponderRunner responderRunner;
  final WorkspaceManager workspaceManager;

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
    );
  }

  Future<void> run() async {
    while (true) {
      await runOnce();
      await Future<void>.delayed(_smallestPollInterval());
    }
  }

  Future<void> runOnce() async {
    _log('starting poll cycle projects=${config.projects.length}');
    for (final project in config.projects.values) {
      if (!project.issueAssistant.enabled) {
        _log('skip project=${project.key} reason=issue_assistant_disabled');
        continue;
      }
      await _pollProject(project);
    }
    _log('poll cycle completed');
  }

  Future<void> close() => database.close();

  Duration _smallestPollInterval() {
    return config.projects.values
        .where((project) => project.issueAssistant.enabled)
        .map((project) => project.issueAssistant.pollInterval)
        .fold<Duration>(
          const Duration(minutes: 5),
          (current, next) => next < current ? next : current,
        );
  }

  Future<void> _pollProject(ProjectConfig project) async {
    final pollRunId = await database.startPollRun(project.key);
    try {
      final repoDirectory = Directory(project.path);
      final repoExists = await repoDirectory.exists();
      final projectState = await database.findProjectState(project.key);
      final since = projectState?.lastSeenUpdatedAt == null
          ? null
          : DateTime.parse(projectState!.lastSeenUpdatedAt!);
      _log(
        'poll project=${project.key} repo=${project.repo} '
        'path=${project.path} path_exists=$repoExists '
        'since=${since?.toUtc().toIso8601String() ?? "initial"}',
      );
      final issues = await githubClient.fetchUpdatedIssues(
        repo: project.repo,
        since: since,
      );
      _log('project=${project.key} fetched_issues=${issues.length}');

      DateTime? latestSeen = since;
      for (final issue in issues) {
        if (latestSeen == null || issue.updatedAt.isAfter(latestSeen)) {
          latestSeen = issue.updatedAt;
        }
        await _processIssue(project, issue);
      }

      await database.upsertProjectState(
        projectKey: project.key,
        repo: project.repo,
        lastSeenUpdatedAt: latestSeen,
      );
      await database.finishPollRun(pollRunId: pollRunId, success: true);
      _log(
        'poll project=${project.key} completed latest_seen='
        '${latestSeen?.toUtc().toIso8601String() ?? "unchanged"}',
      );
    } catch (error) {
      await database.finishPollRun(
        pollRunId: pollRunId,
        success: false,
        error: error.toString(),
      );
      _log('poll project=${project.key} failed error=$error');
      rethrow;
    }
  }

  Future<void> _processIssue(
    ProjectConfig project,
    GitHubIssueSummary issue,
  ) async {
    final thread = await githubClient.fetchThread(
      repo: project.repo,
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
    String? workspacePath;
    Object? lastError;

    for (final responder in project.issueAssistant.responders) {
      final needsWorktree = _looksLikeBugVerification(thread);
      workspacePath = await workspaceManager.createEphemeralWorktree(
        project.path,
      );
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
      } finally {
        await workspaceManager.disposeEphemeralWorktree(workspacePath);
      }
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
      repo: project.repo,
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
