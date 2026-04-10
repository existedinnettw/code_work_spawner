import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  /// ```gherkin
  /// Feature: Issue tracker payload mapping
  ///
  ///   As a maintainer extending tracker providers
  ///   I want issue summaries to serialize and deserialize consistently
  ///   So that stored tracker state can be reused safely across provider-specific API calls
  /// ```
  group('GitHubIssueSummary.fromJson', () {
    /// ```gherkin
    /// Scenario: Preserve repository slugs for repository-backed trackers
    ///   Given a GitHub issue summary created from a repository-backed tracker payload
    ///   When the summary is serialized and read back through fromJson
    ///   Then the repository slug remains available on the deserialized summary
    ///   And requiredRepoSlug still returns the original owner and repository
    /// ```
    test('Preserve repository slugs for repository-backed trackers', () {
      // Given a GitHub issue summary created from a repository-backed tracker payload.
      final original = GitHubIssueSummary.fromRepositoryJson(
        RepositorySlug('owner', 'sample'),
        <String, dynamic>{
          'number': 12,
          'title': 'Need architecture help',
          'body': 'Please review the API layering.',
          'state': 'open',
          'html_url': 'https://example.test/issues/12',
          'updated_at': '2026-04-04T12:00:00Z',
          'user': <String, dynamic>{'login': 'reporter'},
          'labels': <Map<String, String>>[
            <String, String>{'name': 'help'},
          ],
        },
      );

      // When the summary is serialized and read back through fromJson.
      final restored = GitHubIssueSummary.fromJson(
        original.toJson().cast<String, dynamic>(),
      );

      // Then the repository slug remains available on the deserialized summary.
      expect(restored.repoSlug, isNotNull);

      // And requiredRepoSlug still returns the original owner and repository.
      expect(restored.requiredRepoSlug.owner, 'owner');
      expect(restored.requiredRepoSlug.name, 'sample');
    });

    /// ```gherkin
    /// Scenario: Preserve GitLab project paths without forcing owner/repo slugs
    ///   Given a GitLab issue summary created from a namespaced GitLab project payload
    ///   When the summary is serialized and read back through fromJson
    ///   Then the original GitLab project path remains available on the deserialized summary
    ///   And the deserialized summary does not invent a two-segment repository slug
    /// ```
    test('Preserve GitLab project paths without forcing owner/repo slugs', () {
      // Given a GitLab issue summary created from a namespaced GitLab project payload.
      final original = GitHubIssueSummary.fromGitLabJson(
        'group/subgroup/sample',
        <String, dynamic>{
          'iid': 12,
          'title': 'Need GitLab support',
          'description': 'Please add glab support.',
          'state': 'opened',
          'web_url':
              'https://gitlab.example.test/group/subgroup/sample/issues/12',
          'updated_at': '2026-04-04T12:00:00Z',
          'author': <String, dynamic>{'username': 'reporter'},
          'labels': <String>['enhancement'],
        },
      );

      // When the summary is serialized and read back through fromJson.
      final restored = GitHubIssueSummary.fromJson(
        original.toJson().cast<String, dynamic>(),
      );

      // Then the original GitLab project path remains available on the deserialized summary.
      expect(restored.trackerProject, 'group/subgroup/sample');

      // And the deserialized summary does not invent a two-segment repository slug.
      expect(restored.repoSlug, isNull);
    });
  });

  /// ```gherkin
  /// Feature: GitLab tracker client integration
  ///
  ///   As a maintainer adding GitLab issue tracking
  ///   I want the tracker client to talk to glab and normalize GitLab payloads
  ///   So that polling, thread loading, and comment posting work like the existing providers
  /// ```
  group('IssueTrackerClient GitLab', () {
    /// ```gherkin
    /// Scenario: Fetch GitLab issues, comments, and login through glab
    ///   Given a fake glab executable with one GitLab issue and one note
    ///   When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment
    ///   Then the GitLab issue payload is normalized into the shared issue summary model
    ///   And GitLab note URLs fall back to the issue note anchor when the API omits a web URL
    /// ```
    test('Fetch GitLab issues, comments, and login through glab', () async {
      // Given a fake glab executable with one GitLab issue and one note.
      final sandbox = await Directory.systemTemp.createTemp('cws-glab-');
      final glabScript = File(p.join(sandbox.path, 'glab'));
      final postedBodyFile = File(p.join(sandbox.path, 'posted-body.txt'));
      await writeFakeGlabScript(
        glabScript: glabScript,
        issueListResponsesByRepo: <String, List<Map<String, Object?>>>{
          'group/subgroup/sample': <Map<String, Object?>>[
            <String, Object?>{
              'iid': 12,
              'title': 'Need GitLab support',
              'description': 'Please add glab support.',
              'state': 'opened',
              'web_url':
                  'https://gitlab.example.test/group/subgroup/sample/issues/12',
              'updated_at': '2026-04-04T12:00:00Z',
              'author': <String, Object?>{'username': 'reporter'},
              'labels': <String>['enhancement'],
            },
          ],
        },
        commentResponsesByRepo: <String, Map<int, List<Map<String, Object?>>>>{
          'group/subgroup/sample': <int, List<Map<String, Object?>>>{
            12: <Map<String, Object?>>[
              <String, Object?>{
                'id': 501,
                'body': 'Working on it.',
                'created_at': '2026-04-04T12:05:00Z',
                'updated_at': '2026-04-04T12:06:00Z',
                'author': <String, Object?>{'username': 'maintainer'},
              },
            ],
          },
        },
        postedBodyFile: postedBodyFile,
        viewerLogin: 'glab-user',
      );
      final client = IssueTrackerClient(glabCommand: glabScript.path);

      // When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment.
      final issues = await client.fetchUpdatedIssuesForRepos(
        provider: IssueTrackerProvider.gitlab,
        trackerProjects: const <String>['group/subgroup/sample'],
        since: null,
      );
      final thread = await client.fetchThread(
        provider: IssueTrackerProvider.gitlab,
        trackerProject: 'group/subgroup/sample',
        issue: issues.single,
      );
      final login = await client.getAuthenticatedLogin(
        provider: IssueTrackerProvider.gitlab,
      );
      final posted = await client.createIssueComment(
        provider: IssueTrackerProvider.gitlab,
        trackerProject: 'group/subgroup/sample',
        issueNumber: 12,
        body: 'Reply from glab',
      );

      // Then the GitLab issue payload is normalized into the shared issue summary model.
      expect(client.trackerCliName(IssueTrackerProvider.gitlab), 'glab');
      expect(login, 'glab-user');
      expect(issues.single.trackerProject, 'group/subgroup/sample');
      expect(issues.single.repoSlug, isNull);
      expect(issues.single.number, 12);
      expect(issues.single.state, 'opened');
      expect(issues.single.labels, ['enhancement']);

      // And GitLab note URLs fall back to the issue note anchor when the API omits a web URL.
      expect(thread.comments.single.url, endsWith('/issues/12#note_501'));
      expect(await postedBodyFile.readAsString(), 'Reply from glab');
      expect(posted.id, 901);
      expect(posted.url, endsWith('/issues/12#note_901'));
      expect(posted.body, 'posted');
    });
  });

  /// ```gherkin
  /// Feature: Gitea tracker client integration
  ///
  ///   As a maintainer debugging Gitea tracker failures
  ///   I want issue operations to use the Gitea HTTP API directly
  ///   So that issue polling and replies do not depend on `tea api`
  /// ```
  group('IssueTrackerClient Gitea', () {
    setUp(() {
      AppEnvironment.resetForTest();
    });

    tearDown(() {
      AppEnvironment.resetForTest();
    });

    /// ```gherkin
    /// Scenario: Create a Gitea webhook through the HTTP API
    ///   Given a local Gitea API server that accepts webhook creation requests
    ///   When the tracker client creates a Gitea webhook
    ///   Then it returns the created webhook id
    ///   And the webhook options are sent to the Gitea API
    /// ```
    test('Create a Gitea webhook through the HTTP API', () async {
      // Given a local Gitea API server that accepts webhook creation requests.
      final giteaServer = await FakeGiteaApiServer.start();
      _configureGiteaTestEnvironmentFromBaseUrl(giteaServer.baseUrl);
      final client = IssueTrackerClient();

      try {
        // When the tracker client creates a Gitea webhook.
        final webhookId = await client.createGiteaIssueWebhook(
          repo: RepositorySlug('owner', 'sample'),
          url: 'https://gosmee.example.test/sample',
        );

        // Then it returns the created webhook id.
        expect(webhookId, 81);

        // And the webhook options are sent to the Gitea API.
        expect(giteaServer.createdWebhooks, hasLength(1));
        expect(giteaServer.createdWebhooks.single['type'], 'gitea');
        expect(giteaServer.createdWebhooks.single['active'], isTrue);
        expect(giteaServer.createdWebhooks.single['events'], [
          'issues',
          'issue_comment',
        ]);
        expect(
          (giteaServer.createdWebhooks.single['config'] as Map)['url'],
          'https://gosmee.example.test/sample',
        );
      } finally {
        await giteaServer.close();
      }
    });

    /// ```gherkin
    /// Scenario: Fetch Gitea issues, comments, and login through the HTTP API
    ///   Given a local Gitea API server with one issue and one comment
    ///   When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment
    ///   Then the Gitea issue payload is normalized into the shared issue summary model
    ///   And the posted comment response is returned to the caller
    /// ```
    test('Fetch Gitea issues, comments, and login through the HTTP API', () async {
      // Given a local Gitea API server with one issue and one comment.
      String? postedBody;
      final server = await _startGiteaApiServer((request) async {
        if (request.uri.path == '/api/v1/repos/owner/sample/issues' &&
            request.method == 'GET') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'number': 12,
                  'title': 'Need Gitea support',
                  'body': 'Please add direct API support.',
                  'state': 'open',
                  'html_url':
                      'https://gitea.example.test/owner/sample/issues/12',
                  'updated_at': '2026-04-04T12:00:00Z',
                  'user': <String, Object?>{'login': 'reporter'},
                  'labels': <Map<String, Object?>>[
                    <String, Object?>{'name': 'enhancement'},
                  ],
                  'pull_request': null,
                },
              ]),
            );
          await request.response.close();
          return;
        }

        if (request.uri.path ==
                '/api/v1/repos/owner/sample/issues/12/comments' &&
            request.method == 'GET') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'id': 501,
                  'body': 'Working on it.',
                  'created_at': '2026-04-04T12:05:00Z',
                  'updated_at': '2026-04-04T12:06:00Z',
                  'html_url':
                      'https://gitea.example.test/owner/sample/issues/12#issuecomment-501',
                  'user': <String, Object?>{'login': 'maintainer'},
                },
              ]),
            );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/api/v1/user' && request.method == 'GET') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(<String, Object?>{'login': 'gitea-user'}));
          await request.response.close();
          return;
        }

        if (request.uri.path ==
                '/api/v1/repos/owner/sample/issues/12/comments' &&
            request.method == 'POST') {
          postedBody =
              (jsonDecode(await utf8.decodeStream(request))
                      as Map<String, dynamic>)['body']
                  as String?;
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'id': 901,
                'body': 'posted',
                'html_url':
                    'https://gitea.example.test/owner/sample/issues/12#issuecomment-901',
              }),
            );
          await request.response.close();
          return;
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{'message': 'not found'}));
        await request.response.close();
      });
      _configureGiteaTestEnvironment(server);
      final client = IssueTrackerClient();

      try {
        // When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment.
        final issues = await client.fetchUpdatedIssuesForRepos(
          provider: IssueTrackerProvider.gitea,
          trackerProjects: const <String>['owner/sample'],
          since: null,
        );
        final thread = await client.fetchThread(
          provider: IssueTrackerProvider.gitea,
          trackerProject: 'owner/sample',
          issue: issues.single,
        );
        final login = await client.getAuthenticatedLogin(
          provider: IssueTrackerProvider.gitea,
        );
        final posted = await client.createIssueComment(
          provider: IssueTrackerProvider.gitea,
          trackerProject: 'owner/sample',
          issueNumber: 12,
          body: 'Reply from gitea api',
        );

        // Then the Gitea issue payload is normalized into the shared issue summary model.
        expect(login, 'gitea-user');
        expect(issues.single.trackerProject, 'owner/sample');
        expect(issues.single.number, 12);
        expect(issues.single.state, 'open');
        expect(issues.single.labels, ['enhancement']);
        expect(thread.comments.single.url, contains('#issuecomment-501'));

        // And the posted comment response is returned to the caller.
        expect(postedBody, 'Reply from gitea api');
        expect(posted.id, 901);
        expect(posted.url, contains('#issuecomment-901'));
        expect(posted.body, 'posted');
      } finally {
        await server.close(force: true);
      }
    });

    /// ```gherkin
    /// Scenario: Reuse a tea login from the Windows app data config path
    ///   Given a tea config file under LOCALAPPDATA with a default Gitea login
    ///   When the tracker client resolves the authenticated Gitea login
    ///   Then it calls the Gitea HTTP API using the host and token from that config file
    /// ```
    test('Reuse a tea login from the Windows app data config path', () async {
      // Given a tea config file under LOCALAPPDATA with a default Gitea login.
      final sandbox = await Directory.systemTemp.createTemp('cws-tea-config-');
      final localAppData = Directory(p.join(sandbox.path, 'AppData', 'Local'));
      final teaConfigDir = Directory(p.join(localAppData.path, 'tea'));
      await teaConfigDir.create(recursive: true);

      late final HttpServer server;
      server = await _startGiteaApiServer((request) async {
        expect(request.uri.path, '/api/v1/user');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'token config-token',
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{'login': 'config-user'}));
        await request.response.close();
      });

      await File(p.join(teaConfigDir.path, 'config.yml')).writeAsString('''
logins:
  - name: company
    url: http://${server.address.host}:${server.port}
    token: config-token
    default: true
    insecure: true
''');
      AppEnvironment.resetForTest(<String, String>{
        'LOCALAPPDATA': localAppData.path,
      });
      final client = IssueTrackerClient();

      try {
        // When the tracker client resolves the authenticated Gitea login.
        final login = await client.getAuthenticatedLogin(
          provider: IssueTrackerProvider.gitea,
        );

        // Then it calls the Gitea HTTP API using the host and token from that config file.
        expect(login, 'config-user');
      } finally {
        await server.close(force: true);
        await sandbox.delete(recursive: true);
      }
    });

    /// ```gherkin
    /// Scenario: Surface Gitea API error details when issue listing returns an error response
    ///   Given a local Gitea API server whose issue list request returns a Gitea error object
    ///   When the tracker client fetches updated Gitea issues
    ///   Then it throws a format error that includes the repo and API error details
    /// ```
    test(
      'Surface Gitea API error details when issue listing returns an error response',
      () async {
        // Given a local Gitea API server whose issue list request returns a Gitea error object.
        final server = await _startGiteaApiServer((request) async {
          request.response
            ..statusCode = HttpStatus.notFound
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, Object?>{
                'errors': <String>[
                  'user redirect does not exist [name: owner]',
                ],
                'message': 'GetUserByName',
                'url': 'https://gitea.example.test/api/swagger',
              }),
            );
          await request.response.close();
        });
        _configureGiteaTestEnvironment(server);
        final client = IssueTrackerClient();

        try {
          // When the tracker client fetches updated Gitea issues.
          final future = client.fetchUpdatedIssuesForRepos(
            provider: IssueTrackerProvider.gitea,
            trackerProjects: const <String>['owner/sample'],
            since: null,
          );

          // Then it throws a format error that includes the repo and API error details.
          await expectLater(
            future,
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                allOf(
                  contains('GetUserByName'),
                  contains('user redirect does not exist'),
                  contains('404'),
                ),
              ),
            ),
          );
        } finally {
          await server.close(force: true);
        }
      },
    );

    /// ```gherkin
    /// Scenario: Fail fast and log when a Gitea API request exceeds the timeout
    ///   Given a local Gitea API server whose issue list request never returns promptly
    ///   When the tracker client fetches updated Gitea issues with a short timeout
    ///   Then it throws a timeout instead of waiting indefinitely
    ///   And the tracker logger records the timed out request
    /// ```
    test(
      'Fail fast and log when a Gitea API request exceeds the timeout',
      () async {
        // Given a local Gitea API server whose issue list request never returns promptly.
        final server = await _startGiteaApiServer((request) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('[]');
          await request.response.close();
        });
        _configureGiteaTestEnvironment(server);
        final logMessages = <String>[];
        void listener(AppLogRecord record) {
          if (record.loggerName == 'code_work_spawner.issue_tracker') {
            logMessages.add(record.message);
          }
        }

        AppLogger.addListener(listener);
        final client = IssueTrackerClient(
          commandTimeout: const Duration(milliseconds: 200),
        );

        try {
          // When the tracker client fetches updated Gitea issues with a short timeout.
          final future = client.fetchUpdatedIssuesForRepos(
            provider: IssueTrackerProvider.gitea,
            trackerProjects: const <String>['owner/sample'],
            since: null,
          );

          // Then it throws a timeout instead of waiting indefinitely.
          await expectLater(
            future,
            throwsA(
              isA<TimeoutException>().having(
                (error) => error.duration,
                'duration',
                const Duration(milliseconds: 200),
              ),
            ),
          );
        } finally {
          AppLogger.removeListener(listener);
          await server.close(force: true);
        }

        // And the tracker logger records the timed out request.
        expect(
          logMessages,
          contains(
            allOf(
              contains('gitea request timeout'),
              contains('timeout_ms=200'),
              contains('/api/v1/repos/owner/sample/issues'),
            ),
          ),
        );
      },
    );
  });
}

void _configureGiteaTestEnvironment(HttpServer server) {
  _configureGiteaTestEnvironmentFromBaseUrl(
    'http://${server.address.host}:${server.port}',
  );
}

void _configureGiteaTestEnvironmentFromBaseUrl(String baseUrl) {
  AppEnvironment.resetForTest(<String, String>{
    ...Platform.environment,
    'CWS_GITEA_HOST': baseUrl,
    'CWS_GITEA_TOKEN': 'test-token',
    'CWS_GITEA_INSECURE': 'false',
  });
}

Future<HttpServer> _startGiteaApiServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(() async {
    await for (final request in server) {
      await handler(request);
    }
  }());
  return server;
}
