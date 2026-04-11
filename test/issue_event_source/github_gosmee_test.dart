import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunGitHubGosmeeTests() {
  /// ```gherkin
  /// Feature: GitHub gosmee issue events
  ///
  ///   As a maintainer running the long-lived assistant for GitHub
  ///   I want gh/gosmee events to trigger issue evaluation without relying only on polling
  ///   So that multiple GitHub repositories can use channel-based issue triggers
  /// ```
  group('IssueAssistantApp.run github gosmee', () {
    /// ```gherkin
    /// Scenario: Reply to a mention received through gh/gosmee
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee script that forwards one GitHub issue_comment webhook event
    ///   And a gh script that can manage webhooks and post issue comments
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses gh/gosmee
    ///   When the long-running app starts and receives the forwarded webhook
    ///   Then it reads issue comments and posts exactly one reply for that issue
    ///   And the GitHub webhook lifecycle commands are invoked for the project
    /// ```
    test('Reply to a mention received through gh/gosmee', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-gh-gosmee-run-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gosmee script that forwards one GitHub issue_comment webhook event.
      final gosmeeScript = File(p.join(sandbox.path, 'gosmee'));
      final gosmeeLog = File(p.join(sandbox.path, 'gosmee-log.jsonl'));
      final issue = {
        'number': 12,
        'title': 'Need channel-based trigger handling',
        'body': 'Please react to gh/gosmee.',
        'state': 'open',
        'html_url': 'https://example.test/issues/12',
        'updated_at': '2026-04-08T04:00:00Z',
        'user': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final comments = [
        {
          'id': 51,
          'body': '@helper can you handle gh/gosmee comments?',
          'html_url': 'https://example.test/issues/12#issuecomment-51',
          'created_at': '2026-04-08T04:00:00Z',
          'updated_at': '2026-04-08T04:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeGosmeeForwardScript(
        gosmeeScript: gosmeeScript,
        publicUrl: 'https://gosmee.example.test/github-sample',
        payload: {
          'action': 'created',
          'issue': issue,
          'comment': comments.last,
          'repository': {'full_name': 'owner/sample'},
        },
        gosmeeLog: gosmeeLog,
      );

      // And a gh script that can manage webhooks and post issue comments.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      await writeGitHubGosmeeGhScript(
        ghScript: ghScript,
        repo: 'owner/sample',
        webhookId: 81,
        issueNumber: 12,
        comments: comments,
        ghLog: ghLog,
        postedBodyFile: postedBody,
        viewerLogin: 'octocat',
      );

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- consume gh/gosmee issue_comment events',
        'summary': 'posted GitHub channel-based planning advice',
      });

      // And an orchestrator-style config that uses gh/gosmee.
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
      provider: github
      eventSource:
        pollInterval: 5m
        type: gh/gosmee
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
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
        if (await postedBody.exists()) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;

      // Then it reads issue comments and posts exactly one reply for that issue.
      expect(await postedBody.exists(), isTrue);
      final postedComment = await postedBody.readAsString();
      expect(
        postedComment,
        contains('Plan:\n- consume gh/gosmee issue_comment events'),
      );
      expect(postedComment, contains('@octocat'));

      // And the GitHub webhook lifecycle commands are invoked for the project.
      final ghLogLines = await ghLog.readAsLines();
      expect(
        ghLogLines.any(
          (line) =>
              line.contains('api -X POST repos/owner/sample/hooks') &&
              line.contains('-F active=true'),
        ),
        isTrue,
      );
      expect(
        ghLogLines.any(
          (line) => line.contains('api -X DELETE repos/owner/sample/hooks/81'),
        ),
        isTrue,
      );
      final gosmeeLogLines = await gosmeeLog.readAsLines();
      expect(
        gosmeeLogLines.any(
          (line) =>
              line.contains('client https://gosmee.example.test/github-sample'),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) => record.message.contains(
            'route project=sample provider=github event_source=gh/gosmee',
          ),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.message.contains('route source=gh/gosmee projects=sample'),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) => record.message.contains(
            'github/gosmee project=sample setup_start',
          ),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.level == AppLogLevel.debug &&
              record.message.contains('github/gosmee channel_command_result'),
        ),
        isTrue,
      );
      expect(
        records.any(
          (record) =>
              record.level == AppLogLevel.debug &&
              record.message.contains(
                'github webhook create repo=owner/sample',
              ),
        ),
        isTrue,
      );
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunGitHubGosmeeTests();
}
