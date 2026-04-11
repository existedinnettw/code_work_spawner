import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunOnceConcurrencyTests() {
  /// ```gherkin
  /// Feature: Issue thread assistant polling
  ///
  ///   As a maintainer using the issue assistant
  ///   I want issue thread events to be evaluated through configured responders
  ///   So that users get help only when the thread actually needs a response
  /// ```
  group('IssueAssistantApp.runOnce', () {
    /// ```gherkin
    /// Scenario: Process multiple issues concurrently up to the configured limit
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing three planning mentions
    ///   And a responder that sleeps for one second while logging each issue number
    ///   And an orchestrator-style config with maxConcurrentIssues set to three
    ///   When the app processes one polling cycle
    ///   Then all responder executions start before the first responder finishes
    ///   And all three issues still receive replies
    /// ```
    test('Process multiple issues concurrently up to the configured limit', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-concurrent-issues-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And GitHub issue data containing three planning mentions.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final issueData = [
        {
          'number': 41,
          'title': 'First planning request',
          'body': 'first',
          'state': 'open',
          'html_url': 'https://example.test/issues/41',
          'updated_at': '2026-04-04T16:20:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
        {
          'number': 42,
          'title': 'Second planning request',
          'body': 'second',
          'state': 'open',
          'html_url': 'https://example.test/issues/42',
          'updated_at': '2026-04-04T16:21:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
        {
          'number': 43,
          'title': 'Third planning request',
          'body': 'third',
          'state': 'open',
          'html_url': 'https://example.test/issues/43',
          'updated_at': '2026-04-04T16:22:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {
          41: [
            {
              'id': 410,
              'body': '@helper first',
              'html_url': 'https://example.test/issues/41#issuecomment-410',
              'created_at': '2026-04-04T16:20:00Z',
              'updated_at': '2026-04-04T16:20:00Z',
              'user': {'login': 'reporter'},
            },
          ],
          42: [
            {
              'id': 420,
              'body': '@helper second',
              'html_url': 'https://example.test/issues/42#issuecomment-420',
              'created_at': '2026-04-04T16:21:00Z',
              'updated_at': '2026-04-04T16:21:00Z',
              'user': {'login': 'reporter'},
            },
          ],
          43: [
            {
              'id': 430,
              'body': '@helper third',
              'html_url': 'https://example.test/issues/43#issuecomment-430',
              'created_at': '2026-04-04T16:22:00Z',
              'updated_at': '2026-04-04T16:22:00Z',
              'user': {'login': 'reporter'},
            },
          ],
        },
        postCommentIssueNumbers: {41, 42, 43},
        ghLog: ghLog,
      );

      // And a responder that sleeps long enough to expose overlap despite scheduler jitter.
      final eventLog = File(p.join(sandbox.path, 'responder-events.log'));
      final responderScript = File(p.join(sandbox.path, 'responder-slow.sh'));
      await writeDelayedLoggingResponderScript(
        responderScript,
        eventLog: eventLog,
        delay: const Duration(seconds: 2),
        response: {
          'decision': 'reply',
          'mode': 'planning',
          'markdown': 'parallel reply',
          'summary': 'completed after delay',
        },
      );

      // And an orchestrator-style config with maxConcurrentIssues set to three.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    maxConcurrentIssues: 3
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    issueTracker:
      eventSource:
        pollInterval: 5m
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      await app.close();

      // Then all responder executions start before the first responder finishes.
      final eventLines = await eventLog.readAsLines();
      final startLines = eventLines
          .where((line) => line.startsWith('start:'))
          .toList(growable: false);
      final endLines = eventLines
          .where((line) => line.startsWith('end:'))
          .toList(growable: false);
      final startTimes =
          startLines
              .map((line) => int.parse(line.split(':').last))
              .toList(growable: false)
            ..sort();
      final endTimes =
          endLines
              .map((line) => int.parse(line.split(':').last))
              .toList(growable: false)
            ..sort();
      expect(startLines, hasLength(3));
      expect(endLines, hasLength(3));
      expect(endTimes.first, greaterThanOrEqualTo(startTimes.last));

      // And all three issues still receive replies.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/41/comments'),
            )
            .length,
        2,
      );
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/42/comments'),
            )
            .length,
        2,
      );
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/43/comments'),
            )
            .length,
        2,
      );
    });

    /// ```gherkin
    /// Scenario: Fall back to unknown identity when gh user lookup fails
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing an explicit assistant mention
    ///   And a responder that emits a planning reply
    ///   And a fake gh command that fails the authenticated user lookup
    ///   When the app processes one polling cycle
    ///   Then it still posts one comment
    ///   And the visible automation markers use the unknown identity fallback
    /// ```
    test('Fall back to unknown identity when gh user lookup fails', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-gh-fallback-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And GitHub issue data containing an explicit assistant mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      final issueData = [
        {
          'number': 33,
          'title': 'Fallback identity',
          'body': 'identity',
          'state': 'open',
          'html_url': 'https://example.test/issues/33',
          'updated_at': '2026-04-04T16:10:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      final commentsData = [
        {
          'id': 330,
          'body': '@helper who are you?',
          'html_url': 'https://example.test/issues/33#issuecomment-330',
          'created_at': '2026-04-04T16:10:00Z',
          'updated_at': '2026-04-04T16:10:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {33: commentsData},
        postCommentIssueNumber: 33,
        ghLog: ghLog,
        postedBodyFile: postedBody,
        failViewerLookup: true,
      );

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'fallback reply',
        'summary': 'posted',
      });

      // And a fake gh command that fails the authenticated user lookup.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    issueTracker:
      eventSource:
        pollInterval: 5m
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      await app.close();

      // Then it still posts one comment.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/33/comments'),
            )
            .length,
        2,
      );

      // And the visible automation markers use the unknown identity fallback.
      final postedComment = await postedBody.readAsString();
      expect(postedComment, contains('@unknown'));
    });

    /// ```gherkin
    /// Scenario: Skip issue evaluation when no responders are configured
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data with a comment that would otherwise be evaluated
    ///   And an AO subset config that enables the assistant without defining responders
    ///   When the app processes one polling cycle
    ///   Then it completes without throwing an error
    ///   And it records the issue thread as evaluated without a responder decision
    ///   And it stores the job status as skipped
    /// ```
    test('Skip issue evaluation when no responders are configured', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-no-responders-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And GitHub issue data with a comment that would otherwise be evaluated.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final issueData = [
        {
          'number': 7,
          'title': 'Need help',
          'body': 'Please review this thread.',
          'state': 'open',
          'html_url': 'https://example.test/issues/7',
          'updated_at': '2026-04-04T14:00:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      final commentsData = [
        {
          'id': 70,
          'body': '@helper can you take a look?',
          'html_url': 'https://example.test/issues/7#issuecomment-70',
          'created_at': '2026-04-04T14:00:00Z',
          'updated_at': '2026-04-04T14:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {7: commentsData},
      );

      // And an AO subset config that enables the assistant without defining responders.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      final thread = await app.database.findIssueThread('sample', 7);
      final jobs = await app.database.select(app.database.jobs).get();
      await app.close();

      // Then it completes without throwing an error.
      expect(thread, isNotNull);

      // And it records the issue thread as evaluated without a responder decision.
      expect(thread!.lastDecision, isNull);
      expect(thread.lastEvaluatedFingerprint, thread.fingerprint);

      // And it stores the job status as skipped.
      expect(jobs, hasLength(1));
      expect(jobs.single.status, JobStatus.skipped);
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunOnceConcurrencyTests();
}
