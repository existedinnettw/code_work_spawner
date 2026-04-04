import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('AppConfig.load', () {
    test(
      'given AO style config when loading then defaults and project overrides are merged',
      () async {
        // Given a config file with shared defaults and a project override.
        final tempDir = await Directory.systemTemp.createTemp('cws-config-');
        final configFile = File(
          p.join(tempDir.path, 'agent-orchestrator.yaml'),
        );
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

        // When the app config is loaded from disk.
        final config = await AppConfig.load(configFile.path);

        // Then the project inherits defaults and overrides only the prompt.
        expect(config.projects['sample'], isNotNull);
        expect(config.projects['sample']!.issueAssistant.mentionTriggers, [
          '@helper',
        ]);
        expect(
          config.projects['sample']!.issueAssistant.prompt,
          'project {{project_key}}',
        );
        expect(
          config.projects['sample']!.issueAssistant.responders.single.id,
          'fallback',
        );
      },
    );
  });

  group('IssueAssistantApp.runOnce', () {
    test(
      'given an explicit mention when polling then the app posts the responder reply once',
      () async {
        // Given a fake gh client and a fake responder that emits a planning reply.
        final sandbox = await Directory.systemTemp.createTemp('cws-run-');
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await _initGitRepo(repoDir);

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
        final replyJson = jsonEncode({
          'decision': 'reply',
          'mode': 'planning',
          'markdown': 'Plan:\n- separate service and persistence',
          'summary': 'posted planning advice',
        });
        await ghScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "${ghLog.path}"
if [[ "\$1" == "api" && "\$4" == repos/owner/sample/issues\\?* ]]; then
  cat <<'JSON'
${jsonEncode(issueData)}
JSON
  exit 0
fi
if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/12/comments?per_page=100" ]]; then
  cat <<'JSON'
${jsonEncode(commentsData)}
JSON
  exit 0
fi
if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/12/comments" ]]; then
  cat <<'JSON'
{"id": 700, "html_url": "https://example.test/comment/700", "body": "posted"}
JSON
  exit 0
fi
echo "unexpected gh args: \$*" >&2
exit 1
''');
        await Process.run('chmod', ['+x', ghScript.path]);

        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'JSON'
$replyJson
JSON
''');
        await Process.run('chmod', ['+x', responderScript.path]);

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
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${repoDir.path}
    defaultBranch: main
''');

        final config = await AppConfig.load(configFile.path);
        final app = await IssueAssistantApp.open(
          config: config,
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          ghCommand: ghScript.path,
        );

        // When the app processes a single polling cycle.
        await app.runOnce();
        await app.close();

        // Then a GitHub comment is posted for the mentioned issue.
        final logLines = await ghLog.readAsLines();
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('repos/owner/sample/issues/12/comments'),
              )
              .length,
          2,
        );
      },
    );

    test(
      'given a thread update without a useful delta when polling then the app records no reply',
      () async {
        // Given a fake gh client and a responder that explicitly returns no_reply.
        final sandbox = await Directory.systemTemp.createTemp('cws-no-reply-');
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await _initGitRepo(repoDir);

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
        final noReplyJson = jsonEncode({
          'decision': 'no_reply',
          'mode': 'planning',
          'summary': 'thread already resolved',
        });
        await ghScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "api" && "\$4" == repos/owner/sample/issues\\?* ]]; then
  cat <<'JSON'
${jsonEncode(issueData)}
JSON
  exit 0
fi
if [[ "\$1" == "api" && "\$4" == "repos/owner/sample/issues/42/comments?per_page=100" ]]; then
  cat <<'JSON'
${jsonEncode(commentsData)}
JSON
  exit 0
fi
echo "unexpected gh args: \$*" >&2
exit 1
''');
        await Process.run('chmod', ['+x', ghScript.path]);

        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'JSON'
$noReplyJson
JSON
''');
        await Process.run('chmod', ['+x', responderScript.path]);

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

        // When a poll cycle evaluates the unchanged discussion.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 42);
        await app.close();

        // Then the issue is marked as evaluated without storing a comment.
        expect(thread, isNotNull);
        expect(thread!.lastDecision, 'no_reply');
        expect(thread.lastCommentId, isNull);
      },
    );
  });
}

Future<void> _initGitRepo(Directory directory) async {
  await Process.run('git', ['init'], workingDirectory: directory.path);
  await Process.run('git', [
    'config',
    'user.email',
    'test@example.com',
  ], workingDirectory: directory.path);
  await Process.run('git', [
    'config',
    'user.name',
    'Test User',
  ], workingDirectory: directory.path);
  await File(p.join(directory.path, 'README.md')).writeAsString('repo');
  await Process.run('git', ['add', '.'], workingDirectory: directory.path);
  await Process.run('git', [
    'commit',
    '-m',
    'init',
  ], workingDirectory: directory.path);
}
