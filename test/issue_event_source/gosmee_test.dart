import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunGosmeeTests() {
  /// ```gherkin
  /// Feature: Gitea gosmee issue events
  ///
  ///   As a maintainer running the long-lived assistant for Gitea
  ///   I want tea/gosmee events to trigger issue evaluation without relying only on polling
  ///   So that issue and comment activity can be handled through a channel-based source
  /// ```
  group('IssueAssistantApp.run gosmee', () {
    /// ```gherkin
    /// Scenario: Reply to a mention received through tea/gosmee
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee script that forwards one Gitea issue_comment webhook event
    ///   And a Gitea API fixture that can manage webhooks and post issue comments
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses tea/gosmee
    ///   When the long-running app starts and receives the forwarded webhook
    ///   Then it reads issue comments and posts exactly one reply for that issue
    ///   And the Gitea webhook lifecycle API is invoked for the project
    /// ```
    test('Reply to a mention received through tea/gosmee', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-gosmee-run-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gosmee script that forwards one Gitea issue_comment webhook event.
      final gosmeeScript = File(p.join(sandbox.path, 'gosmee'));
      final gosmeeLog = File(p.join(sandbox.path, 'gosmee-log.jsonl'));
      final issue = {
        'index': 12,
        'title': 'Need channel-based trigger handling',
        'body': 'Please react to gosmee.',
        'state': 'open',
        'url': 'https://gitea.example.test/owner/sample/issues/12',
        'updated_at': '2026-04-08T04:00:00Z',
        'poster': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final comments = [
        {
          'id': 51,
          'body': '@helper can you handle gosmee comments?',
          'url':
              'https://gitea.example.test/owner/sample/issues/12#issuecomment-51',
          'created_at': '2026-04-08T04:00:00Z',
          'updated_at': '2026-04-08T04:00:00Z',
          'poster': {'login': 'reporter'},
        },
      ];
      await writeGosmeeForwardScript(
        gosmeeScript: gosmeeScript,
        publicUrl: 'https://gosmee.example.test/sample',
        payload: {
          'action': 'created',
          'issue': issue,
          'comment': comments.last,
          'repository': {'full_name': 'owner/sample'},
        },
        gosmeeLog: gosmeeLog,
      );

      // And a Gitea API fixture for issue reads and replies.
      final giteaServer = await FakeGiteaApiServer.start(
        issueListResponsesByRepo: {
          'owner/sample': const <Map<String, Object?>>[],
        },
        commentResponsesByRepo: {
          'owner/sample': {12: comments},
        },
        postCommentResponsesByRepo: {
          'owner/sample': {
            12: {
              'id': 801,
              'body': 'posted',
              'html_url': 'https://gitea.example.test/comment/801',
            },
          },
        },
        viewerLogin: 'tea-octocat',
      );
      addTearDown(giteaServer.close);

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- consume gosmee issue_comment events',
        'summary': 'posted channel-based planning advice',
      });

      // And an orchestrator-style config that uses tea/gosmee.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    issueTracker:
      provider: gitea
      eventSource:
        pollInterval: 5m
        type: tea/gosmee
    repo: owner/sample
    path: ${repoDir.path}
''');
      await File(p.join(sandbox.path, '.env')).writeAsString('''
CWS_GITEA_HOST=${giteaServer.baseUrl}
CWS_GITEA_TOKEN=test-token
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        gosmeeCommand: gosmeeScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );
      final records = <AppLogRecord>[];
      void captureLog(AppLogRecord record) {
        records.add(record);
      }

      AppLogger.addListener(captureLog);
      addTearDown(() => AppLogger.removeListener(captureLog));

      // When the long-running app starts and receives the forwarded webhook.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 200; attempt += 1) {
        if (giteaServer.postedBodies.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;

      // Then it reads issue comments and posts exactly one reply for that issue.
      expect(giteaServer.postedBodies, hasLength(1));
      final postedComment =
          (jsonDecode(giteaServer.postedBodies.single)
                  as Map<String, dynamic>)['body']
              as String;
      expect(
        postedComment,
        contains('Plan:\n- consume gosmee issue_comment events'),
      );
      expect(postedComment, contains('@tea-octocat'));

      // And the Gitea webhook lifecycle API is invoked for the project.
      expect(giteaServer.createdWebhooks, hasLength(1));
      expect(
        (giteaServer.createdWebhooks.single['config'] as Map)['url'],
        'https://gosmee.example.test/sample',
      );
      expect(giteaServer.deletedWebhookIds, contains(81));
      expect(
        records.any(
          (record) => record.message.contains(
            'route project=sample provider=gitea event_source=tea/gosmee',
          ),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) => record.message.contains(
            'route source=tea/gosmee projects=sample',
          ),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) => record.message.contains(
            'gitea/gosmee project=sample setup_start',
          ),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.level == AppLogLevel.debug &&
              record.message.contains('gitea/gosmee channel_command_result'),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.level == AppLogLevel.debug &&
              record.message.contains('gitea config source=env'),
        ),
        isTrue,
      );
    });

    /// ```gherkin
    /// Scenario: Reconcile a missed Gitea gosmee event through polling
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee script that starts forwarding without delivering an event
    ///   And a Gitea API fixture that returns a new issue only on a later reconciliation poll
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses tea/gosmee with continuous reconciliation
    ///   When the long-running app starts and enough time passes for reconciliation polling
    ///   Then it posts exactly one reply for the issue discovered by polling
    ///   And the app performs more than one Gitea issue listing request while running
    /// ```
    test('Reconcile a missed Gitea gosmee event through polling', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-gosmee-reconcile-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gosmee script that starts forwarding without delivering an event.
      final gosmeeScript = File(p.join(sandbox.path, 'gosmee'));
      final gosmeeLog = File(p.join(sandbox.path, 'gosmee-log.jsonl'));
      registerFakeGosmeeCommand(
        command: gosmeeScript.path,
        publicUrl: 'https://gosmee.example.test/reconcile',
        gosmeeLog: gosmeeLog,
      );

      final issue = {
        'index': 18,
        'title': 'Need reconciliation after a missed webhook',
        'body': 'Please recover this mention from polling.',
        'state': 'open',
        'url': 'https://gitea.example.test/owner/sample/issues/18',
        'updated_at': '2026-04-08T05:00:00Z',
        'poster': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final comments = [
        {
          'id': 181,
          'body': '@helper please recover this even if gosmee missed it',
          'url':
              'https://gitea.example.test/owner/sample/issues/18#issuecomment-181',
          'created_at': '2026-04-08T05:00:00Z',
          'updated_at': '2026-04-08T05:00:00Z',
          'poster': {'login': 'reporter'},
        },
      ];

      // And a Gitea API fixture that returns a new issue only on a later reconciliation poll.
      final giteaServer = await FakeGiteaApiServer.start(
        issueListResponseSequenceByRepo: {
          'owner/sample': [
            const <Map<String, Object?>>[],
            [issue],
          ],
        },
        commentResponsesByRepo: {
          'owner/sample': {18: comments},
        },
        postCommentResponsesByRepo: {
          'owner/sample': {
            18: {
              'id': 802,
              'body': 'posted',
              'html_url': 'https://gitea.example.test/comment/802',
            },
          },
        },
        viewerLogin: 'tea-octocat',
      );
      addTearDown(giteaServer.close);

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- reconcile missed gosmee events through polling',
        'summary': 'posted reconciliation advice',
      });

      // And an orchestrator-style config that uses tea/gosmee with continuous reconciliation.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    issueTracker:
      provider: gitea
      eventSource:
        type: tea/gosmee
        reconciliation: continuous
        reconcileInterval: 1s
    repo: owner/sample
    path: ${repoDir.path}
''');
      await File(p.join(sandbox.path, '.env')).writeAsString('''
CWS_GITEA_HOST=${giteaServer.baseUrl}
CWS_GITEA_TOKEN=test-token
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        gosmeeCommand: gosmeeScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the long-running app starts and enough time passes for reconciliation polling.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 200; attempt += 1) {
        if (giteaServer.postedBodies.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;

      // Then it posts exactly one reply for the issue discovered by polling.
      expect(giteaServer.postedBodies, hasLength(1));
      final postedComment =
          (jsonDecode(giteaServer.postedBodies.single)
                  as Map<String, dynamic>)['body']
              as String;
      expect(
        postedComment,
        contains('Plan:\n- reconcile missed gosmee events through polling'),
      );

      // And the app performs more than one Gitea issue listing request while running.
      expect(
        giteaServer.issueListRequestCount('owner/sample'),
        greaterThanOrEqualTo(2),
      );
      final gosmeeLogLines = await gosmeeLog.readAsLines();
      expect(
        gosmeeLogLines.any(
          (line) =>
              line.contains('client https://gosmee.example.test/reconcile'),
        ),
        isTrue,
      );
    });

    /// ```gherkin
    /// Scenario: Delete webhook even when gosmee ignores SIGTERM during shutdown
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee command that forwards one Gitea webhook event but ignores SIGTERM
    ///   And a Gitea API fixture that can manage webhooks and post issue comments
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses tea/gosmee
    ///   When the long-running app starts and then closes
    ///   Then the app still deletes the Gitea webhook for the project
    /// ```
    test('Delete webhook even when gosmee ignores SIGTERM during shutdown', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-gosmee-shutdown-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gosmee command that forwards one Gitea webhook event but ignores SIGTERM.
      final gosmeeScript = File(p.join(sandbox.path, 'gosmee'));
      final issue = {
        'index': 21,
        'title': 'Shutdown should still unregister webhook',
        'body': 'Please react before shutdown.',
        'state': 'open',
        'url': 'https://gitea.example.test/owner/sample/issues/21',
        'updated_at': '2026-04-08T07:00:00Z',
        'poster': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final comments = [
        {
          'id': 151,
          'body': '@helper verify webhook cleanup on shutdown',
          'url':
              'https://gitea.example.test/owner/sample/issues/21#issuecomment-151',
          'created_at': '2026-04-08T07:00:00Z',
          'updated_at': '2026-04-08T07:00:00Z',
          'poster': {'login': 'reporter'},
        },
      ];
      registerFakeGosmeeCommand(
        command: gosmeeScript.path,
        publicUrl: 'https://gosmee.example.test/shutdown',
        payload: {
          'action': 'created',
          'issue': issue,
          'comment': comments.last,
          'repository': {'full_name': 'owner/sample'},
        },
        exitOnSigterm: false,
      );

      // And a Gitea API fixture that can manage webhooks and post issue comments.
      final giteaServer = await FakeGiteaApiServer.start(
        issueListResponsesByRepo: {
          'owner/sample': const <Map<String, Object?>>[],
        },
        commentResponsesByRepo: {
          'owner/sample': {21: comments},
        },
        postCommentResponsesByRepo: {
          'owner/sample': {
            21: {
              'id': 803,
              'body': 'posted',
              'html_url': 'https://gitea.example.test/comment/803',
            },
          },
        },
        viewerLogin: 'tea-octocat',
      );
      addTearDown(giteaServer.close);

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown':
            'Plan:\n- ensure webhook cleanup when shutdown races forwarding',
        'summary': 'posted shutdown cleanup advice',
      });

      // And an orchestrator-style config that uses tea/gosmee.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    issueTracker:
      provider: gitea
      eventSource:
        pollInterval: 5m
        type: tea/gosmee
    repo: owner/sample
    path: ${repoDir.path}
''');
      await File(p.join(sandbox.path, '.env')).writeAsString('''
CWS_GITEA_HOST=${giteaServer.baseUrl}
CWS_GITEA_TOKEN=test-token
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        gosmeeCommand: gosmeeScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the long-running app starts and then closes.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 200; attempt += 1) {
        if (giteaServer.postedBodies.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;

      // Then the app still deletes the Gitea webhook for the project.
      expect(giteaServer.deletedWebhookIds, contains(81));
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunGosmeeTests();
}
