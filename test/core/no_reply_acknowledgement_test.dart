import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// ```gherkin
  /// Feature: No-reply acknowledgements across providers
  ///
  ///   As a maintainer operating multiple tracker providers
  ///   I want no-reply decisions to leave a lightweight acknowledgement marker
  ///   So that users can tell the assistant evaluated the update without posting a full reply
  /// ```
  group('IssueAssistantApp no-reply acknowledgements', () {
    /// ```gherkin
    /// Scenario: Acknowledge no_reply on Gitea by adding an eyes reaction to the human comment
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And Gitea issue data containing a human comment with an explicit assistant mention
    ///   And a responder that returns no_reply
    ///   And an orchestrator-style config that marks the project provider as gitea
    ///   When the app processes one polling cycle
    ///   Then it records the evaluation result as no_reply
    ///   And it patches the triggering Gitea comment with an eyes reaction
    ///   And it does not post a normal issue comment
    /// ```
    test(
      'Acknowledge no_reply on Gitea by adding an eyes reaction to the human comment',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-gitea-no-reply-ack-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And Gitea issue data containing a human comment with an explicit assistant mention.
        final giteaServer = await FakeGiteaApiServer.start(
          issueListResponsesByRepo: {
            'owner/sample': [
              {
                'number': 12,
                'title': 'Need architecture help',
                'body': 'Please review the API layering.',
                'state': 'open',
                'html_url': 'https://gitea.example.test/owner/sample/issues/12',
                'updated_at': '2026-04-04T12:00:00Z',
                'user': {'login': 'reporter'},
                'labels': const [],
                'pull_request': null,
              },
            ],
          },
          commentResponsesByRepo: {
            'owner/sample': {
              12: [
                {
                  'id': 50,
                  'body': '@helper this thread is already complete',
                  'html_url':
                      'https://gitea.example.test/owner/sample/issues/12#issuecomment-50',
                  'created_at': '2026-04-04T12:00:00Z',
                  'updated_at': '2026-04-04T12:00:00Z',
                  'user': {'login': 'reporter'},
                },
              ],
            },
          },
        );
        addTearDown(giteaServer.close);

        // And a responder that returns no_reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'no_reply',
          'mode': 'planning',
          'summary': 'thread already resolved',
        });

        // And an orchestrator-style config that marks the project provider as gitea.
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
    provider: gitea
    repo: owner/sample
    path: ${repoDir.path}
    defaultBranch: main
''');
        await File(p.join(sandbox.path, '.env')).writeAsString('''
CWS_GITEA_HOST=${giteaServer.baseUrl}
CWS_GITEA_TOKEN=test-token
''');
        final app = await IssueAssistantApp.open(
          config: await AppConfig.load(configFile.path),
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          responderRunner: fakeResponderRunner(),
          commandExecutor: fakeExternalCommandExecutor(),
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 12);
        await app.close();

        // Then it records the evaluation result as no_reply.
        expect(thread, isNotNull);
        expect(thread!.lastDecision, 'no_reply');
        expect(thread.lastCommentId, isNull);

        // And it patches the triggering Gitea comment with an eyes reaction.
        expect(
          giteaServer.requestPaths,
          contains('/api/v1/repos/owner/sample/issues/comments/50/reactions'),
        );
        expect(giteaServer.reactionBodies, hasLength(1));
        expect(
          (jsonDecode(giteaServer.reactionBodies.single)
              as Map<String, dynamic>)['content'],
          'eyes',
        );

        // And it does not post a normal issue comment.
        expect(giteaServer.postedBodies, isEmpty);
      },
    );

    /// ```gherkin
    /// Scenario: Acknowledge no_reply on GitLab by adding an eyes award emoji to the note
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And GitLab issue data containing a human note with an explicit assistant mention
    ///   And a responder that returns no_reply
    ///   And an orchestrator-style config that marks the project provider as gitlab
    ///   When the app processes one polling cycle
    ///   Then it records the evaluation result as no_reply
    ///   And it adds an eyes award emoji to the triggering GitLab note
    ///   And it does not post a normal issue note
    /// ```
    test(
      'Acknowledge no_reply on GitLab by adding an eyes award emoji to the note',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-gitlab-no-reply-ack-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And GitLab issue data containing a human note with an explicit assistant mention.
        final glabScript = File(p.join(sandbox.path, 'glab'));
        final glabLog = File(p.join(sandbox.path, 'glab-log.jsonl'));
        final reactionBody = File(p.join(sandbox.path, 'reaction-body.txt'));
        await writeFakeGlabScript(
          glabScript: glabScript,
          issueListResponsesByRepo: {
            'group/subgroup/sample': [
              {
                'iid': 12,
                'title': 'Need GitLab support',
                'description': 'Please add glab support.',
                'state': 'opened',
                'web_url':
                    'https://gitlab.example.test/group/subgroup/sample/issues/12',
                'updated_at': '2026-04-04T12:00:00Z',
                'author': {'username': 'reporter'},
                'labels': const <String>[],
              },
            ],
          },
          commentResponsesByRepo: {
            'group/subgroup/sample': {
              12: [
                {
                  'id': 501,
                  'body': '@helper this thread is already complete',
                  'created_at': '2026-04-04T12:00:00Z',
                  'updated_at': '2026-04-04T12:00:00Z',
                  'author': {'username': 'reporter'},
                },
              ],
            },
          },
          glabLog: glabLog,
          reactionBodyFile: reactionBody,
        );

        // And a responder that returns no_reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'no_reply',
          'mode': 'planning',
          'summary': 'thread already resolved',
        });

        // And an orchestrator-style config that marks the project provider as gitlab.
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
    provider: gitlab
    repo: group/subgroup/sample
    path: ${repoDir.path}
    defaultBranch: main
''');
        final app = await IssueAssistantApp.open(
          config: await AppConfig.load(configFile.path),
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          glabCommand: glabScript.path,
          responderRunner: fakeResponderRunner(),
          commandExecutor: fakeExternalCommandExecutor(),
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 12);
        await app.close();

        // Then it records the evaluation result as no_reply.
        expect(thread, isNotNull);
        expect(thread!.lastDecision, 'no_reply');
        expect(thread.lastCommentId, isNull);

        // And it adds an eyes award emoji to the triggering GitLab note.
        final logLines = await glabLog.readAsLines();
        expect(
          logLines
              .where(
                (line) => line.contains(
                  'projects/group%2Fsubgroup%2Fsample/issues/12/notes/501/award_emoji',
                ),
              )
              .length,
          1,
        );
        expect(await reactionBody.readAsString(), 'eyes');

        // And it does not post a normal issue note.
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('-X POST') &&
                    line.contains(
                      'projects/group%2Fsubgroup%2Fsample/issues/12/notes ',
                    ),
              )
              .length,
          0,
        );
      },
    );

    /// ```gherkin
    /// Scenario: Acknowledge no_reply on OpenProject by toggling an eyes emoji on the activity
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And an OpenProject API fixture containing a human activity comment with an explicit assistant mention
    ///   And a responder that returns no_reply
    ///   And an orchestrator-style config that uses OpenProject as the tracker provider
    ///   When the app processes one polling cycle
    ///   Then it records the evaluation result as no_reply
    ///   And it toggles the eyes emoji reaction for the triggering OpenProject activity
    ///   And it does not post a normal OpenProject activity comment
    /// ```
    test(
      'Acknowledge no_reply on OpenProject by toggling an eyes emoji on the activity',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-openproject-no-reply-ack-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And an OpenProject API fixture containing a human activity comment with an explicit assistant mention.
        final server = await _FakeOpenProjectNoReplyServer.start();
        addTearDown(server.close);

        // And a responder that returns no_reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'no_reply',
          'mode': 'planning',
          'summary': 'thread already covered',
        });

        // And an orchestrator-style config that uses OpenProject as the tracker provider.
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
      provider: openproject
    scm:
      provider: github
    repo: Demo project
    path: ${repoDir.path}
    defaultBranch: main
''');
        await File(p.join(sandbox.path, '.env')).writeAsString('''
OP_CLI_HOST=${server.baseUrl}
OP_CLI_TOKEN=test-token
''');
        final app = await IssueAssistantApp.open(
          config: await AppConfig.load(configFile.path),
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          responderRunner: fakeResponderRunner(),
          commandExecutor: fakeExternalCommandExecutor(),
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 77);
        await app.close();

        // Then it records the evaluation result as no_reply.
        expect(thread, isNotNull);
        expect(thread!.lastDecision, 'no_reply');
        expect(thread.lastCommentId, isNull);

        // And it toggles the eyes emoji reaction for the triggering OpenProject activity.
        expect(
          server.requestPaths,
          contains('/api/v3/activities/501/emoji_reactions'),
        );
        expect(server.reactionBodies, hasLength(1));
        expect(
          (jsonDecode(server.reactionBodies.single)
              as Map<String, dynamic>)['reaction'],
          'eyes',
        );

        // And it does not post a normal OpenProject activity comment.
        expect(server.postedBodies, isEmpty);
      },
    );
  });
}

class _FakeOpenProjectNoReplyServer {
  _FakeOpenProjectNoReplyServer._(this._server);

  final HttpServer _server;
  final List<String> requestPaths = <String>[];
  final List<String> postedBodies = <String>[];
  final List<String> reactionBodies = <String>[];

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeOpenProjectNoReplyServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _FakeOpenProjectNoReplyServer._(server);
    unawaited(
      server.forEach((request) async {
        fixture.requestPaths.add(request.uri.toString());
        final authHeader = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        if (authHeader !=
            'Basic ${base64Encode(utf8.encode('apikey:test-token'))}') {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }

        final response = request.response
          ..headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.path == '/api/v3/projects') {
          response.write(
            jsonEncode({
              '_embedded': {
                'elements': [
                  {'id': 42, 'name': 'Demo project'},
                ],
              },
            }),
          );
          await response.close();
          return;
        }

        if (request.method == 'GET' &&
            request.uri.path == '/api/v3/projects/42/work_packages') {
          response.write(
            jsonEncode({
              '_embedded': {
                'elements': [
                  {
                    'id': 77,
                    'subject': 'Need OpenProject support',
                    'updatedAt': '2026-04-04T12:00:00Z',
                    'description': {'raw': 'Please add OpenProject support.'},
                    '_links': {
                      'self': {
                        'href': 'https://openproject.example.test/wp/77',
                      },
                      'author': {'title': 'reporter'},
                    },
                  },
                ],
              },
            }),
          );
          await response.close();
          return;
        }

        if (request.method == 'GET' &&
            request.uri.path == '/api/v3/work_packages/77/activities') {
          response.write(
            jsonEncode({
              '_embedded': {
                'elements': [
                  {
                    'id': 501,
                    'comment': {'raw': '@helper this is already resolved'},
                    'createdAt': '2026-04-04T12:00:00Z',
                    'updatedAt': '2026-04-04T12:00:00Z',
                    '_links': {
                      'self': {'href': '/api/v3/activities/501'},
                      'user': {'title': 'reporter'},
                    },
                  },
                ],
              },
            }),
          );
          await response.close();
          return;
        }

        if (request.method == 'PATCH' &&
            request.uri.path == '/api/v3/activities/501/emoji_reactions') {
          final body = await utf8.decoder.bind(request).join();
          fixture.reactionBodies.add(body);
          response.write(
            jsonEncode({
              '_type': 'EmojiReaction',
              'id': '501-eyes',
              'reaction': 'eyes',
              'emoji': 'eyes',
            }),
          );
          await response.close();
          return;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/api/v3/work_packages/77/activities') {
          final body = await utf8.decoder.bind(request).join();
          fixture.postedBodies.add(body);
          response.statusCode = HttpStatus.created;
          response.write(jsonEncode({'id': 701}));
          await response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }),
    );
    return fixture;
  }

  Future<void> close() => _server.close(force: true);
}
