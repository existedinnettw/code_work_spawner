import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeGiteaApiServer {
  FakeGiteaApiServer._({
    required HttpServer server,
    required this.issueListResponsesByRepo,
    required this.issueListResponseSequenceByRepo,
    required this.commentResponsesByRepo,
    required this.postCommentResponsesByRepo,
    required this.viewerLogin,
    required this.token,
  }) : _server = server;

  final HttpServer _server;
  final Map<String, List<Map<String, Object?>>> issueListResponsesByRepo;
  final Map<String, List<List<Map<String, Object?>>>>
  issueListResponseSequenceByRepo;
  final Map<String, Map<int, List<Map<String, Object?>>>>
  commentResponsesByRepo;
  final Map<String, Map<int, Map<String, Object?>>> postCommentResponsesByRepo;
  final String viewerLogin;
  final String token;
  final List<String> requestPaths = <String>[];
  final List<String> postedBodies = <String>[];
  final List<String> reactionBodies = <String>[];
  final List<Map<String, dynamic>> createdWebhooks = <Map<String, dynamic>>[];
  final List<int> deletedWebhookIds = <int>[];
  final Map<String, int> _issueListRequestCounts = <String, int>{};

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  int issueListRequestCount(String repo) => _issueListRequestCounts[repo] ?? 0;

  static Future<FakeGiteaApiServer> start({
    Map<String, List<Map<String, Object?>>> issueListResponsesByRepo =
        const <String, List<Map<String, Object?>>>{},
    Map<String, List<List<Map<String, Object?>>>>
        issueListResponseSequenceByRepo =
        const <String, List<List<Map<String, Object?>>>>{},
    Map<String, Map<int, List<Map<String, Object?>>>> commentResponsesByRepo =
        const <String, Map<int, List<Map<String, Object?>>>>{},
    Map<String, Map<int, Map<String, Object?>>> postCommentResponsesByRepo =
        const <String, Map<int, Map<String, Object?>>>{},
    String viewerLogin = 'tea-octocat',
    String token = 'test-token',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = FakeGiteaApiServer._(
      server: server,
      issueListResponsesByRepo: issueListResponsesByRepo,
      issueListResponseSequenceByRepo: issueListResponseSequenceByRepo,
      commentResponsesByRepo: commentResponsesByRepo,
      postCommentResponsesByRepo: postCommentResponsesByRepo,
      viewerLogin: viewerLogin,
      token: token,
    );
    unawaited(
      server.forEach((request) async {
        await fixture._handleRequest(request);
      }),
    );
    return fixture;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    requestPaths.add(request.uri.toString());
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'token $token') {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    final response = request.response..headers.contentType = ContentType.json;
    if (request.method == 'GET' && request.uri.path == '/api/v1/user') {
      response.write(jsonEncode(<String, Object?>{'login': viewerLogin}));
      await response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length >= 6 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'repos') {
      final repo = '${segments[3]}/${segments[4]}';
      if (segments.length == 6 &&
          segments[5] == 'hooks' &&
          request.method == 'POST') {
        final body = await utf8.decodeStream(request);
        createdWebhooks.add(jsonDecode(body) as Map<String, dynamic>);
        response.statusCode = HttpStatus.created;
        response.write(jsonEncode(<String, Object?>{'id': 81}));
        await response.close();
        return;
      }

      if (segments.length == 7 &&
          segments[5] == 'hooks' &&
          request.method == 'DELETE') {
        deletedWebhookIds.add(int.parse(segments[6]));
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }

      if (segments.length == 6 &&
          segments[5] == 'issues' &&
          request.method == 'GET') {
        final requestCount = (_issueListRequestCounts[repo] ?? 0) + 1;
        _issueListRequestCounts[repo] = requestCount;
        final sequence = issueListResponseSequenceByRepo[repo];
        final payload = sequence == null || sequence.isEmpty
            ? issueListResponsesByRepo[repo] ?? const <Map<String, Object?>>[]
            : sequence[(requestCount - 1).clamp(0, sequence.length - 1)];
        response.write(jsonEncode(payload));
        await response.close();
        return;
      }

      if (segments.length == 8 &&
          segments[5] == 'issues' &&
          segments[7] == 'comments') {
        final issueNumber = int.parse(segments[6]);
        if (request.method == 'GET') {
          final payload =
              commentResponsesByRepo[repo]?[issueNumber] ??
              const <Map<String, Object?>>[];
          response.write(jsonEncode(payload));
          await response.close();
          return;
        }

        if (request.method == 'POST') {
          final body = await utf8.decodeStream(request);
          postedBodies.add(body);
          final payload =
              postCommentResponsesByRepo[repo]?[issueNumber] ??
              <String, Object?>{
                'id': 700,
                'body': 'posted',
                'html_url':
                    'https://gitea.example.test/$repo/issues/$issueNumber#issuecomment-700',
              };
          response.statusCode = HttpStatus.created;
          response.write(jsonEncode(payload));
          await response.close();
          return;
        }
      }

      if (segments.length == 9 &&
          segments[5] == 'issues' &&
          segments[6] == 'comments' &&
          segments[8] == 'reactions' &&
          request.method == 'POST') {
        final body = await utf8.decodeStream(request);
        reactionBodies.add(body);
        response.statusCode = HttpStatus.created;
        response.write(
          jsonEncode(<String, Object?>{'id': 990, 'content': 'eyes'}),
        );
        await response.close();
        return;
      }
    }

    response.statusCode = HttpStatus.notFound;
    response.write(jsonEncode(<String, Object?>{'message': 'not found'}));
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}
