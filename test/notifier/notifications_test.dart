import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunOnceNotificationTests() {
  /// ```gherkin
  /// Feature: Issue thread assistant polling
  ///
  ///   As a maintainer using the issue assistant
  ///   I want issue thread events to be evaluated through configured responders
  ///   So that users get help only when the thread actually needs a response
  /// ```
  group('IssueAssistantApp.runOnce', () {
    /// ```gherkin
    /// Scenario: Cache authenticated gh login across multiple replies
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing two issues that explicitly mention the assistant
    ///   And a responder that replies to both issues
    ///   And an orchestrator-style config pointing to the fake repo and responder
    ///   When the app processes one polling cycle
    ///   Then it looks up the authenticated gh login only once
    ///   And it still posts one comment per issue
    /// ```
    test('Cache authenticated gh login across multiple replies', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-gh-cache-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And GitHub issue data containing two issues that explicitly mention the assistant.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final issueData = [
        {
          'number': 31,
          'title': 'First mention',
          'body': 'first',
          'state': 'open',
          'html_url': 'https://example.test/issues/31',
          'updated_at': '2026-04-04T16:00:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
        {
          'number': 32,
          'title': 'Second mention',
          'body': 'second',
          'state': 'open',
          'html_url': 'https://example.test/issues/32',
          'updated_at': '2026-04-04T16:01:00Z',
          'user': {'login': 'reporter'},
          'labels': const [],
        },
      ];
      await writeFakeGhScript(
        ghScript: ghScript,
        issueListResponse: issueData,
        commentResponses: {
          31: [
            {
              'id': 310,
              'body': '@helper first',
              'html_url': 'https://example.test/issues/31#issuecomment-310',
              'created_at': '2026-04-04T16:00:00Z',
              'updated_at': '2026-04-04T16:00:00Z',
              'user': {'login': 'reporter'},
            },
          ],
          32: [
            {
              'id': 320,
              'body': '@helper second',
              'html_url': 'https://example.test/issues/32#issuecomment-320',
              'created_at': '2026-04-04T16:01:00Z',
              'updated_at': '2026-04-04T16:01:00Z',
              'user': {'login': 'reporter'},
            },
          ],
        },
        postCommentIssueNumbers: {31, 32},
        ghLog: ghLog,
        viewerLogin: 'octocat',
      );

      // And a responder that replies to both issues.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'cached login reply',
        'summary': 'posted',
      });

      // And an orchestrator-style config pointing to the fake repo and responder.
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

      // Then it looks up the authenticated gh login only once.
      final logLines = await ghLog.readAsLines();
      expect(logLines.where((line) => line == 'api user').length, 1);

      // And it still posts one comment per issue.
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/31/comments'),
            )
            .length,
        2,
      );
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/32/comments'),
            )
            .length,
        2,
      );
    });

    /// ```gherkin
    /// Scenario: Send Discord webhook notifications for mention and reply events
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitHub issue data containing an explicit assistant mention
    ///   And a responder that emits a planning reply
    ///   And a local webhook server that records notification requests
    ///   And an orchestrator-style config with a discord webhook notifier
    ///   When the app processes one polling cycle
    ///   Then the webhook server receives one mention_detected notification
    ///   And the webhook server receives one reply_posted notification
    /// ```
    test(
      'Send Discord webhook notifications for mention and reply events',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-discord-notify-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And GitHub issue data containing an explicit assistant mention.
        final ghScript = File(p.join(sandbox.path, 'gh'));
        final issueData = [
          {
            'number': 61,
            'title': 'Need architecture help',
            'body': 'Please review the notifier design.',
            'state': 'open',
            'html_url': 'https://example.test/issues/61',
            'updated_at': '2026-04-04T17:10:00Z',
            'user': {'login': 'reporter'},
            'labels': const [],
          },
        ];
        final commentsData = [
          {
            'id': 610,
            'body': '@helper please review the notifier design',
            'html_url': 'https://example.test/issues/61#issuecomment-610',
            'created_at': '2026-04-04T17:10:00Z',
            'updated_at': '2026-04-04T17:10:00Z',
            'user': {'login': 'reporter'},
          },
        ];
        await writeFakeGhScript(
          ghScript: ghScript,
          issueListResponse: issueData,
          commentResponses: {61: commentsData},
          postCommentIssueNumber: 61,
        );

        // And a responder that emits a planning reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'reply',
          'mode': 'planning',
          'markdown': 'discord notification reply',
          'summary': 'posted planning advice',
        });

        // And a local webhook server that records notification requests.
        final requests = <Map<String, dynamic>>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        unawaited(() async {
          await for (final request in server) {
            final body = await utf8.decoder.bind(request).join();
            requests.add(jsonDecode(body) as Map<String, dynamic>);
            request.response.statusCode = HttpStatus.noContent;
            await request.response.close();
          }
        }());

        // And an orchestrator-style config with a discord webhook notifier.
        final configFile = File(
          p.join(sandbox.path, 'agent-orchestrator.yaml'),
        );
        await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: ${responderScript.path}
    notifications:
      - type: discordWebhook
        enabled: true
        events: ["mention_detected", "reply_posted"]
        webhookUrl: http://${server.address.host}:${server.port}/discord
        username: code-work-spawner
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
        await server.close(force: true);

        // Then the webhook server receives one mention_detected notification.
        expect(requests, hasLength(2));
        expect(requests.first['username'], 'code-work-spawner');
        expect(
          requests.first['content'] as String,
          contains('**Mention detected**'),
        );

        // And the webhook server receives one reply_posted notification.
        expect(
          requests.last['content'] as String,
          contains('**Reply posted**'),
        );
        expect(
          requests.last['content'] as String,
          contains('summary: posted planning advice'),
        );
      },
    );
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunOnceNotificationTests();
}
