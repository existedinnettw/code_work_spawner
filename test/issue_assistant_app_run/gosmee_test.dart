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
    ///   And a tea script that can manage webhooks and post issue comments
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses tea/gosmee
    ///   When the long-running app starts and receives the forwarded webhook
    ///   Then it reads issue comments and posts exactly one reply for that issue
    ///   And the tea webhook lifecycle commands are invoked for the Gitea project
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

      // And a tea script that can manage webhooks and post issue comments.
      final teaScript = File(p.join(sandbox.path, 'tea'));
      final teaLog = File(p.join(sandbox.path, 'tea-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      await teaScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${teaLog.path}"

if [[ "\$1" == "api" && "\$2" == "user" ]]; then
  cat <<'JSON'
${jsonEncode({'login': 'tea-octocat'})}
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == repos/owner/sample/issues\\?state=open* ]]; then
  cat <<'JSON'
[]
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/12/comments?limit=100" ]]; then
  cat <<'JSON'
${jsonEncode(comments)}
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/12/comments" ]]; then
  for arg in "\$@"; do
    if [[ "\$arg" == body=* ]]; then
      printf '%s' "\${arg#body=}" > "${postedBody.path}"
    fi
  done
  cat <<'JSON'
${jsonEncode({'id': 801, 'url': 'https://gitea.example.test/comment/801', 'body': 'posted'})}
JSON
  exit 0
fi

if [[ "\$1" == "webhooks" && "\$2" == "create" ]]; then
  cat <<'JSON'
${jsonEncode({'id': 81})}
JSON
  exit 0
fi

if [[ "\$1" == "webhooks" && "\$2" == "delete" ]]; then
  exit 0
fi

echo "unexpected tea args: \$*" >&2
exit 1
''');
      await Process.run('chmod', ['+x', teaScript.path]);

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
    pollInterval: 5m
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
        timeout: 1m
projects:
  sample:
    provider: gitea
    repo: owner/sample
    path: ${repoDir.path}
    issueAssistant:
      eventSource: tea/gosmee
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        gosmeeCommand: gosmeeScript.path,
        teaCommand: teaScript.path,
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
        contains('Plan:\n- consume gosmee issue_comment events'),
      );
      expect(postedComment, contains('@tea-octocat'));

      // And the tea webhook lifecycle commands are invoked for the Gitea project.
      final teaLogLines = await teaLog.readAsLines();
      expect(
        teaLogLines.any(
          (line) => line.contains(
            'webhooks create --type gitea --events issues,issue_comment --active -o json -r owner/sample https://gosmee.example.test/sample',
          ),
        ),
        isTrue,
      );
      expect(
        teaLogLines.any(
          (line) =>
              line.contains('webhooks delete --confirm -r owner/sample 81'),
        ),
        isTrue,
      );
    });

    /// ```gherkin
    /// Scenario: Reconcile a missed Gitea gosmee event through polling
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee script that starts forwarding without delivering an event
    ///   And a tea script that returns a new issue only on a later reconciliation poll
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses tea/gosmee with a short poll interval
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
      await gosmeeScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${gosmeeLog.path}"

if [[ "\$1" == "--output" && "\$2" == "json" && "\$3" == "client" && "\$4" == "--new-url" ]]; then
  printf '%s\n' 'https://gosmee.example.test/reconcile'
  exit 0
fi

if [[ "\$1" == "client" ]]; then
  while true; do
    sleep 60
  done
fi

echo "unexpected gosmee args: \$*" >&2
exit 1
''');
      await Process.run('chmod', ['+x', gosmeeScript.path]);

      // And a tea script that returns a new issue only on a later reconciliation poll.
      final teaScript = File(p.join(sandbox.path, 'tea'));
      final teaLog = File(p.join(sandbox.path, 'tea-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      final issueListCount = File(p.join(sandbox.path, 'issue-list-count'));
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
      await teaScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${teaLog.path}"

if [[ "\$1" == "api" && "\$2" == "user" ]]; then
  cat <<'JSON'
${jsonEncode({'login': 'tea-octocat'})}
JSON
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == repos/owner/sample/issues\\?state=open* ]]; then
  count=0
  if [[ -f "${issueListCount.path}" ]]; then
    count="\$(cat "${issueListCount.path}")"
  fi
  count=\$((count + 1))
  printf '%s' "\$count" > "${issueListCount.path}"
  if [[ "\$count" -eq 1 ]]; then
    cat <<'JSON'
[]
JSON
  else
    cat <<'JSON'
${jsonEncode([issue])}
JSON
  fi
  exit 0
fi

if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/18/comments?limit=100" ]]; then
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
${jsonEncode({'id': 802, 'url': 'https://gitea.example.test/comment/802', 'body': 'posted'})}
JSON
  exit 0
fi

if [[ "\$1" == "webhooks" && "\$2" == "create" ]]; then
  cat <<'JSON'
${jsonEncode({'id': 82})}
JSON
  exit 0
fi

if [[ "\$1" == "webhooks" && "\$2" == "delete" ]]; then
  exit 0
fi

echo "unexpected tea args: \$*" >&2
exit 1
''');
      await Process.run('chmod', ['+x', teaScript.path]);

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- reconcile missed gosmee events through polling',
        'summary': 'posted reconciliation advice',
      });

      // And an orchestrator-style config that uses tea/gosmee with a short poll interval.
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
    provider: gitea
    repo: owner/sample
    path: ${repoDir.path}
    issueAssistant:
      eventSource: tea/gosmee
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        gosmeeCommand: gosmeeScript.path,
        teaCommand: teaScript.path,
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
        contains('Plan:\n- reconcile missed gosmee events through polling'),
      );

      // And the app performs more than one Gitea issue listing request while running.
      final teaLogLines = await teaLog.readAsLines();
      expect(
        teaLogLines
            .where(
              (line) => line.contains('repos/owner/sample/issues?state=open'),
            )
            .length,
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
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunGosmeeTests();
}
