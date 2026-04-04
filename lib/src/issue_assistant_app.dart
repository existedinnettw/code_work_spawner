import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cli_responder.dart';
import 'config.dart';
import 'database.dart';
import 'github_client.dart';
import 'workspace_manager.dart';

class IssueAssistantApp {
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
      workspaceManager: WorkspaceManager(),
    );
  }

  Future<void> run() async {
    while (true) {
      await runOnce();
      await Future<void>.delayed(_smallestPollInterval());
    }
  }

  Future<void> runOnce() async {
    for (final project in config.projects.values) {
      if (!project.issueAssistant.enabled) {
        continue;
      }
      await _pollProject(project);
    }
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
      final projectState = await database.findProjectState(project.key);
      final since = projectState?.lastSeenUpdatedAt == null
          ? null
          : DateTime.parse(projectState!.lastSeenUpdatedAt!);
      final issues = await githubClient.fetchUpdatedIssues(
        repo: project.repo,
        since: since,
      );

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
    } catch (error) {
      await database.finishPollRun(
        pollRunId: pollRunId,
        success: false,
        error: error.toString(),
      );
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
      return;
    }

    final trigger = _determineTrigger(project, thread);
    final jobId = await database.createJob(
      projectKey: project.key,
      issueNumber: issue.number,
      fingerprint: fingerprint,
      trigger: trigger,
      status: 'queued',
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

    await database.updateJobStatus(jobId, 'running');
    final forceReply = trigger == 'mention';
    final prompt = _buildPrompt(
      project: project,
      thread: thread,
      trigger: trigger,
    );

    ResponderResult? selectedResult;
    String? workspacePath;
    Object? lastError;

    for (final responder in project.issueAssistant.responders) {
      final needsWorktree = _looksLikeBugVerification(thread);
      workspacePath = needsWorktree
          ? await workspaceManager.createEphemeralWorktree(project.path)
          : project.path;

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
        selectedResult = result;
        break;
      } catch (error) {
        lastError = error;
        await database.addExecutionRun(
          jobId: jobId,
          responderId: responder.id,
          mode: 'error',
          decision: 'no_reply',
          success: false,
          workspacePath: workspacePath,
          stdout: '',
          stderr: error.toString(),
        );
      } finally {
        if (workspacePath != project.path) {
          await workspaceManager.disposeEphemeralWorktree(workspacePath);
        }
      }
    }

    if (selectedResult == null) {
      await database.updateJobStatus(jobId, 'failed');
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
      await database.updateJobStatus(jobId, 'completed');
      return;
    }

    final commentBody = _decorateComment(
      tag: project.issueAssistant.commentTag,
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
    await database.updateJobStatus(jobId, 'completed');
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

  String _decorateComment({
    required String tag,
    required String fingerprint,
    required String markdown,
  }) {
    return '$markdown\n\n<!-- $tag:$fingerprint -->';
  }
}
