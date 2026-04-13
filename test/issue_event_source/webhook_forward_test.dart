import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';
import 'test_helpers.dart';

void registerIssueAssistantAppRunWebhookForwardTests() {
  /// ```gherkin
  /// Feature: GitHub webhook forward issue events
  ///
  ///   As a maintainer running the long-lived assistant
  ///   I want GitHub webhook-forward events to trigger issue evaluation without polling
  ///   So that comment mentions can be processed through a channel-based source
  /// ```
  group('IssueAssistantApp.run webhook-forward', () {
    /// ```gherkin
    /// Scenario: Reply to a mention received through gh/webhook-forward
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gh script that forwards one issue_comment webhook event
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses gh/webhook-forward
    ///   When the long-running app starts and receives the forwarded webhook
    ///   Then it reads issue comments and posts exactly one reply for that issue
    ///   And the gh webhook forward command is invoked for the GitHub project
    /// ```
    test('Reply to a mention received through gh/webhook-forward', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandboxRepo = await createSandboxRepo(prefix: 'cws-webhook-run-');
      final sandbox = sandboxRepo.sandbox;
      final repoDir = sandboxRepo.repoDir;

      // And a gh script that forwards one issue_comment webhook event.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      final issue = {
        'number': 12,
        'title': 'Need channel-based trigger handling',
        'body': 'Please react to webhook-forward.',
        'state': 'open',
        'html_url': 'https://example.test/issues/12',
        'updated_at': '2026-04-08T04:00:00Z',
        'user': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final comments = [
        {
          'id': 51,
          'body': '@helper can you handle forwarded comments?',
          'html_url': 'https://example.test/issues/12#issuecomment-51',
          'created_at': '2026-04-08T04:00:00Z',
          'updated_at': '2026-04-08T04:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      await writeWebhookForwardGhScript(
        ghScript: ghScript,
        repo: 'owner/sample',
        issue: issue,
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
        'markdown': 'Plan:\n- consume forwarded issue_comment events',
        'summary': 'posted channel-based planning advice',
      });

      // And an orchestrator-style config that uses gh/webhook-forward.
      final configFile = await writeSingleProjectIssueAssistantConfig(
        sandbox: sandbox,
        responderPath: responderScript.path,
        provider: 'github',
        repo: 'owner/sample',
        repoPath: repoDir.path,
        eventSourceLines: const ['type: gh/webhook-forward'],
      );
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the long-running app starts and receives the forwarded webhook.
      await runAppUntil(app: app, isReady: postedBody.exists);

      // Then it reads issue comments and posts exactly one reply for that issue.
      expect(await postedBody.exists(), isTrue);
      final postedComment = await postedBody.readAsString();
      expect(
        postedComment,
        contains('Plan:\n- consume forwarded issue_comment events'),
      );
      expect(postedComment, contains('@octocat'));

      // And the gh webhook forward command is invoked for the GitHub project.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines.any(
          (line) => line.contains(
            'webhook forward --events=issues,issue_comment --repo=owner/sample',
          ),
        ),
        isTrue,
      );
    });

    /// ```gherkin
    /// Scenario: Log webhook forward stderr at error level
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gh script that writes a webhook creation failure to stderr while forwarding
    ///   And an orchestrator-style config that uses gh/webhook-forward
    ///   When the long-running app starts and webhook-forward emits that stderr line
    ///   Then the app logs the webhook-forward stderr message at error level
    /// ```
    test('Log webhook forward stderr at error level', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandboxRepo = await createSandboxRepo(
        prefix: 'cws-webhook-stderr-',
      );
      final sandbox = sandboxRepo.sandbox;
      final repoDir = sandboxRepo.repoDir;

      // And a gh script that writes a webhook creation failure to stderr while forwarding.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      fakeCommandHandlers[ghScript.path] = (arguments, {timeout}) async {
        if (arguments.length >= 2 &&
            arguments[0] == 'api' &&
            arguments[1] == 'user') {
          return ProcessResult(0, 0, '{"login":"octocat"}', '');
        }
        if (arguments.length >= 4 &&
            arguments[0] == 'api' &&
            arguments[3] == 'search/issues') {
          return ProcessResult(
            0,
            0,
            '{"total_count":0,"incomplete_results":false,"items":[]}',
            '',
          );
        }
        return ProcessResult(
          0,
          1,
          '',
          'unexpected gh args: ${arguments.join(' ')}\n',
        );
      };
      fakeStartedCommandHandlers[ghScript.path] = (arguments) async {
        final process = FakeStartedExternalCommand()
          ..addStderr(
            'Error: error creating webhook: HTTP 422: Validation Failed (https://api.github.com/repos/existedinnettw/code_work_spawner/hooks)\n',
          );
        return process;
      };

      // And an orchestrator-style config that uses gh/webhook-forward.
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
projects:
  sample:
    issueTracker:
      provider: github
      eventSource:
        type: gh/webhook-forward
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
      final records = <AppLogRecord>[];
      void captureLog(AppLogRecord record) {
        records.add(record);
      }

      AppLogger.addListener(captureLog);

      // When the long-running app starts and webhook-forward emits that stderr line.
      await runAppUntil(
        app: app,
        isReady: () async => records.any(
          (record) => record.message.contains('error creating webhook'),
        ),
      );
      AppLogger.removeListener(captureLog);

      // Then the app logs the webhook-forward stderr message at error level.
      expect(
        records.any(
          (record) =>
              record.level == AppLogLevel.error &&
              record.message.contains(
                'stderr=Error: error creating webhook: HTTP 422: Validation Failed',
              ),
        ),
        isTrue,
      );
    });

    /// ```gherkin
    /// Scenario: Reconcile a missed GitHub webhook event through polling
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gh script that starts webhook forwarding without delivering an event
    ///   And the same gh script returns a new issue only on a later reconciliation poll
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses gh/webhook-forward with continuous reconciliation
    ///   When the long-running app starts and enough time passes for reconciliation polling
    ///   Then it posts exactly one reply for the issue discovered by polling
    ///   And the gh webhook forward command is still invoked for the GitHub project
    ///   And the app performs more than one GitHub search request while running
    /// ```
    test('Reconcile a missed GitHub webhook event through polling', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandboxRepo = await createSandboxRepo(
        prefix: 'cws-webhook-reconcile-',
      );
      final sandbox = sandboxRepo.sandbox;
      final repoDir = sandboxRepo.repoDir;

      // And a gh script that starts webhook forwarding without delivering an event.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      final searchCountFile = File(p.join(sandbox.path, 'search-count'));
      final issue = {
        'number': 18,
        'title': 'Need reconciliation after a missed webhook',
        'body': 'Please recover this mention from polling.',
        'state': 'open',
        'html_url': 'https://example.test/issues/18',
        'updated_at': '2026-04-08T05:00:00Z',
        'user': {'login': 'reporter'},
        'labels': const <Map<String, Object?>>[],
      };
      final searchItem = {
        ...issue,
        'repository_url': 'https://api.github.com/repos/owner/sample',
      };
      final comments = [
        {
          'id': 181,
          'body': '@helper please recover this even if the webhook was missed',
          'html_url': 'https://example.test/issues/18#issuecomment-181',
          'created_at': '2026-04-08T05:00:00Z',
          'updated_at': '2026-04-08T05:00:00Z',
          'user': {'login': 'reporter'},
        },
      ];
      fakeCommandHandlers[ghScript.path] = (arguments, {timeout}) async {
        await ghLog.writeAsString(
          '${arguments.join(' ')}\n',
          mode: FileMode.append,
        );
        if (arguments.length >= 2 &&
            arguments[0] == 'api' &&
            arguments[1] == 'user') {
          return ProcessResult(0, 0, '{"login":"octocat"}', '');
        }
        final path = arguments.length > 3 ? arguments[3] : '';
        if (arguments.length >= 4 &&
            arguments[0] == 'api' &&
            path == 'search/issues') {
          var count = 0;
          if (await searchCountFile.exists()) {
            count = int.parse(await searchCountFile.readAsString());
          }
          count += 1;
          await searchCountFile.writeAsString(count.toString());
          return ProcessResult(
            0,
            0,
            jsonEncode(
              count == 1
                  ? {
                      'total_count': 0,
                      'incomplete_results': false,
                      'items': <Object?>[],
                    }
                  : {
                      'total_count': 1,
                      'incomplete_results': false,
                      'items': [searchItem],
                    },
            ),
            '',
          );
        }
        if (arguments.length >= 4 &&
            arguments[0] == 'api' &&
            path == 'repos/owner/sample/issues/18/comments?per_page=100') {
          return ProcessResult(0, 0, jsonEncode(comments), '');
        }
        if (arguments.length >= 4 &&
            arguments[0] == 'api' &&
            path == 'repos/owner/sample/issues/18/comments') {
          final body = arguments
              .where((argument) => argument.startsWith('body='))
              .map((argument) => argument.substring('body='.length))
              .firstOrNull;
          if (body != null) {
            await postedBody.writeAsString(body);
          }
          return ProcessResult(
            0,
            0,
            jsonEncode({
              'id': 703,
              'html_url': 'https://example.test/comment/703',
              'body': 'posted',
            }),
            '',
          );
        }
        return ProcessResult(
          0,
          1,
          '',
          'unexpected gh args: ${arguments.join(' ')}\n',
        );
      };
      fakeStartedCommandHandlers[ghScript.path] = (arguments) async {
        await ghLog.writeAsString(
          '${arguments.join(' ')}\n',
          mode: FileMode.append,
        );
        return FakeStartedExternalCommand();
      };

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- reconcile missed webhook events through polling',
        'summary': 'posted reconciliation advice',
      });

      // And an orchestrator-style config that uses gh/webhook-forward with continuous reconciliation.
      final configFile = await writeSingleProjectIssueAssistantConfig(
        sandbox: sandbox,
        responderPath: responderScript.path,
        provider: 'github',
        repo: 'owner/sample',
        repoPath: repoDir.path,
        eventSourceLines: const [
          'type: gh/webhook-forward',
          'reconciliation: continuous',
          'reconcileInterval: 1s',
        ],
      );
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

      // When the long-running app starts and enough time passes for reconciliation polling.
      await runAppUntil(app: app, isReady: postedBody.exists);

      // Then it posts exactly one reply for the issue discovered by polling.
      expect(await postedBody.exists(), isTrue);
      final postedComment = await postedBody.readAsString();
      expect(
        postedComment,
        contains('Plan:\n- reconcile missed webhook events through polling'),
      );

      // And the gh webhook forward command is still invoked for the GitHub project.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines.any(
          (line) => line.contains(
            'webhook forward --events=issues,issue_comment --repo=owner/sample',
          ),
        ),
        isTrue,
      );

      // And the app performs more than one GitHub search request while running.
      expect(
        logLines
            .where(
              (line) =>
                  line ==
                  'api -X GET search/issues -f q=repo:owner/sample is:issue state:open -f sort=updated -f order=asc -f per_page=100 -f page=1',
            )
            .length,
        greaterThanOrEqualTo(2),
      );
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunWebhookForwardTests();
}
