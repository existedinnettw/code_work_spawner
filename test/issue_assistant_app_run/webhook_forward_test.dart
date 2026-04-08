import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

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
      final sandbox = await Directory.systemTemp.createTemp('cws-webhook-run-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

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
    provider: github
    repo: owner/sample
    path: ${repoDir.path}
    issueAssistant:
      eventSource: gh/webhook-forward
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );

      // When the long-running app starts and receives the forwarded webhook.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 50; attempt += 1) {
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
    ///   Then the app logs the webhook-forward stderr message at severe level
    /// ```
    test('Log webhook forward stderr at error level', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-webhook-stderr-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gh script that writes a webhook creation failure to stderr while forwarding.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      await ghScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail

if [[ "\$1" == "webhook" && "\$2" == "forward" ]]; then
  echo "Error: error creating webhook: HTTP 422: Validation Failed (https://api.github.com/repos/existedinnettw/code_work_spawner/hooks)" >&2
  while true; do
    sleep 60
  done
fi

if [[ "\$1" == "api" && "\$2" == "user" ]]; then
  cat <<'JSON'
${jsonEncode({'login': 'octocat'})}
JSON
  exit 0
fi

echo "unexpected gh args: \$*" >&2
exit 1
''');
      await Process.run('chmod', ['+x', ghScript.path]);

      // And an orchestrator-style config that uses gh/webhook-forward.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
projects:
  sample:
    provider: github
    repo: owner/sample
    path: ${repoDir.path}
    issueAssistant:
      eventSource: gh/webhook-forward
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );
      final records = <LogRecord>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final subscription = Logger.root.onRecord.listen(records.add);

      // When the long-running app starts and webhook-forward emits that stderr line.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 50; attempt += 1) {
        if (records.any(
          (record) => record.message.contains('error creating webhook'),
        )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;
      await subscription.cancel();
      Logger.root.level = previousLevel;

      // Then the app logs the webhook-forward stderr message at severe level.
      expect(
        records.any(
          (record) =>
              record.level == Level.SEVERE &&
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
    ///   And an orchestrator-style config that uses gh/webhook-forward with a short poll interval
    ///   When the long-running app starts and enough time passes for reconciliation polling
    ///   Then it posts exactly one reply for the issue discovered by polling
    ///   And the gh webhook forward command is still invoked for the GitHub project
    ///   And the app performs more than one GitHub search request while running
    /// ```
    test('Reconcile a missed GitHub webhook event through polling', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-webhook-reconcile-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

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
      await ghScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${ghLog.path}"

if [[ "\$1" == "api" && "\$2" == "user" ]]; then
  cat <<'JSON'
${jsonEncode({'login': 'octocat'})}
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "search/issues" ]]; then
  count=0
  if [[ -f "${searchCountFile.path}" ]]; then
    count="\$(cat "${searchCountFile.path}")"
  fi
  count=\$((count + 1))
  printf '%s' "\$count" > "${searchCountFile.path}"
  if [[ "\$count" -eq 1 ]]; then
    cat <<'JSON'
{"total_count":0,"incomplete_results":false,"items":[]}
JSON
  else
    cat <<'JSON'
${jsonEncode({
        'total_count': 1,
        'incomplete_results': false,
        'items': [searchItem],
      })}
JSON
  fi
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/18/comments?per_page=100" ]]; then
  cat <<'JSON'
${jsonEncode(comments)}
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/18/comments" ]]; then
  for arg in "\$@"; do
    if [[ "\$arg" == body=* ]]; then
      printf '%s' "\${arg#body=}" > "${postedBody.path}"
    fi
  done
  cat <<'JSON'
${jsonEncode({'id': 703, 'html_url': 'https://example.test/comment/703', 'body': 'posted'})}
JSON
  exit 0
fi

if [[ "\$1" == "webhook" && "\$2" == "forward" ]]; then
  while true; do
    sleep 60
  done
fi

echo "unexpected gh args: \$*" >&2
exit 1
''');
      await Process.run('chmod', ['+x', ghScript.path]);

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- reconcile missed webhook events through polling',
        'summary': 'posted reconciliation advice',
      });

      // And an orchestrator-style config that uses gh/webhook-forward with a short poll interval.
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 1s
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    provider: github
    repo: owner/sample
    path: ${repoDir.path}
    issueAssistant:
      eventSource: gh/webhook-forward
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
      );

      // When the long-running app starts and enough time passes for reconciliation polling.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 50; attempt += 1) {
        if (await postedBody.exists()) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;

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
