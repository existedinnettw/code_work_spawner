import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunGitLabGosmeeTests() {
  /// ```gherkin
  /// Feature: GitLab gosmee issue events
  ///
  ///   As a maintainer running the long-lived assistant for GitLab
  ///   I want glab/gosmee events to trigger issue evaluation without relying only on polling
  ///   So that GitLab issue and note activity can use a channel-based source
  /// ```
  group('IssueAssistantApp.run gitlab gosmee', () {
    /// ```gherkin
    /// Scenario: Reply to a mention received through glab/gosmee
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gosmee script that forwards one GitLab note webhook event
    ///   And a glab script that can manage webhooks and post issue comments
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses glab/gosmee
    ///   When the long-running app starts and receives the forwarded webhook
    ///   Then it reads issue comments and posts exactly one reply for that issue
    ///   And the GitLab webhook lifecycle commands are invoked for the project
    /// ```
    test('Reply to a mention received through glab/gosmee', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-glab-gosmee-run-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gosmee script that forwards one GitLab note webhook event.
      final gosmeeScript = File(p.join(sandbox.path, 'gosmee'));
      final gosmeeLog = File(p.join(sandbox.path, 'gosmee-log.jsonl'));
      final issue = <String, Object?>{
        'iid': 12,
        'title': 'Need channel-based trigger handling',
        'description': 'Please react to glab/gosmee.',
        'state': 'opened',
        'web_url':
            'https://gitlab.example.test/group/subgroup/sample/-/issues/12',
        'updated_at': '2026-04-08T04:00:00Z',
        'author': {'username': 'reporter'},
        'labels': const <String>[],
      };
      final comments = <Map<String, Object?>>[
        {
          'id': 51,
          'body': '@helper can you handle glab/gosmee comments?',
          'created_at': '2026-04-08T04:00:00Z',
          'updated_at': '2026-04-08T04:00:00Z',
          'author': {'username': 'reporter'},
          'noteable_url':
              'https://gitlab.example.test/group/subgroup/sample/-/issues/12',
        },
      ];
      await writeGosmeeForwardScript(
        gosmeeScript: gosmeeScript,
        publicUrl: 'https://gosmee.example.test/gitlab-sample',
        payload: {
          'object_kind': 'note',
          'project': {'path_with_namespace': 'group/subgroup/sample'},
          'issue': issue,
          'object_attributes': {
            'action': 'create',
            'note': comments.last['body'],
            'noteable_type': 'Issue',
            'url': comments.last['noteable_url'],
          },
          'user': {'username': 'reporter'},
        },
        gosmeeLog: gosmeeLog,
      );

      // And a glab script that can manage webhooks and post issue comments.
      final glabScript = File(p.join(sandbox.path, 'glab'));
      final glabLog = File(p.join(sandbox.path, 'glab-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      await writeFakeGlabScript(
        glabScript: glabScript,
        issueListResponsesByRepo: {
          'group/subgroup/sample': const <Map<String, Object?>>[],
        },
        commentResponsesByRepo: {
          'group/subgroup/sample': {12: comments},
        },
        postCommentIssueNumbersByRepo: {
          'group/subgroup/sample': {12},
        },
        glabLog: glabLog,
        postedBodyFile: postedBody,
        viewerLogin: 'glab-user',
        webhookIdsByRepo: {'group/subgroup/sample': 81},
      );

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- consume glab/gosmee issue note events',
        'summary': 'posted GitLab channel-based planning advice',
      });

      // And an orchestrator-style config that uses glab/gosmee.
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
      provider: gitlab
      eventSource:
        pollInterval: 5m
        type: glab/gosmee
    repo: group/subgroup/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        glabCommand: glabScript.path,
        gosmeeCommand: gosmeeScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );

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
        contains('Plan:\n- consume glab/gosmee issue note events'),
      );
      expect(postedComment, contains('@glab-user'));

      // And the GitLab webhook lifecycle commands are invoked for the project.
      final glabLogLines = await glabLog.readAsLines();
      expect(
        glabLogLines.any(
          (line) =>
              line.contains('api -X POST') &&
              line.contains('projects/group%2Fsubgroup%2Fsample/hooks') &&
              line.contains('issues_events=true') &&
              line.contains('note_events=true'),
        ),
        isTrue,
      );
      expect(
        glabLogLines.any(
          (line) => line.contains(
            'api -X DELETE projects/group%2Fsubgroup%2Fsample/hooks/81',
          ),
        ),
        isTrue,
      );
      final gosmeeLogLines = await gosmeeLog.readAsLines();
      expect(
        gosmeeLogLines.any(
          (line) =>
              line.contains('client https://gosmee.example.test/gitlab-sample'),
        ),
        isTrue,
      );
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunGitLabGosmeeTests();
}
