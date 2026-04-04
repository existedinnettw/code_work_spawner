import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// ```gherkin
  /// Feature: AppConfig loading
  ///
  ///   As a user of the Code Work Spawner
  ///   I want the app configuration to correctly merge defaults with project-specific overrides
  ///   So that I can specify common settings once and customize only what differs for each project
  /// ```
  group('AppConfig.load', () {
    /// ```gherkin
    /// Scenario: Merge defaults with project overrides
    ///   Given AO style config with shared defaults and one project override
    ///   When loading the app config from disk
    ///   Then the project keeps inherited defaults that were not overridden
    ///   And the project-specific prompt replaces the shared prompt
    /// ```
    test('Merge defaults with project overrides', () async {
      // Given AO style config with shared defaults and one project override.
      final tempDir = await Directory.systemTemp.createTemp('cws-config-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    prompt: "default {{repo}}"
    responders:
      - id: fallback
        command: responder
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    defaultBranch: main
    issueAssistant:
      prompt: "project {{project_key}}"
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the project keeps inherited defaults that were not overridden.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
        '@helper',
      ]);
      expect(
        config.projects['sample']!.issueAssistant.responders.single.id,
        'fallback',
      );

      // And the project-specific prompt replaces the shared prompt.
      expect(
        config.projects['sample']!.issueAssistant.prompt,
        'project {{project_key}}',
      );
    });

    /// ```gherkin
    /// Scenario: Normalize legacy codex json flag
    ///   Given an orchestrator config that still uses the legacy codex --json-output flag
    ///   When loading the app config from disk
    ///   Then the responder args are normalized to the current codex --json flag
    /// ```
    test('Normalize legacy codex json flag', () async {
      // Given an orchestrator config that still uses the legacy codex --json-output flag.
      final tempDir = await Directory.systemTemp.createTemp('cws-codex-args-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: codex
        command: codex
        args: ["exec", "--json-output"]
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the responder args are normalized to the current codex --json flag.
      expect(config.projects['sample']!.issueAssistant.responders.single.args, [
        'exec',
        '--json',
      ]);
    });

    /// ```gherkin
    /// Scenario: Load AO subset config with shared worktree root
    ///   Given an AO style shortcut config with dataDir, worktreeDir, and project defaults
    ///   When loading the app config from disk
    ///   Then the app exposes the configured data and worktree directories
    ///   And each project inherits the supported shared defaults
    /// ```
    test('Load AO subset config with shared worktree root', () async {
      // Given an AO style shortcut config with dataDir, worktreeDir, and project defaults.
      final tempDir = await Directory.systemTemp.createTemp('cws-ao-subset-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
dataDir: ~/.agent-orchestrator
worktreeDir: ~/.worktrees
defaults:
  defaultBranch: trunk
  sessionPrefix: ao
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
''');

      // When loading the app config from disk.
      final config = await AppConfig.load(configFile.path);

      // Then the app exposes the configured data and worktree directories.
      expect(
        config.dataDir,
        p.join(Platform.environment['HOME']!, '.agent-orchestrator'),
      );
      expect(
        config.worktreeDir,
        p.join(Platform.environment['HOME']!, '.worktrees'),
      );

      // And each project inherits the supported shared defaults.
      expect(config.projects['sample'], isNotNull);
      expect(config.projects['sample']!.defaultBranch, 'trunk');
      expect(config.projects['sample']!.sessionPrefix, 'ao');
      expect(config.projects['sample']!.issueAssistant.enabled, isTrue);
    });

    /// ```gherkin
    /// Scenario: Reject unsupported AO fields
    ///   Given an AO style config that includes an unsupported field
    ///   When loading the app config from disk
    ///   Then loading fails with a clear config error
    /// ```
    test('Reject unsupported AO fields', () async {
      // Given an AO style config that includes an unsupported field.
      final tempDir = await Directory.systemTemp.createTemp('cws-ao-invalid-');
      final configFile = File(p.join(tempDir.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
worktreeDir: ~/.worktrees
projects:
  sample:
    repo: owner/sample
    path: ${tempDir.path}
    tracker:
      plugin: github
''');

      // When loading the app config from disk.
      final load = AppConfig.load(configFile.path);

      // Then loading fails with a clear config error.
      await expectLater(
        load,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported config field: projects.sample.tracker'),
          ),
        ),
      );
    });
  });

  /// ```gherkin
  /// Feature: Worktree management
  ///
  ///   As a maintainer running bug verification jobs
  ///   I want ephemeral git worktrees to respect the configured worktree root
  ///   So that temporary workspaces are created in a predictable location
  /// ```
  group('WorkspaceManager.createEphemeralWorktree', () {
    /// ```gherkin
    /// Scenario: Create and dispose a worktree under the configured root
    ///   Given a git repository and a dedicated worktree root directory
    ///   When creating and then disposing an ephemeral worktree
    ///   Then the worktree is created beneath the configured root
    ///   And cleanup removes the generated worktree directory without deleting the root
    /// ```
    test('Create and dispose a worktree under the configured root', () async {
      // Given a git repository and a dedicated worktree root directory.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-worktree-root-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      final worktreeRoot = await Directory(
        p.join(sandbox.path, 'worktrees'),
      ).create();
      await _initGitRepo(repoDir);
      final manager = WorkspaceManager(worktreeRoot: worktreeRoot.path);

      // When creating and then disposing an ephemeral worktree.
      final workspacePath = await manager.createEphemeralWorktree(repoDir.path);
      final workspaceDirectory = Directory(workspacePath);
      final parentDirectory = Directory(p.dirname(workspacePath));
      await manager.disposeEphemeralWorktree(workspacePath);

      // Then the worktree is created beneath the configured root.
      expect(p.isWithin(worktreeRoot.path, workspacePath), isTrue);

      // And cleanup removes the generated worktree directory without deleting the root.
      expect(await workspaceDirectory.exists(), isFalse);
      expect(await parentDirectory.exists(), isFalse);
      expect(await worktreeRoot.exists(), isTrue);
    });
  });

  /// ```gherkin
  /// Feature: Issue thread assistant polling
  ///
  ///   As a maintainer using the issue assistant
  ///   I want issue thread events to be evaluated through configured responders
  ///   So that users get help only when the thread actually needs a response
  /// ```
  group('IssueAssistantApp.runOnce', () {
    /// ```gherkin
    /// Scenario: Reply once when a user explicitly mentions the assistant
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing a comment with an explicit assistant mention
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then it reads issue comments and posts exactly one reply for that issue
    /// ```
    test('Reply once when a user explicitly mentions the assistant', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-run-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await _initGitRepo(repoDir);

      // And GitHub issue data containing a comment with an explicit assistant mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final issueData = [
        {
          'number': 12,
          'title': 'Need architecture help',
          'body': 'Please review the API layering.',
          'state': 'open',
          'html_url': 'https://example.test/issues/12',
          'updated_at': '2026-04-04T12:00:00Z',
          'user': {'login': 'reporter'},
          'labels': [
            {'name': 'help'},
          ],
        },
      ];
      final commentsData = [
        {
          'id': 50,
          'body': '@helper can you plan the architecture?',
          'html_url': 'https://example.test/issues/12#issuecomment-50',
          'created_at': '2026-04-04T12:00:00Z',
          'updated_at': '2026-04-04T12:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await _writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {12: commentsData},
        postCommentIssueNumber: 12,
        ghLog: ghLog,
      );

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await _writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- separate service and persistence',
        'summary': 'posted planning advice',
      });

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
    defaultBranch: main
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      await app.close();

      // Then it reads issue comments and posts exactly one reply for that issue.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/12/comments'),
            )
            .length,
        2,
      );
    });

    /// ```gherkin
    /// Scenario: Record no reply when the responder decides the discussion is already sufficient
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data with a new comment that does not require another response
    ///   And a responder that explicitly returns no_reply
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then it records the evaluation result as no_reply
    ///   And it does not store a posted GitHub comment for that thread version
    /// ```
    test(
      'Record no reply when the responder decides the discussion is already sufficient',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp('cws-no-reply-');
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await _initGitRepo(repoDir);

        // And GitHub issue data with a new comment that does not require another response.
        final ghScript = File(p.join(sandbox.path, 'gh'));
        final issueData = [
          {
            'number': 42,
            'title': 'Existing discussion',
            'body': 'Initial context',
            'state': 'open',
            'html_url': 'https://example.test/issues/42',
            'updated_at': '2026-04-04T13:00:00Z',
            'user': {'login': 'reporter'},
            'labels': const [],
          },
        ];
        final commentsData = [
          {
            'id': 99,
            'body': 'I think this is already covered.',
            'html_url': 'https://example.test/issues/42#issuecomment-99',
            'created_at': '2026-04-04T13:00:00Z',
            'updated_at': '2026-04-04T13:00:00Z',
            'user': {'login': 'reporter'},
          },
        ];
        await _writeFakeGhScript(
          ghScript: ghScript,
          issueListResponse: issueData,
          commentResponses: {42: commentsData},
        );

        // And a responder that explicitly returns no_reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await _writeResponderScript(responderScript, {
          'decision': 'no_reply',
          'mode': 'planning',
          'summary': 'thread already resolved',
        });

        // And an orchestrator-style config pointing to the fake repo and responder.
        final configFile = File(
          p.join(sandbox.path, 'agent-orchestrator.yaml'),
        );
        await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
''');
        final app = await IssueAssistantApp.open(
          config: await AppConfig.load(configFile.path),
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          ghCommand: ghScript.path,
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 42);
        await app.close();

        // Then it records the evaluation result as no_reply.
        expect(thread, isNotNull);
        expect(thread!.lastDecision, 'no_reply');

        // And it does not store a posted GitHub comment for that thread version.
        expect(thread.lastCommentId, isNull);
      },
    );

    /// ```gherkin
    /// Scenario: Log raw responder output for debugging
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing an explicit assistant mention
    ///   And a responder that writes stderr diagnostics alongside a no_reply JSON payload
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle while app logs are captured
    ///   Then the application logs include the responder stdout payload
    ///   And the application logs include the responder stderr diagnostics
    /// ```
    test('Log raw responder output for debugging', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-log-output-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await _initGitRepo(repoDir);

      // And GitHub issue data containing an explicit assistant mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final issueData = [
        {
          'number': 21,
          'title': 'Need responder diagnostics',
          'body': 'Inspect the responder output.',
          'state': 'open',
          'html_url': 'https://example.test/issues/21',
          'updated_at': '2026-04-04T14:10:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      final commentsData = [
        {
          'id': 210,
          'body': '@helper please explain why you skipped this',
          'html_url': 'https://example.test/issues/21#issuecomment-210',
          'created_at': '2026-04-04T14:10:00Z',
          'updated_at': '2026-04-04T14:10:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await _writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {21: commentsData},
        postCommentIssueNumber: 21,
      );

      // And a responder that writes stderr diagnostics alongside a no_reply JSON payload.
      final responderScript = File(p.join(sandbox.path, 'responder-debug.sh'));
      await _writeResponderScript(responderScript, {
        'decision': 'no_reply',
        'mode': 'planning',
        'summary': 'diagnostic skip',
      }, stderr: 'codex diagnostic trace');

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );
      final logMessages = <String>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.INFO;
      final subscription = Logger.root.onRecord.listen((record) {
        logMessages.add(record.message);
      });

      // When the app processes one polling cycle while app logs are captured.
      await app.runOnce();
      await subscription.cancel();
      Logger.root.level = previousLevel;
      await app.close();

      // Then the application logs include the responder stdout payload.
      expect(logMessages.join('\n'), contains('"decision":"no_reply"'));

      // And the application logs include the responder stderr diagnostics.
      expect(logMessages.join('\n'), contains('codex diagnostic trace'));
    });

    /// ```gherkin
    /// Scenario: Run mention replies from an ephemeral worktree with issue context
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing an explicit assistant mention
    ///   And a responder that records its working directory and stdin before returning no_reply
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then the responder runs from an ephemeral worktree instead of the source checkout
    ///   And the responder stdin includes the latest issue comment text
    ///   And the app still posts a GitHub comment because the thread explicitly mentioned the assistant
    /// ```
    test('Run mention replies from an ephemeral worktree with issue context', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-mention-worktree-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await _initGitRepo(repoDir);

      // And GitHub issue data containing an explicit assistant mention.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final issueData = [
        {
          'number': 24,
          'title': 'Need your thoughts',
          'body': 'Please review the CLI workflow.',
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
          'body': '@helper give me your though about this CLI flow',
          'html_url': 'https://example.test/issues/24#issuecomment-240',
          'created_at': '2026-04-04T15:30:00Z',
          'updated_at': '2026-04-04T15:30:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await _writeFakeGhScript(
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
      await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
pwd > "${cwdCapture.path}"
cat > "${stdinCapture.path}"
cat <<'JSON'
{"decision":"no_reply","mode":"planning","summary":"captured mention context"}
JSON
''');
      await Process.run('chmod', ['+x', responderScript.path]);

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      await app.close();

      // Then the responder runs from an ephemeral worktree instead of the source checkout.
      final capturedCwd = await cwdCapture.readAsString();
      expect(p.normalize(capturedCwd.trim()), isNot(p.normalize(repoDir.path)));

      // And the responder stdin includes the latest issue comment text.
      final capturedStdin = await stdinCapture.readAsString();
      expect(
        capturedStdin,
        contains('@helper give me your though about this CLI flow'),
      );

      // And the app still posts a GitHub comment because the thread explicitly mentioned the assistant.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/24/comments'),
            )
            .length,
        2,
      );
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
      await _initGitRepo(repoDir);

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
      await _writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {18: commentsData},
        postCommentIssueNumber: 18,
        ghLog: ghLog,
      );

      // And a responder that emits codex style jsonl events instead of a single json object.
      final responderScript = File(p.join(sandbox.path, 'responder-jsonl.sh'));
      await _writeJsonlResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Codex JSONL reply',
        'summary': 'parsed event stream',
      });

      // And an orchestrator-style config pointing to the fake repo and responder.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
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
      await _initGitRepo(repoDir);

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
      await _writeFakeGhScript(
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

Future<void> _writeFakeGhScript({
  required File ghScript,
  required List<Map<String, Object?>> issueListResponse,
  required Map<int, List<Map<String, Object?>>> commentResponses,
  File? ghLog,
  int? postCommentIssueNumber,
}) async {
  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('set -euo pipefail');

  if (ghLog != null) {
    buffer.writeln(
      r'''printf '%s\n' "$*" >> '''
      '"${ghLog.path}"',
    );
  }

  buffer
    ..writeln(
      r'''if [[ "$1" == "api" && "$4" == repos/owner/sample/issues\?* ]]; then''',
    )
    ..writeln("  cat <<'JSON'")
    ..writeln(jsonEncode(issueListResponse))
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  for (final entry in commentResponses.entries) {
    buffer
      ..writeln(
        'if [[ "\$1" == "api" && "\$4" == '
        '"repos/owner/sample/issues/${entry.key}/comments?per_page=100" ]]; then',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode(entry.value))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  if (postCommentIssueNumber != null) {
    buffer
      ..writeln(
        'if [[ "\$1" == "api" && "\$4" == '
        '"repos/owner/sample/issues/$postCommentIssueNumber/comments" ]]; then',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(
        jsonEncode({
          'id': 700,
          'html_url': 'https://example.test/comment/700',
          'body': 'posted',
        }),
      )
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  buffer
    ..writeln(r'''echo "unexpected gh args: $*" >&2''')
    ..writeln('exit 1');

  await ghScript.writeAsString(buffer.toString());
  await Process.run('chmod', ['+x', ghScript.path]);
}

Future<void> _writeResponderScript(
  File responderScript,
  Map<String, Object?> response, {
  String stderr = '',
  int exitCode = 0,
}) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
${stderr.isEmpty ? '' : "printf '%s\\n' ${jsonEncode(stderr)} >&2"}
cat <<'JSON'
${jsonEncode(response)}
JSON
exit $exitCode
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

Future<void> _writeJsonlResponderScript(
  File responderScript,
  Map<String, Object?> response,
) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'JSON'
{"type":"thread.started","thread_id":"test-thread"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":${jsonEncode(jsonEncode(response))}}}
{"type":"turn.completed"}
JSON
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

Future<void> _initGitRepo(Directory directory) async {
  await _runGit(['init'], workingDirectory: directory.path);
  await _runGit([
    'config',
    'user.email',
    'test@example.com',
  ], workingDirectory: directory.path);
  await _runGit([
    'config',
    'user.name',
    'Test User',
  ], workingDirectory: directory.path);
  await File(p.join(directory.path, 'README.md')).writeAsString('repo');
  await _runGit(['add', '.'], workingDirectory: directory.path);
  await _runGit(['commit', '-m', 'init'], workingDirectory: directory.path);
}

const Set<String> _gitContextEnvironmentKeys = {
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_COMMON_DIR',
  'GIT_DIR',
  'GIT_IMPLICIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_PREFIX',
  'GIT_WORK_TREE',
};

Future<ProcessResult> _runGit(
  List<String> arguments, {
  required String workingDirectory,
}) {
  final environment = Map<String, String>.from(Platform.environment)
    ..removeWhere((key, _) => _gitContextEnvironmentKeys.contains(key));
  return Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
  );
}
