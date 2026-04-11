import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/app_environment.dart';
import '../config/app_logger.dart';
import '../config/config_schema.dart';
import '../core/process_launcher.dart';
import 'models.dart';

class IssueTrackerClient {
  IssueTrackerClient({
    this.ghCommand = 'gh',
    this.glabCommand = 'glab',
    this.teaCommand = 'tea',
    this.opCommand = 'op',
    Duration? commandTimeout,
    AppLogger? logger,
    ExternalCommandExecutor? commandExecutor,
  }) : commandTimeout = commandTimeout ?? const Duration(seconds: 15),
       _logger = logger ?? AppLogger('code_work_spawner.issue_tracker'),
       _commandExecutor =
           commandExecutor ?? const DefaultExternalCommandExecutor();

  final String ghCommand;
  final String glabCommand;
  final String teaCommand;
  final String opCommand;
  final Duration commandTimeout;
  final AppLogger _logger;
  final ExternalCommandExecutor _commandExecutor;
  final Map<IssueTrackerProvider, Future<String?>> _authenticatedLoginFutures =
      <IssueTrackerProvider, Future<String?>>{};
  final Map<String, Future<_OpenProjectProjectRef>> _openProjectProjectFutures =
      <String, Future<_OpenProjectProjectRef>>{};
  static const int _pageSize = 100;

  Future<List<GitHubIssueSummary>> fetchUpdatedIssuesForRepos({
    required IssueTrackerProvider provider,
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) {
    return switch (provider) {
      IssueTrackerProvider.github => _fetchUpdatedGitHubIssues(
        trackerProjects: trackerProjects,
        since: since,
      ),
      IssueTrackerProvider.gitlab => _fetchUpdatedGitLabIssues(
        trackerProjects: trackerProjects,
        since: since,
      ),
      IssueTrackerProvider.gitea => _fetchUpdatedGiteaIssues(
        trackerProjects: trackerProjects,
        since: since,
      ),
      IssueTrackerProvider.openproject => _fetchUpdatedOpenProjectIssues(
        trackerProjects: trackerProjects,
        since: since,
      ),
    };
  }

  Future<IssueThread> fetchThread({
    required IssueTrackerProvider provider,
    required String trackerProject,
    required GitHubIssueSummary issue,
  }) async {
    final openProjectConfig = provider == IssueTrackerProvider.openproject
        ? await _loadOpenProjectConfig()
        : null;
    final commentJson = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson([
        'api',
        '-X',
        'GET',
        _buildApiPath(
          issue.requiredRepoSlug,
          ['issues', '${issue.number}', 'comments'],
          {'per_page': '100'},
        ),
      ]),
      IssueTrackerProvider.gitlab => await _runGlabJson([
        'api',
        '-X',
        'GET',
        _buildGitLabApiPath(
          trackerProject,
          ['issues', '${issue.number}', 'notes'],
          {'per_page': '100'},
        ),
      ]),
      IssueTrackerProvider.gitea => await _runGiteaJson(
        method: 'GET',
        path: _buildApiPath(
          issue.requiredRepoSlug,
          ['issues', '${issue.number}', 'comments'],
          {'limit': '100'},
        ),
      ),
      IssueTrackerProvider.openproject => await _runOpenProjectJson(
        method: 'GET',
        path: '/api/v3/work_packages/${issue.number}/activities',
      ),
    };
    final comments = provider == IssueTrackerProvider.openproject
        ? ((((commentJson as Map<String, dynamic>)['_embedded']
                          as Map<String, dynamic>?)?['elements']
                      as List<dynamic>?) ??
                  const <dynamic>[])
              .cast<Map<String, dynamic>>()
        : (commentJson as List<dynamic>).cast<Map<String, dynamic>>();

    return IssueThread(
      issue: issue,
      comments: comments
          .map(switch (provider) {
            IssueTrackerProvider.openproject =>
              (json) => GitHubIssueComment.fromOpenProjectJson(
                json,
                openProjectConfig!.host,
              ),
            IssueTrackerProvider.gitlab =>
              (json) => GitHubIssueComment.fromGitLabJson(json, issue.url),
            _ => GitHubIssueComment.fromJson,
          })
          .toList(growable: false),
    );
  }

  Future<PostedComment> createIssueComment({
    required IssueTrackerProvider provider,
    required String trackerProject,
    required int issueNumber,
    required String body,
  }) async {
    final openProjectConfig = provider == IssueTrackerProvider.openproject
        ? await _loadOpenProjectConfig()
        : null;
    final json = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson([
        'api',
        '-X',
        'POST',
        _buildApiPath(parseRepositorySlug(trackerProject), [
          'issues',
          '$issueNumber',
          'comments',
        ]),
        '-f',
        'body=$body',
      ]),
      IssueTrackerProvider.gitlab => await _runGlabJson([
        'api',
        '-X',
        'POST',
        _buildGitLabApiPath(trackerProject, [
          'issues',
          '$issueNumber',
          'notes',
        ]),
        '-f',
        'body=$body',
      ]),
      IssueTrackerProvider.gitea => await _runGiteaJson(
        method: 'POST',
        path: _buildApiPath(parseRepositorySlug(trackerProject), [
          'issues',
          '$issueNumber',
          'comments',
        ]),
        body: <String, Object?>{'body': body},
      ),
      IssueTrackerProvider.openproject => await _runOpenProjectJson(
        method: 'POST',
        path: '/api/v3/work_packages/$issueNumber/activities',
        body: <String, Object?>{
          'comment': <String, Object?>{'raw': body},
        },
      ),
    };

    final map = json as Map<String, dynamic>;
    return PostedComment(
      id: readIntField(map, 'id'),
      url: switch (provider) {
        IssueTrackerProvider.openproject => resolveTrackerUrl(
          readUrlField(map),
          openProjectConfig!.host,
        ),
        IssueTrackerProvider.gitlab => GitHubIssueComment.buildGitLabNoteUrl(
          issueUrl: '',
          json: map,
        ),
        _ => readUrlField(map),
      },
      body: map['body'] as String? ?? readOpenProjectCommentBody(map) ?? body,
    );
  }

  Future<bool> createNoReplyReaction({
    required IssueTrackerProvider provider,
    required String trackerProject,
    required int issueNumber,
    required int commentId,
  }) async {
    switch (provider) {
      case IssueTrackerProvider.github:
        await _runGhJson([
          'api',
          '-X',
          'POST',
          _buildApiPath(parseRepositorySlug(trackerProject), [
            'issues',
            'comments',
            '$commentId',
            'reactions',
          ]),
          '-H',
          'Accept: application/vnd.github+json',
          '-f',
          'content=eyes',
        ]);
        return true;
      case IssueTrackerProvider.gitea:
        try {
          await _runGiteaJson(
            method: 'POST',
            path: _buildApiPath(parseRepositorySlug(trackerProject), [
              'issues',
              'comments',
              '$commentId',
              'reactions',
            ]),
            body: <String, Object?>{'content': 'eyes'},
          );
          return true;
        } on FormatException catch (error) {
          final message = error.message.toLowerCase();
          if (_isGiteaExistingReactionError(message)) {
            return true;
          }
          if (_isGiteaReactionUnsupported(message)) {
            return false;
          }
          rethrow;
        }
      case IssueTrackerProvider.gitlab:
        try {
          await _runGlabJson([
            'api',
            '-X',
            'POST',
            _buildGitLabApiPath(trackerProject, [
              'issues',
              '$issueNumber',
              'notes',
              '$commentId',
              'award_emoji',
            ]),
            '-f',
            'name=eyes',
          ]);
          return true;
        } on ProcessException catch (error) {
          if (_isGitLabReactionUnsupported(
            error.message.toLowerCase(),
            error.errorCode,
          )) {
            return false;
          }
          rethrow;
        }
      case IssueTrackerProvider.openproject:
        try {
          await _runOpenProjectJson(
            method: 'PATCH',
            path: '/api/v3/activities/$commentId/emoji_reactions',
            body: <String, Object?>{'reaction': 'eyes'},
          );
          return true;
        } on HttpException catch (error) {
          if (_isOpenProjectEmojiUnsupported(error.message.toLowerCase())) {
            return false;
          }
          rethrow;
        }
    }
  }

  bool _isGiteaExistingReactionError(String message) {
    return message.contains('already') && message.contains('reaction');
  }

  bool _isGitLabReactionUnsupported(String message, int exitCode) {
    if (exitCode == 404 || exitCode == 405) {
      return true;
    }
    return message.contains('404') ||
        message.contains('405') ||
        message.contains('not found') ||
        message.contains('method not allowed') ||
        message.contains('award_emoji') && message.contains('unexpected glab');
  }

  bool _isGiteaReactionUnsupported(String message) {
    return message.contains('(404') ||
        message.contains('not found') ||
        message.contains('(405') ||
        message.contains('method not allowed');
  }

  bool _isOpenProjectEmojiUnsupported(String message) {
    return message.contains('(404') ||
        message.contains('not found') ||
        message.contains('(405') ||
        message.contains('method not allowed');
  }

  Future<String?> getAuthenticatedLogin({
    required IssueTrackerProvider provider,
  }) {
    return _authenticatedLoginFutures.putIfAbsent(
      provider,
      () => _loadAuthenticatedLogin(provider: provider),
    );
  }

  String trackerCliName(IssueTrackerProvider provider) {
    return switch (provider) {
      IssueTrackerProvider.github => 'gh',
      IssueTrackerProvider.gitlab => 'glab',
      IssueTrackerProvider.gitea => 'gitea',
      IssueTrackerProvider.openproject => opCommand,
    };
  }

  Future<int> createGiteaIssueWebhook({
    required RepositorySlug repo,
    required String url,
  }) async {
    _logger.debug(
      'gitea webhook create repo=${repo.fullName} url=$url events=issues,issue_comment',
    );
    final json = await _runGiteaJson(
      method: 'POST',
      path: _buildApiPath(repo, ['hooks']),
      body: <String, Object?>{
        'type': 'gitea',
        'config': <String, Object?>{'url': url, 'content_type': 'json'},
        'events': <String>['issues', 'issue_comment'],
        'active': true,
      },
    );
    if (json is Map<String, dynamic>) {
      return readIntField(json, 'id');
    }

    throw FormatException(
      'Gitea API webhook create returned an unexpected response for repo '
      '${repo.fullName}.',
    );
  }

  Future<int> createGitHubIssueWebhook({
    required RepositorySlug repo,
    required String url,
  }) async {
    _logger.debug(
      'github webhook create repo=${repo.fullName} url=$url events=issues,issue_comment',
    );
    final json = await _runGhJson([
      'api',
      '-X',
      'POST',
      _buildApiPath(repo, ['hooks']),
      '-f',
      'name=web',
      '-F',
      'active=true',
      '-f',
      'events[]=issues',
      '-f',
      'events[]=issue_comment',
      '-f',
      'config[url]=$url',
      '-f',
      'config[content_type]=json',
    ]);
    if (json is! Map<String, dynamic>) {
      throw const FormatException(
        'gh api webhook create returned an unexpected response.',
      );
    }
    return readIntField(json, 'id');
  }

  Future<int> createGitLabIssueWebhook({
    required String trackerProject,
    required String url,
  }) async {
    _logger.debug(
      'gitlab webhook create repo=$trackerProject url=$url events=issues,note',
    );
    final json = await _runGlabJson([
      'api',
      '-X',
      'POST',
      _buildGitLabApiPath(trackerProject, ['hooks']),
      '-f',
      'url=$url',
      '-f',
      'issues_events=true',
      '-f',
      'note_events=true',
      '-f',
      'push_events=false',
    ]);
    if (json is! Map<String, dynamic>) {
      throw const FormatException(
        'glab api webhook create returned an unexpected response.',
      );
    }
    return readIntField(json, 'id');
  }

  Future<void> deleteGitHubWebhook({
    required RepositorySlug repo,
    required int webhookId,
  }) async {
    _logger.debug(
      'github webhook delete repo=${repo.fullName} webhook_id=$webhookId',
    );
    await _runGhJson([
      'api',
      '-X',
      'DELETE',
      _buildApiPath(repo, ['hooks', '$webhookId']),
    ]);
  }

  Future<void> deleteGiteaWebhook({
    required RepositorySlug repo,
    required int webhookId,
  }) async {
    _logger.debug(
      'gitea webhook delete repo=${repo.fullName} webhook_id=$webhookId',
    );
    await _runGiteaJson(
      method: 'DELETE',
      path: _buildApiPath(repo, ['hooks', '$webhookId']),
    );
  }

  Future<void> deleteGitLabWebhook({
    required String trackerProject,
    required int webhookId,
  }) async {
    _logger.debug(
      'gitlab webhook delete repo=$trackerProject webhook_id=$webhookId',
    );
    await _runGlabJson([
      'api',
      '-X',
      'DELETE',
      _buildGitLabApiPath(trackerProject, ['hooks', '$webhookId']),
    ]);
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedGitHubIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final repoList = trackerProjects
        .map(parseRepositorySlug)
        .toList(growable: false);
    if (repoList.isEmpty) {
      return const <GitHubIssueSummary>[];
    }

    final queryParts = <String>[
      for (final repo in repoList) 'repo:${repo.fullName}',
      'is:issue',
      'state:open',
      if (since != null) 'updated:>=${since.toUtc().toIso8601String()}',
    ];

    final issues = <GitHubIssueSummary>[];
    for (var page = 1; true; page += 1) {
      _traceRequest(
        provider: IssueTrackerProvider.github,
        requestKind: 'search-issues',
        trackerProject: repoList.map((repo) => repo.fullName).join(','),
        page: page,
        since: since,
        requestPath: 'search/issues',
      );
      final json = await _runGhJson([
        'api',
        '-X',
        'GET',
        'search/issues',
        '-f',
        'q=${queryParts.join(' ')}',
        '-f',
        'sort=updated',
        '-f',
        'order=asc',
        '-f',
        'per_page=$_pageSize',
        '-f',
        'page=$page',
      ]);
      final items =
          ((json as Map<String, dynamic>)['items'] as List<dynamic>? ??
                  const [])
              .cast<Map<String, dynamic>>();
      issues.addAll(
        items
            .where((item) => !item.containsKey('pull_request'))
            .map(GitHubIssueSummary.fromSearchJson),
      );
      if (items.length < _pageSize) {
        break;
      }
    }

    return issues;
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedGitLabIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final issues = <GitHubIssueSummary>[];

    for (final trackerProject in trackerProjects) {
      for (var page = 1; true; page += 1) {
        final query = <String, String>{
          'state': 'opened',
          'order_by': 'updated_at',
          'sort': 'asc',
          'per_page': '$_pageSize',
          'page': '$page',
          if (since != null) 'updated_after': since.toUtc().toIso8601String(),
        };
        _traceRequest(
          provider: IssueTrackerProvider.gitlab,
          requestKind: 'list-issues',
          trackerProject: trackerProject,
          page: page,
          since: since,
          requestPath: _buildGitLabApiPath(trackerProject, ['issues'], query),
        );
        final json = await _runGlabJson([
          'api',
          '-X',
          'GET',
          _buildGitLabApiPath(trackerProject, ['issues'], query),
        ]);
        final items = (json as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
        issues.addAll(
          items.map(
            (item) => GitHubIssueSummary.fromGitLabJson(trackerProject, item),
          ),
        );
        if (items.length < _pageSize) {
          break;
        }
      }
    }

    issues.sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
    return issues;
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedGiteaIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final issues = <GitHubIssueSummary>[];

    for (final repo in trackerProjects.map(parseRepositorySlug)) {
      for (var page = 1; true; page += 1) {
        final query = <String, String>{
          'state': 'open',
          'limit': '$_pageSize',
          'page': '$page',
          if (since != null) 'since': since.toUtc().toIso8601String(),
        };
        final requestPath = _buildApiPath(repo, ['issues'], query);
        _traceRequest(
          provider: IssueTrackerProvider.gitea,
          requestKind: 'list-issues',
          trackerProject: repo.fullName,
          page: page,
          since: since,
          requestPath: requestPath,
        );
        final json = await _runGiteaJson(method: 'GET', path: requestPath);
        if (json is Map<String, dynamic>) {
          throw FormatException(
            'Gitea API returned an error while listing issues for '
            '${repo.fullName}: ${_describeJsonObject(json)}',
          );
        }
        if (json != null && json is! List<dynamic>) {
          throw FormatException(
            'Gitea API returned ${json.runtimeType} while listing issues '
            'for ${repo.fullName}; expected a JSON array.',
          );
        }
        final items = (json as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
        issues.addAll(
          items
              .where((item) => item['pull_request'] == null)
              .map((item) => GitHubIssueSummary.fromRepositoryJson(repo, item)),
        );
        if (items.length < _pageSize) {
          break;
        }
      }
    }

    issues.sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
    return issues;
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedOpenProjectIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final issues = <GitHubIssueSummary>[];

    for (final trackerProject in trackerProjects) {
      final project = await _resolveOpenProjectProjectRef(trackerProject);
      final config = await _loadOpenProjectConfig();
      final json = await _runOpenProjectJson(
        method: 'GET',
        path: '/api/v3/projects/${project.id}/work_packages',
        queryParameters: <String, String>{
          'pageSize': '-1',
          'filters': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'status': <String, Object?>{
                'operator': 'o',
                'values': const <String>[],
              },
            },
          ]),
        },
      );
      final embedded =
          (json as Map<String, dynamic>)['_embedded'] as Map<String, dynamic>?;
      final items =
          (embedded?['elements'] as List<dynamic>? ?? const <dynamic>[])
              .cast<Map<String, dynamic>>();
      issues.addAll(
        items
            .map(
              (item) => GitHubIssueSummary.fromOpenProjectJson(
                trackerProject,
                item,
                config.host,
              ),
            )
            .where((issue) => since == null || issue.updatedAt.isAfter(since)),
      );
    }

    issues.sort((left, right) => left.updatedAt.compareTo(right.updatedAt));
    return issues;
  }

  Future<String?> _loadAuthenticatedLogin({
    required IssueTrackerProvider provider,
  }) async {
    final json = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson(['api', 'user']),
      IssueTrackerProvider.gitlab => await _runGlabJson(['api', 'user']),
      IssueTrackerProvider.gitea => await _runGiteaJson(
        method: 'GET',
        path: '/user',
      ),
      IssueTrackerProvider.openproject => await _runOpenProjectJson(
        method: 'GET',
        path: '/api/v3/users/me',
      ),
    };
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final login =
        json['login']?.toString().trim() ??
        json['username']?.toString().trim() ??
        json['name']?.toString().trim() ??
        json['firstName']?.toString().trim();
    return login == null || login.isEmpty ? null : login;
  }

  Future<Object?> _runGhJson(List<String> arguments) {
    return _runJson(ghCommand, arguments);
  }

  Future<Object?> _runGlabJson(List<String> arguments) {
    return _runJson(glabCommand, arguments);
  }

  Future<Object?> _runGiteaJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
  }) async {
    final config = await _loadGiteaConfig();
    final client = HttpClient();
    if (config.insecure) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    final uri = _buildGiteaUri(
      config.host,
      path,
      queryParameters: queryParameters,
    );
    final stopwatch = Stopwatch()..start();
    _logger.debug(
      'gitea request start timeout_ms=${commandTimeout.inMilliseconds} '
      'method=$method uri=$uri',
    );

    try {
      final result =
          await (() async {
            final request = await client.openUrl(method, uri);
            request.headers.set(HttpHeaders.acceptHeader, 'application/json');
            request.headers.set(
              HttpHeaders.authorizationHeader,
              'token ${config.token}',
            );
            if (body != null) {
              request.headers.set(
                HttpHeaders.contentTypeHeader,
                'application/json',
              );
              request.write(jsonEncode(body));
            }
            final response = await request.close();
            final responseBody = await utf8.decodeStream(response);
            return (response: response, body: responseBody);
          })().timeout(
            commandTimeout,
            onTimeout: () {
              throw TimeoutException(
                'Gitea API request timed out after ${commandTimeout.inMilliseconds}ms.',
                commandTimeout,
              );
            },
          );

      stopwatch.stop();
      _logger.debug(
        'gitea request finished duration_ms=${stopwatch.elapsedMilliseconds} '
        'status_code=${result.response.statusCode} method=$method uri=$uri',
      );
      final trimmed = result.body.trim();
      final parsedJson = trimmed.isEmpty ? null : jsonDecode(trimmed);
      if (result.response.statusCode < 200 ||
          result.response.statusCode >= 300) {
        if (parsedJson is Map<String, dynamic>) {
          throw FormatException(
            'Gitea API request failed '
            '(${result.response.statusCode} ${result.response.reasonPhrase}): '
            '${_describeJsonObject(parsedJson)}',
          );
        }
        throw HttpException(
          'Gitea API request failed '
          '(${result.response.statusCode} ${result.response.reasonPhrase}): '
          '${_summarizeOutput(result.body)}',
          uri: uri,
        );
      }
      return parsedJson;
    } on TimeoutException catch (error, stackTrace) {
      stopwatch.stop();
      _logger.error(
        'gitea request timeout duration_ms=${stopwatch.elapsedMilliseconds} '
        'timeout_ms=${commandTimeout.inMilliseconds} method=$method uri=$uri',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logger.error(
        'gitea request failed duration_ms=${stopwatch.elapsedMilliseconds} '
        'method=$method uri=$uri',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _runOpenProjectJson({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
  }) async {
    final config = await _loadOpenProjectConfig();
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        _buildOpenProjectUri(
          config.host,
          path,
          queryParameters: queryParameters,
        ),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('apikey:${config.token}'))}',
      );
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'OpenProject API request failed '
          '(${response.statusCode} ${response.reasonPhrase}): $responseBody',
          uri: request.uri,
        );
      }

      final trimmed = responseBody.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      return jsonDecode(trimmed);
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _runJson(String command, List<String> arguments) async {
    final result = await _runCommand(command, arguments);
    final stdoutText = result.stdout.toString().trim();
    if (stdoutText.isEmpty) {
      _traceCommandResult(
        command: command,
        arguments: arguments,
        state: 'empty-stdout',
      );
      return null;
    }

    try {
      final json = jsonDecode(stdoutText);
      _traceCommandResult(
        command: command,
        arguments: arguments,
        state: 'json-parsed',
        detail: _describeJsonPayload(json),
      );
      return json;
    } on FormatException catch (error) {
      _traceCommandResult(
        command: command,
        arguments: arguments,
        state: 'json-parse-failed',
        detail:
            '${error.message} stdout=${_summarizeOutput(stdoutText, maxLength: 120)}',
      );
      throw FormatException(
        'Failed to parse JSON from `$command ${arguments.join(' ')}`: '
        '${error.message}. stdout=${_summarizeOutput(stdoutText)}',
      );
    }
  }

  Future<ProcessResult> _runCommand(
    String command,
    List<String> arguments,
  ) async {
    final renderedCommand = _renderCommand(command, arguments);
    final stopwatch = Stopwatch()..start();
    _logger.debug(
      'command start timeout_ms=${commandTimeout.inMilliseconds} command=$renderedCommand',
    );
    late final ProcessResult result;
    try {
      result = await _commandExecutor.run(
        command,
        arguments,
        timeout: commandTimeout,
      );
    } on TimeoutException catch (error, stackTrace) {
      stopwatch.stop();
      _logger.error(
        'command timeout duration_ms=${stopwatch.elapsedMilliseconds} '
        'timeout_ms=${commandTimeout.inMilliseconds} command=$renderedCommand',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logger.error(
        'command failed duration_ms=${stopwatch.elapsedMilliseconds} command=$renderedCommand',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    stopwatch.stop();
    _logger.debug(
      'command finished duration_ms=${stopwatch.elapsedMilliseconds} '
      'exit_code=${result.exitCode} command=$renderedCommand',
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        command,
        arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    return result;
  }

  String _renderCommand(String command, List<String> arguments) {
    final parts = <String>[command, ...arguments];
    return parts.map(_shellQuote).join(' ');
  }

  String _shellQuote(String value) {
    if (value.isEmpty) {
      return '""';
    }
    if (!value.contains(RegExp(r'[\s"]'))) {
      return value;
    }
    return '"${value.replaceAll('"', r'\"')}"';
  }

  String _describeJsonObject(Map<String, dynamic> json) {
    final message = json['message']?.toString().trim();
    final errors = (json['errors'] as List<dynamic>?)
        ?.map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    final url = json['url']?.toString().trim();
    final parts = <String>[
      if (message != null && message.isNotEmpty) 'message=$message',
      if (errors != null && errors.isNotEmpty) 'errors=${errors.join('; ')}',
      if (url != null && url.isNotEmpty) 'url=$url',
    ];
    if (parts.isEmpty) {
      return _summarizeOutput(jsonEncode(json));
    }
    return parts.join(' ');
  }

  String _summarizeOutput(String text, {int maxLength = 240}) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) {
      return singleLine;
    }
    return '${singleLine.substring(0, maxLength)}...';
  }

  String _describeJsonPayload(Object? json) {
    return switch (json) {
      List<dynamic> list => 'type=list length=${list.length}',
      Map<String, dynamic> map =>
        'type=object keys=${map.keys.take(6).join(",")}',
      null => 'type=null',
      _ => 'type=${json.runtimeType}',
    };
  }

  void _traceRequest({
    required IssueTrackerProvider provider,
    required String requestKind,
    required String trackerProject,
    required int page,
    required DateTime? since,
    required String requestPath,
  }) {
    _logger.debug(
      'trace request provider=${provider.name} kind=$requestKind '
      'tracker_project=$trackerProject page=$page '
      'since=${since?.toUtc().toIso8601String() ?? "(none)"} '
      'path=$requestPath',
    );
  }

  void _traceCommandResult({
    required String command,
    required List<String> arguments,
    required String state,
    String? detail,
  }) {
    final parts = <String>[
      'trace command_result state=$state',
      'command=$command',
      'args=${arguments.map(_shellQuote).join(" ")}',
      if (detail != null && detail.isNotEmpty) 'detail=$detail',
    ];
    _logger.debug(parts.join(' '));
  }

  String _buildApiPath(
    RepositorySlug repo,
    List<String> tailSegments, [
    Map<String, String> query = const <String, String>{},
  ]) {
    return Uri(
      pathSegments: ['repos', repo.owner, repo.name, ...tailSegments],
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  String _buildGitLabApiPath(
    String projectPath,
    List<String> tailSegments, [
    Map<String, String> query = const <String, String>{},
  ]) {
    final path =
        'projects/${Uri.encodeComponent(projectPath)}/${tailSegments.join('/')}';
    if (query.isEmpty) {
      return path;
    }
    return Uri(path: path, queryParameters: query).toString();
  }

  Uri _buildOpenProjectUri(
    Uri host,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return host.replace(
      path: p.posix.normalize(
        '${host.path.endsWith('/') ? host.path.substring(0, host.path.length - 1) : host.path}$path',
      ),
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }

  Uri _buildGiteaUri(
    Uri host,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final relativeUri = Uri.parse(path);
    final normalizedPath = relativeUri.path.startsWith('/')
        ? relativeUri.path
        : '/${relativeUri.path}';
    final effectiveQueryParameters =
        queryParameters ??
        (relativeUri.hasQuery ? relativeUri.queryParameters : null);
    return host.replace(
      path: p.posix.normalize(
        '${host.path.endsWith('/') ? host.path.substring(0, host.path.length - 1) : host.path}/api/v1$normalizedPath',
      ),
      queryParameters:
          effectiveQueryParameters == null || effectiveQueryParameters.isEmpty
          ? null
          : effectiveQueryParameters,
    );
  }

  Future<_GiteaConfig> _loadGiteaConfig() async {
    final environment = AppEnvironment.variables;
    final host =
        environment['CWS_GITEA_HOST']?.trim() ??
        environment['GITEA_HOST']?.trim();
    final token =
        environment['CWS_GITEA_TOKEN']?.trim() ??
        environment['GITEA_TOKEN']?.trim();
    final insecureValue =
        environment['CWS_GITEA_INSECURE']?.trim() ??
        environment['GITEA_INSECURE']?.trim();
    if (host != null && host.isNotEmpty && token != null && token.isNotEmpty) {
      _logger.debug(
        'gitea config source=env host=$host insecure=${_parseBooleanFlag(insecureValue)}',
      );
      return _GiteaConfig(
        host: Uri.parse(host),
        token: token,
        insecure: _parseBooleanFlag(insecureValue),
      );
    }

    final loginName =
        environment['CWS_GITEA_LOGIN']?.trim() ??
        environment['GITEA_LOGIN']?.trim() ??
        environment['TEA_LOGIN']?.trim();
    final configPath = _teaConfigPath(environment);
    _logger.debug(
      'gitea config source=tea config_path=$configPath '
      'requested_login=${loginName ?? "(default)"}',
    );
    final file = File(configPath);
    if (!await file.exists()) {
      throw const FileSystemException(
        'Gitea config not found. Set CWS_GITEA_HOST/CWS_GITEA_TOKEN or configure tea first.',
      );
    }

    final document = loadYaml(await file.readAsString());
    final logins =
        (document is YamlMap ? document['logins'] : null) as YamlList?;
    if (logins == null || logins.isEmpty) {
      throw FileSystemException(
        'No tea logins found in Gitea config at $configPath.',
      );
    }

    final loginMaps = logins
        .whereType<YamlMap>()
        .map((entry) => Map<String, Object?>.from(entry))
        .toList(growable: false);
    final selectedLogin = _selectTeaLogin(loginMaps, loginName);
    final loginHost = selectedLogin['url']?.toString().trim();
    final loginToken = selectedLogin['token']?.toString().trim();
    if (loginHost == null ||
        loginHost.isEmpty ||
        loginToken == null ||
        loginToken.isEmpty) {
      throw FileSystemException(
        'Selected tea login in $configPath is missing url or token.',
      );
    }

    _logger.debug(
      'gitea config source=tea host=$loginHost '
      'login=${selectedLogin["name"]?.toString().trim() ?? "(unnamed)"} '
      'insecure=${_parseBooleanFlag(selectedLogin["insecure"]?.toString())}',
    );
    return _GiteaConfig(
      host: Uri.parse(loginHost),
      token: loginToken,
      insecure: _parseBooleanFlag(selectedLogin['insecure']?.toString()),
    );
  }

  Map<String, Object?> _selectTeaLogin(
    List<Map<String, Object?>> logins,
    String? requestedLoginName,
  ) {
    if (requestedLoginName != null && requestedLoginName.isNotEmpty) {
      final matchedLogin = logins
          .where((login) {
            final name = login['name']?.toString().trim();
            return name != null &&
                name.toLowerCase() == requestedLoginName.toLowerCase();
          })
          .toList(growable: false);
      if (matchedLogin.length == 1) {
        return matchedLogin.single;
      }
      throw FileSystemException(
        'tea login "$requestedLoginName" was not found or was ambiguous.',
      );
    }

    final defaultLogins = logins
        .where((login) {
          final value = login['default'];
          return value == true || value?.toString().toLowerCase() == 'true';
        })
        .toList(growable: false);
    if (defaultLogins.length == 1) {
      return defaultLogins.single;
    }
    if (logins.length == 1) {
      return logins.single;
    }
    throw const FileSystemException(
      'Multiple tea logins found. Set CWS_GITEA_LOGIN, GITEA_LOGIN, or TEA_LOGIN to choose one.',
    );
  }

  String _teaConfigPath(Map<String, String> environment) {
    final explicitPath =
        environment['CWS_GITEA_CONFIG_PATH']?.trim() ??
        environment['TEA_CONFIG_PATH']?.trim();
    if (explicitPath != null && explicitPath.isNotEmpty) {
      return explicitPath;
    }

    final candidates = <String>[];
    final localAppData = environment['LOCALAPPDATA']?.trim();
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add(p.join(localAppData, 'tea', 'config.yml'));
    }
    final xdgConfigHome = environment['XDG_CONFIG_HOME']?.trim();
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      candidates.add(p.join(xdgConfigHome, 'tea', 'config.yml'));
    }
    final userProfile = environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      candidates.add(
        p.join(userProfile, 'AppData', 'Local', 'tea', 'config.yml'),
      );
      candidates.add(p.join(userProfile, '.tea', 'tea.yml'));
    }
    final home = environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      candidates.add(p.join(home, '.config', 'tea', 'config.yml'));
      candidates.add(p.join(home, '.tea', 'tea.yml'));
    }
    if (candidates.isEmpty) {
      throw const FileSystemException(
        'HOME is not set and LOCALAPPDATA/XDG_CONFIG_HOME/USERPROFILE are unset. Cannot locate tea config.',
      );
    }

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return candidates.first;
  }

  bool _parseBooleanFlag(String? value) {
    if (value == null) {
      return false;
    }
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
    }
    return false;
  }

  Future<_OpenProjectConfig> _loadOpenProjectConfig() async {
    final environment = AppEnvironment.variables;
    final host = environment['OP_CLI_HOST']?.trim();
    final token = environment['OP_CLI_TOKEN']?.trim();
    if (host != null && host.isNotEmpty && token != null && token.isNotEmpty) {
      return _OpenProjectConfig(host: Uri.parse(host), token: token);
    }

    final configPath = _openProjectConfigPath(environment);
    final file = File(configPath);
    if (!await file.exists()) {
      throw const FileSystemException(
        'OpenProject config not found. Set OP_CLI_HOST and OP_CLI_TOKEN or run `op login` first.',
      );
    }

    final parts = (await file.readAsString()).trim().split(RegExp(r'\s+'));
    if (parts.length != 2) {
      throw FileSystemException(
        'Invalid OpenProject config file at $configPath. Run `op login` again.',
      );
    }
    return _OpenProjectConfig(host: Uri.parse(parts[0]), token: parts[1]);
  }

  String _openProjectConfigPath(Map<String, String> environment) {
    final xdgConfigHome = environment['XDG_CONFIG_HOME']?.trim();
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      return p.join(xdgConfigHome, 'openproject', 'config');
    }
    final home = environment['HOME']?.trim();
    if (home == null || home.isEmpty) {
      throw const FileSystemException(
        'HOME is not set and XDG_CONFIG_HOME is unset. Cannot locate OpenProject config.',
      );
    }
    return p.join(home, '.config', 'openproject', 'config');
  }

  Future<_OpenProjectProjectRef> _resolveOpenProjectProjectRef(
    String projectRef,
  ) {
    return _openProjectProjectFutures.putIfAbsent(
      projectRef,
      () => _loadOpenProjectProjectRef(projectRef),
    );
  }

  Future<_OpenProjectProjectRef> _loadOpenProjectProjectRef(
    String projectRef,
  ) async {
    final projectId = int.tryParse(projectRef);
    if (projectId != null && projectId > 0) {
      return _OpenProjectProjectRef(id: projectId, name: projectRef);
    }

    final json = await _runOpenProjectJson(
      method: 'GET',
      path: '/api/v3/projects',
      queryParameters: <String, String>{
        'pageSize': '-1',
        'filters': jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'typeahead': <String, Object?>{
              'operator': '**',
              'values': <String>[projectRef],
            },
          },
        ]),
      },
    );
    final embedded =
        (json as Map<String, dynamic>)['_embedded'] as Map<String, dynamic>?;
    final projects =
        (embedded?['elements'] as List<dynamic>? ?? const <dynamic>[])
            .cast<Map<String, dynamic>>();
    final exactMatches = projects
        .where((project) {
          final name = project['name']?.toString().trim();
          return name != null && name.toLowerCase() == projectRef.toLowerCase();
        })
        .toList(growable: false);

    if (exactMatches.length != 1) {
      throw FormatException(
        'OpenProject project "$projectRef" did not resolve to exactly one project.',
      );
    }

    return _OpenProjectProjectRef(
      id: readIntField(exactMatches.single, 'id'),
      name: exactMatches.single['name']?.toString() ?? projectRef,
    );
  }
}

class _OpenProjectConfig {
  const _OpenProjectConfig({required this.host, required this.token});

  final Uri host;
  final String token;
}

class _GiteaConfig {
  const _GiteaConfig({
    required this.host,
    required this.token,
    required this.insecure,
  });

  final Uri host;
  final String token;
  final bool insecure;
}

class _OpenProjectProjectRef {
  const _OpenProjectProjectRef({required this.id, required this.name});

  final int id;
  final String name;
}
