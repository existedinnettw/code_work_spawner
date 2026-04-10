import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunOnceMultiProjectTests() {
  /// ```gherkin
  /// Feature: Issue thread assistant polling
  ///
  ///   As a maintainer using the issue assistant
  ///   I want issue thread events to be evaluated through configured responders
  ///   So that users get help only when the thread actually needs a response
  /// ```
  group('IssueAssistantApp.runOnce', () {
    /// ```gherkin
    /// Scenario: Aggregate one search request across multiple enabled projects while ignoring closed issues
    ///   Given two temporary project checkouts that can be used as local repo paths
    ///   And GitHub issue data containing an explicit assistant mention in each repository
    ///   And one of the search results is a closed issue
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config with both repositories enabled
    ///   When the app processes one polling cycle
    ///   Then it fetches issue updates through one aggregate GitHub search request for open issues only
    ///   And it still posts one reply in each repository
    /// ```
    test(
      'Aggregate one search request across multiple enabled projects while ignoring closed issues',
      () async {
        // Given two temporary project checkouts that can be used as local repo paths.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-aggregate-search-',
        );
        final repoOneDir = await Directory(
          p.join(sandbox.path, 'repo-one'),
        ).create();
        final repoTwoDir = await Directory(
          p.join(sandbox.path, 'repo-two'),
        ).create();
        await initGitRepo(repoOneDir);
        await initGitRepo(repoTwoDir);

        // And GitHub issue data containing an explicit assistant mention in each repository.
        final ghScript = File(p.join(sandbox.path, 'gh'));
        final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
        await writeFakeGhScript(
          ghScript: ghScript,
          issueListResponse: const [],
          commentResponses: const {},
          issueListResponsesByRepo: {
            'owner/repo-one': [
              {
                'number': 11,
                'title': 'Repo one mention',
                'body': 'first repo',
                'state': 'open',
                'html_url': 'https://example.test/owner/repo-one/issues/11',
                'updated_at': '2026-04-04T17:00:00Z',
                'user': {'login': 'reporter-one'},
                'labels': const [],
              },
            ],
            'owner/repo-two': [
              {
                'number': 22,
                'title': 'Repo two mention',
                'body': 'second repo',
                'state': 'open',
                'html_url': 'https://example.test/owner/repo-two/issues/22',
                'updated_at': '2026-04-04T17:01:00Z',
                'user': {'login': 'reporter-two'},
                'labels': const [],
              },
              {
                'number': 23,
                'title': 'Repo two closed mention',
                'body': 'closed repo issue',
                'state': 'closed',
                'html_url': 'https://example.test/owner/repo-two/issues/23',
                'updated_at': '2026-04-04T17:02:00Z',
                'user': {'login': 'reporter-three'},
                'labels': const [],
              },
            ],
          },
          commentResponsesByRepo: {
            'owner/repo-one': {
              11: [
                {
                  'id': 110,
                  'body': '@helper please review repo one',
                  'html_url':
                      'https://example.test/owner/repo-one/issues/11#issuecomment-110',
                  'created_at': '2026-04-04T17:00:00Z',
                  'updated_at': '2026-04-04T17:00:00Z',
                  'user': {'login': 'reporter-one'},
                },
              ],
            },
            'owner/repo-two': {
              22: [
                {
                  'id': 220,
                  'body': '@helper please review repo two',
                  'html_url':
                      'https://example.test/owner/repo-two/issues/22#issuecomment-220',
                  'created_at': '2026-04-04T17:01:00Z',
                  'updated_at': '2026-04-04T17:01:00Z',
                  'user': {'login': 'reporter-two'},
                },
              ],
              23: [
                {
                  'id': 230,
                  'body': '@helper please review closed repo two',
                  'html_url':
                      'https://example.test/owner/repo-two/issues/23#issuecomment-230',
                  'created_at': '2026-04-04T17:02:00Z',
                  'updated_at': '2026-04-04T17:02:00Z',
                  'user': {'login': 'reporter-three'},
                },
              ],
            },
          },
          postCommentIssueNumbersByRepo: {
            'owner/repo-one': {11},
            'owner/repo-two': {22},
          },
          ghLog: ghLog,
        );

        // And a responder that emits a planning reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'reply',
          'mode': 'planning',
          'markdown': 'aggregate reply',
          'summary': 'posted planning advice',
        });

        // And an orchestrator-style config with both repositories enabled.
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
projects:
  repoOne:
    issueTracker:
      eventSource:
        pollInterval: 30s
    repo: owner/repo-one
    path: ${repoOneDir.path}
  repoTwo:
    issueTracker:
      eventSource:
        pollInterval: 30s
    repo: owner/repo-two
    path: ${repoTwoDir.path}
''');
        final app = await IssueAssistantApp.open(
          config: await AppConfig.load(configFile.path),
          databasePath: p.join(sandbox.path, 'state.sqlite3'),
          ghCommand: ghScript.path,
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        await app.close();

        // Then it fetches issue updates through one aggregate GitHub search request for open issues only.
        final logLines = await ghLog.readAsLines();
        final searchLogs = logLines
            .where((line) => line.contains('search/issues'))
            .toList();
        expect(searchLogs.length, 1);
        expect(searchLogs.single, contains('state:open'));

        // And it still posts one reply in each repository.
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('repos/owner/repo-one/issues/11/comments'),
              )
              .length,
          2,
        );
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('repos/owner/repo-two/issues/22/comments'),
              )
              .length,
          2,
        );
        expect(
          logLines
              .where(
                (line) =>
                    line.contains('repos/owner/repo-two/issues/23/comments'),
              )
              .length,
          0,
        );
      },
    );

    /// ```gherkin
    /// Scenario: Reply through Gitea when a user explicitly mentions the assistant
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And Gitea issue data containing a comment with an explicit assistant mention
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that marks the project provider as gitea
    ///   When the app processes one polling cycle
    ///   Then it reads issue comments and posts exactly one reply through tea for that issue
    /// ```
    test('Reply through Gitea when a user explicitly mentions the assistant', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-gitea-run-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And Gitea issue data containing a comment with an explicit assistant mention.
      final teaScript = File(p.join(sandbox.path, 'tea'));
      final teaLog = File(p.join(sandbox.path, 'tea-log.jsonl'));
      final postedBody = File(p.join(sandbox.path, 'posted-body.md'));
      await writeFakeTeaScript(
        teaScript: teaScript,
        issueListResponsesByRepo: {
          'owner/sample': [
            {
              'index': 12,
              'title': 'Need architecture help',
              'body': 'Please review the API layering.',
              'state': 'open',
              'url': 'https://gitea.example.test/owner/sample/issues/12',
              'updated_at': '2026-04-04T12:00:00Z',
              'poster': {'login': 'reporter'},
              'labels': [
                {'name': 'help'},
              ],
            },
          ],
        },
        commentResponsesByRepo: {
          'owner/sample': {
            12: [
              {
                'id': 50,
                'body': '@helper can you plan the architecture?',
                'url':
                    'https://gitea.example.test/owner/sample/issues/12#issuecomment-50',
                'created_at': '2026-04-04T12:00:00Z',
                'updated_at': '2026-04-04T12:00:00Z',
                'poster': {'login': 'reporter'},
              },
            ],
          },
        },
        postCommentIssueNumbersByRepo: {
          'owner/sample': {12},
        },
        teaLog: teaLog,
        postedBodyFile: postedBody,
        viewerLogin: 'tea-octocat',
      );

      // And a responder that emits a planning reply.
      final responderScript = File(p.join(sandbox.path, 'responder.sh'));
      await writeResponderScript(responderScript, {
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Plan:\n- keep provider-specific commands isolated',
        'summary': 'posted planning advice',
      });

      // And an orchestrator-style config that marks the project provider as gitea.
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
      eventSource:
        pollInterval: 5m
    provider: gitea
    repo: owner/sample
    path: ${repoDir.path}
    defaultBranch: main
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        teaCommand: teaScript.path,
      );

      // When the app processes one polling cycle.
      await app.runOnce();
      await app.close();

      // Then it reads issue comments and posts exactly one reply through tea for that issue.
      final logLines = await teaLog.readAsLines();
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues?state=open'),
            )
            .length,
        1,
      );
      expect(
        logLines
            .where(
              (line) => line.contains('repos/owner/sample/issues/12/comments'),
            )
            .length,
        2,
      );
      final postedComment = await postedBody.readAsString();
      expect(postedComment, contains('via `tea`'));
      expect(postedComment, contains('@tea-octocat'));
      expect(
        postedComment,
        contains('Plan:\n- keep provider-specific commands isolated'),
      );
    });

    /// ```gherkin
    /// Scenario: Reply through OpenProject when a user explicitly mentions the assistant
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And an OpenProject API fixture containing a mentioned work package
    ///   And a responder that emits a planning reply
    ///   And an orchestrator-style config that uses an OpenProject project name
    ///   When the app processes one polling cycle
    ///   Then it reads work package activities and posts exactly one reply through the OpenProject API
    /// ```
    test(
      'Reply through OpenProject when a user explicitly mentions the assistant',
      () async {
        // Given a temporary project checkout that can be used as the local repo path.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-openproject-run-',
        );
        final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
        await initGitRepo(repoDir);

        // And an OpenProject API fixture containing a mentioned work package.
        final server = await _FakeOpenProjectServer.start();
        addTearDown(server.close);

        // And a responder that emits a planning reply.
        final responderScript = File(p.join(sandbox.path, 'responder.sh'));
        await writeResponderScript(responderScript, {
          'decision': 'reply',
          'mode': 'planning',
          'markdown': 'Plan:\n- isolate tracker-specific API adapters',
          'summary': 'posted planning advice',
        });

        // And an orchestrator-style config that uses an OpenProject project name.
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
        timeout: 1m
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
        );

        // When the app processes one polling cycle.
        await app.runOnce();
        final thread = await app.database.findIssueThread('sample', 77);
        await app.close();

        // Then it reads work package activities and posts exactly one reply through the OpenProject API.
        expect(
          server.requestPaths,
          contains(
            '/api/v3/projects?pageSize=-1&filters=%5B%7B%22typeahead%22%3A%7B%22operator%22%3A%22%2A%2A%22%2C%22values%22%3A%5B%22Demo+project%22%5D%7D%7D%5D',
          ),
        );
        expect(
          server.requestPaths,
          contains(
            '/api/v3/projects/42/work_packages?pageSize=-1&filters=%5B%7B%22status%22%3A%7B%22operator%22%3A%22o%22%2C%22values%22%3A%5B%5D%7D%7D%5D',
          ),
        );
        expect(
          server.requestPaths,
          contains('/api/v3/work_packages/77/activities'),
        );
        expect(server.postedBodies, hasLength(1));
        final postedComment =
            (jsonDecode(server.postedBodies.single)
                    as Map<String, dynamic>)['comment']['raw']
                as String;
        expect(postedComment, contains('via `op`'));
        expect(postedComment, contains('@OpenProject Bot'));
        expect(
          postedComment,
          contains('Plan:\n- isolate tracker-specific API adapters'),
        );
        expect(thread, isNotNull);
        expect(
          thread!.lastCommentUrl,
          '${server.baseUrl}/api/v3/activities/701',
        );
      },
    );
  });
}

class _FakeOpenProjectServer {
  _FakeOpenProjectServer._(this._server);

  final HttpServer _server;
  final List<String> requestPaths = <String>[];
  final List<String> postedBodies = <String>[];

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_FakeOpenProjectServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _FakeOpenProjectServer._(server);
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
                    'comment': {
                      'raw': '@helper can you plan this integration?',
                    },
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

        if (request.method == 'GET' && request.uri.path == '/api/v3/users/me') {
          response.write(jsonEncode({'id': 1, 'name': 'OpenProject Bot'}));
          await response.close();
          return;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/api/v3/work_packages/77/activities') {
          final body = await utf8.decoder.bind(request).join();
          fixture.postedBodies.add(body);
          response.statusCode = HttpStatus.created;
          response.write(
            jsonEncode({
              'id': 701,
              'comment': {'raw': jsonDecode(body)['comment']['raw']},
              '_links': {
                'self': {'href': '/api/v3/activities/701'},
              },
            }),
          );
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunOnceMultiProjectTests();
}
