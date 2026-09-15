import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunOnceWorktreeTests() {
  /// ```gherkin
  /// Feature: Issue thread assistant polling
  ///
  ///   As a maintainer using the issue assistant
  ///   I want issue thread events to be evaluated through configured responders
  ///   So that users get help only when the thread actually needs a response
  /// ```
  group('IssueAssistantApp.runOnce', () {
    /// ```gherkin
    /// Scenario: Run bug verification mention evaluation from an ephemeral worktree with issue context
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing a bug verification mention
    ///   And a responder that records its working directory and stdin before returning no_reply
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then the responder runs from an ephemeral worktree instead of the source checkout
    ///   And the responder stdin includes the latest issue comment text
    ///   And the app does not post a GitHub comment when the responder returns no_reply
    /// ```
    test(
      'Run bug verification mention evaluation from an ephemeral worktree with issue context',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-mention-worktree-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And GitHub issue data containing a bug verification mention.
        final ghScript = File(p.join(sandbox.path, 'gh'));
        final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
        final issueData = [
          {
            'number': 24,
            'title': 'Need help verifying a bug',
            'body': 'Please verify and reproduce this bug in the CLI workflow.',
            'state': 'open',
            'html_url': 'https://example.test/issues/24',
            'updated_at': '2026-04-04T15:30:00Z',
            'user': {'login': 'reporter'},
            'labels': const [],
          },
        ];
        final commentsData = [
          {
            'id': 240,
            'body': '@helper please verify and reproduce this bug',
            'html_url': 'https://example.test/issues/24#issuecomment-240',
            'created_at': '2026-04-04T15:30:00Z',
            'updated_at': '2026-04-04T15:30:00Z',
            'user': {'login': 'reporter'},
          },
        ];
        await writeFakeGhScript(
          ghScript: ghScript,
          issueListResponse: issueData,
          commentResponses: {24: commentsData},
          ghLog: ghLog,
          postCommentIssueNumber: 24,
        );

        // And a responder that records its working directory and stdin before returning no_reply.
        final cwdCapture = File(p.join(sandbox.path, 'responder.cwd'));
        final stdinCapture = File(p.join(sandbox.path, 'responder.stdin'));
        final responderScript = File(
          p.join(sandbox.path, 'responder-capture.sh'),
        );
        await writeCapturingResponderScript(
          responderScript,
          {
            'decision': 'no_reply',
            'mode': 'planning',
            'summary': 'captured mention context',
          },
          cwdCapture: cwdCapture,
          stdinCapture: stdinCapture,
        );

        // And an orchestrator-style config pointing to the fake repo and responder.
        final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
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

        // Then the responder runs from an ephemeral worktree instead of the source checkout.
        final capturedCwd = await cwdCapture.readAsString();
        expect(
          p.normalize(capturedCwd.trim()),
          isNot(p.normalize(repoDir.path)),
        );

        // And the responder stdin includes the latest issue comment text.
        final capturedStdin = await stdinCapture.readAsString();
        expect(
          capturedStdin,
          contains('@helper please verify and reproduce this bug'),
        );

        // And the app does not post a GitHub comment when the responder returns no_reply.
        final logLines = await ghLog.readAsLines();
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('repos/owner/sample/issues/24/comments'),
              )
              .length,
          1,
        );
      },
    );

    /// ```gherkin
    /// Scenario: Run planning replies from an ephemeral worktree
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing a planning mention
    ///   And a responder that records its working directory before returning a reply
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then the responder runs from an ephemeral worktree instead of the source checkout
    ///   And the worktree is retained after the run for issue-session reuse
    /// ```
    test('Run planning replies from an ephemeral worktree', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-planning-project-path-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      final worktreeRoot = await Directory(
        p.join(sandbox.path, 'worktrees'),
      ).create();
      await initGitRepo(repoDir);

      // And GitHub issue data containing a planning mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final issueData = [
        {
          'number': 25,
          'title': 'Need planning help',
          'body': 'Please review the service layout.',
          'state': 'open',
          'html_url': 'https://example.test/issues/25',
          'updated_at': '2026-04-04T15:35:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      final commentsData = [
        {
          'id': 250,
          'body': '@helper can you plan the service layout?',
          'html_url': 'https://example.test/issues/25#issuecomment-250',
          'created_at': '2026-04-04T15:35:00Z',
          'updated_at': '2026-04-04T15:35:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {25: commentsData},
        postCommentIssueNumber: 25,
      );

      // And a responder that records its working directory before returning a reply.
      final cwdCapture = File(p.join(sandbox.path, 'planning.cwd'));
      final responderScript = File(
        p.join(sandbox.path, 'planning-responder.sh'),
      );
      await writeCapturingResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'planning reply',
        'summary': 'used project path',
      }, cwdCapture: cwdCapture);

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
worktreeDir: ${worktreeRoot.path}
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

      // Then the responder runs from an ephemeral worktree instead of the source checkout.
      final capturedCwd = await cwdCapture.readAsString();
      expect(p.normalize(capturedCwd.trim()), isNot(p.normalize(repoDir.path)));
      expect(
        p.isWithin(worktreeRoot.path, p.normalize(capturedCwd.trim())),
        isTrue,
      );

      // And the worktree is retained after the run for issue-session reuse.
      expect(await worktreeRoot.list().isEmpty, isFalse);
    });

    /// ```gherkin
    /// Scenario: Accept codex style jsonl responder output
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing an explicit assistant mention
    ///   And a responder that emits codex style jsonl events instead of a single json object
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then it extracts the final agent message and posts one reply
    /// ```
    test('Accept codex style jsonl responder output', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-jsonl-run-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And GitHub issue data containing an explicit assistant mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final issueData = [
        {
          'number': 18,
          'title': 'Need help',
          'body': 'Please review the plan.',
          'state': 'open',
          'html_url': 'https://example.test/issues/18',
          'updated_at': '2026-04-04T15:00:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      final commentsData = [
        {
          'id': 180,
          'body': '@helper can you respond?',
          'html_url': 'https://example.test/issues/18#issuecomment-180',
          'created_at': '2026-04-04T15:00:00Z',
          'updated_at': '2026-04-04T15:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {18: commentsData},
        postCommentIssueNumber: 18,
        ghLog: ghLog,
      );

      // And a responder that emits codex style jsonl events instead of a single json object.
      final responderScript = File(p.join(sandbox.path, 'responder-jsonl.sh'));
      await writeJsonlResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Codex JSONL reply',
        'summary': 'parsed event stream',
      });

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
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

      // Then it extracts the final agent message and posts one reply.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/18/comments'),
            )
            .length,
        2,
      );
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunOnceWorktreeTests();
}
