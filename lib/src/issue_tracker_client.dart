import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:path/path.dart' as p;

import 'app_environment.dart';
import 'process_launcher.dart';

import 'config_schema.dart';

class IssueTrackerClient {
  IssueTrackerClient({
    this.ghCommand = 'gh',
    this.teaCommand = 'tea',
    this.opCommand = 'op',
  });

  final String ghCommand;
  final String teaCommand;
  final String opCommand;
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
      IssueTrackerProvider.gitea => await _runTeaJson([
        'api',
        '-X',
        'GET',
        _buildApiPath(
          issue.requiredRepoSlug,
          ['issues', '${issue.number}', 'comments'],
          {'limit': '100'},
        ),
        '-r',
        issue.requiredRepoSlug.fullName,
      ]),
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
          .map(
            provider == IssueTrackerProvider.openproject
                ? (json) => GitHubIssueComment.fromOpenProjectJson(
                    json,
                    openProjectConfig!.host,
                  )
                : GitHubIssueComment.fromJson,
          )
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
        _buildApiPath(_parseRepositorySlug(trackerProject), [
          'issues',
          '$issueNumber',
          'comments',
        ]),
        '-f',
        'body=$body',
      ]),
      IssueTrackerProvider.gitea => await _runTeaJson([
        'api',
        '-X',
        'POST',
        _buildApiPath(_parseRepositorySlug(trackerProject), [
          'issues',
          '$issueNumber',
          'comments',
        ]),
        '-f',
        'body=$body',
        '-r',
        trackerProject,
      ]),
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
      id: _readInt(map, 'id'),
      url: provider == IssueTrackerProvider.openproject
          ? _resolveUrl(_readUrl(map), openProjectConfig!.host)
          : _readUrl(map),
      body: map['body'] as String? ?? _readOpenProjectCommentBody(map) ?? body,
    );
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
      IssueTrackerProvider.gitea => 'tea',
      IssueTrackerProvider.openproject => opCommand,
    };
  }

  Future<int> createGiteaIssueWebhook({
    required RepositorySlug repo,
    required String url,
  }) async {
    final json = await _runTeaJson([
      'webhooks',
      'create',
      '--type',
      'gitea',
      '--events',
      'issues,issue_comment',
      '--active',
      '-o',
      'json',
      '-r',
      repo.fullName,
      url,
    ]);
    if (json is! Map<String, dynamic>) {
      throw const FormatException(
        'tea webhooks create returned an unexpected response.',
      );
    }
    return _readInt(json, 'id');
  }

  Future<int> createGitHubIssueWebhook({
    required RepositorySlug repo,
    required String url,
  }) async {
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
    return _readInt(json, 'id');
  }

  Future<void> deleteGitHubWebhook({
    required RepositorySlug repo,
    required int webhookId,
  }) async {
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
    await _runTeaJson([
      'webhooks',
      'delete',
      '--confirm',
      '-r',
      repo.fullName,
      '$webhookId',
    ]);
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedGitHubIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final repoList = trackerProjects
        .map(_parseRepositorySlug)
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

  Future<List<GitHubIssueSummary>> _fetchUpdatedGiteaIssues({
    required Iterable<String> trackerProjects,
    required DateTime? since,
  }) async {
    final issues = <GitHubIssueSummary>[];

    for (final repo in trackerProjects.map(_parseRepositorySlug)) {
      for (var page = 1; true; page += 1) {
        final query = <String, String>{
          'state': 'open',
          'limit': '$_pageSize',
          'page': '$page',
          if (since != null) 'since': since.toUtc().toIso8601String(),
        };
        final json = await _runTeaJson([
          'api',
          '-X',
          'GET',
          _buildApiPath(repo, ['issues'], query),
          '-r',
          repo.fullName,
        ]);
        final items = (json as List<dynamic>? ?? const [])
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
      IssueTrackerProvider.gitea => await _runTeaJson(['api', 'user']),
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
        json['name']?.toString().trim() ??
        json['firstName']?.toString().trim();
    return login == null || login.isEmpty ? null : login;
  }

  Future<Object?> _runGhJson(List<String> arguments) {
    return _runJson(ghCommand, arguments);
  }

  Future<Object?> _runTeaJson(List<String> arguments) {
    return _runJson(teaCommand, arguments);
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
    final result = await runExternalCommand(command, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        command,
        arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    final stdoutText = result.stdout.toString().trim();
    if (stdoutText.isEmpty) {
      return null;
    }
    return jsonDecode(stdoutText);
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
      id: _readInt(exactMatches.single, 'id'),
      name: exactMatches.single['name']?.toString() ?? projectRef,
    );
  }
}

class GitHubIssueSummary {
  GitHubIssueSummary({
    required this.trackerProject,
    required this.repoSlug,
    required this.number,
    required this.title,
    required this.body,
    required this.state,
    required this.url,
    required this.updatedAt,
    required this.userLogin,
    required this.labels,
  });

  final String trackerProject;
  final RepositorySlug? repoSlug;
  final int number;
  final String title;
  final String body;
  final String state;
  final String url;
  final DateTime updatedAt;
  final String userLogin;
  final List<String> labels;

  factory GitHubIssueSummary.fromRepositoryJson(
    RepositorySlug repo,
    Map<String, dynamic> json,
  ) {
    final labelsNode = json['labels'] as List<dynamic>? ?? const [];
    return GitHubIssueSummary(
      trackerProject: repo.fullName,
      repoSlug: repo,
      number: _readInt(json, 'number', fallbackKey: 'index'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: _readUrl(json),
      updatedAt: DateTime.parse(_readString(json, 'updated_at')),
      userLogin: _readLogin(json['user']) ?? _readLogin(json['poster']) ?? '',
      labels: labelsNode
          .map((label) => _readString(label as Map<String, dynamic>, 'name'))
          .toList(growable: false),
    );
  }

  factory GitHubIssueSummary.fromOpenProjectJson(
    String trackerProject,
    Map<String, dynamic> json,
    Uri host,
  ) {
    final embedded = json['_embedded'] as Map<String, dynamic>?;
    final description =
        embedded?['description'] as Map<String, dynamic>? ??
        json['description'] as Map<String, dynamic>?;
    return GitHubIssueSummary(
      trackerProject: trackerProject,
      repoSlug: null,
      number: _readInt(json, 'id'),
      title: json['subject'] as String? ?? '',
      body: description?['raw'] as String? ?? '',
      state: 'open',
      url: _resolveUrl(_readUrl(json), host),
      updatedAt: DateTime.parse(_readString(json, 'updatedAt')),
      userLogin:
          _readLinkTitle(
            (json['_links'] as Map<String, dynamic>?)?['author'],
          ) ??
          '',
      labels: const <String>[],
    );
  }

  factory GitHubIssueSummary.fromSearchJson(Map<String, dynamic> json) {
    final repositoryUrl = json['repository_url'] as String?;
    if (repositoryUrl == null || repositoryUrl.isEmpty) {
      throw const FormatException(
        'Missing repository_url in GitHub search result item.',
      );
    }
    return GitHubIssueSummary.fromRepositoryJson(
      _parseRepositorySlugFromRepositoryUrl(repositoryUrl),
      json,
    );
  }

  static RepositorySlug _parseRepositorySlugFromRepositoryUrl(String value) {
    return parseRepositorySlugFromRepositoryUrl(value);
  }

  factory GitHubIssueSummary.fromJson(Map<String, dynamic> json) {
    final trackerProject = json['repo'] as String? ?? '';
    RepositorySlug? repoSlug;
    try {
      repoSlug = _parseRepositorySlug(trackerProject);
    } on FormatException {
      repoSlug = null;
    }
    return GitHubIssueSummary(
      trackerProject: trackerProject,
      repoSlug: repoSlug,
      number: _readInt(json, 'number'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: _readString(json, 'url'),
      updatedAt: DateTime.parse(_readString(json, 'updated_at')),
      userLogin: json['user_login'] as String? ?? '',
      labels: (json['labels'] as List<dynamic>? ?? const <dynamic>[])
          .map((label) => label.toString())
          .toList(growable: false),
    );
  }

  RepositorySlug get requiredRepoSlug {
    final slug = repoSlug;
    if (slug == null) {
      throw StateError(
        'Tracker project "$trackerProject" does not use a repository slug.',
      );
    }
    return slug;
  }

  Map<String, Object?> toJson() => {
    'repo': trackerProject,
    'number': number,
    'title': title,
    'body': body,
    'state': state,
    'url': url,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'user_login': userLogin,
    'labels': labels,
  };
}

class GitHubIssueComment {
  GitHubIssueComment({
    required this.id,
    required this.body,
    required this.userLogin,
    required this.createdAt,
    required this.updatedAt,
    required this.url,
  });

  final int id;
  final String body;
  final String userLogin;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String url;

  factory GitHubIssueComment.fromJson(Map<String, dynamic> json) {
    return GitHubIssueComment(
      id: _readInt(json, 'id'),
      body: json['body'] as String? ?? '',
      userLogin: _readLogin(json['user']) ?? _readLogin(json['poster']) ?? '',
      createdAt: DateTime.parse(_readString(json, 'created_at')),
      updatedAt: DateTime.parse(_readString(json, 'updated_at')),
      url: _readUrl(json),
    );
  }

  factory GitHubIssueComment.fromOpenProjectJson(
    Map<String, dynamic> json,
    Uri host,
  ) {
    return GitHubIssueComment(
      id: _readInt(json, 'id'),
      body: _readOpenProjectCommentBody(json) ?? '',
      userLogin:
          _readLinkTitle((json['_links'] as Map<String, dynamic>?)?['user']) ??
          '',
      createdAt: DateTime.parse(_readString(json, 'createdAt')),
      updatedAt: DateTime.parse(_readString(json, 'updatedAt')),
      url: _resolveUrl(_readUrl(json), host),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'body': body,
    'user_login': userLogin,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'url': url,
  };
}

class IssueThread {
  IssueThread({required this.issue, required this.comments});

  final GitHubIssueSummary issue;
  final List<GitHubIssueComment> comments;

  bool get isOpen => issue.state == 'open';

  GitHubIssueComment? get latestComment =>
      comments.isEmpty ? null : comments.last;

  Map<String, Object?> toJson() => {
    'issue': issue.toJson(),
    'comments': comments.map((comment) => comment.toJson()).toList(),
  };
}

class PostedComment {
  PostedComment({required this.id, required this.url, required this.body});

  final int id;
  final String url;
  final String body;
}

int _readInt(Map<String, dynamic> json, String key, {String? fallbackKey}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.parse(value);
  }
  throw FormatException(
    'Missing integer field "$key"${fallbackKey == null ? '' : ' or "$fallbackKey"'} in tracker payload.',
  );
}

String _readString(
  Map<String, dynamic> json,
  String key, {
  String? fallbackKey,
}) {
  final value = json[key] ?? (fallbackKey == null ? null : json[fallbackKey]);
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException(
    'Missing string field "$key"${fallbackKey == null ? '' : ' or "$fallbackKey"'} in tracker payload.',
  );
}

String _readUrl(Map<String, dynamic> json) {
  return json['html_url'] as String? ??
      json['url'] as String? ??
      json['htmlUrl'] as String? ??
      _readLinkHref((json['_links'] as Map<String, dynamic>?)?['self']) ??
      '';
}

String? _readLogin(Object? userNode) {
  if (userNode is Map<String, dynamic>) {
    final login = userNode['login']?.toString().trim();
    if (login != null && login.isNotEmpty) {
      return login;
    }
    final userName = userNode['user_name']?.toString().trim();
    if (userName != null && userName.isNotEmpty) {
      return userName;
    }
    final username = userNode['username']?.toString().trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }
  }
  return null;
}

String? _readLinkTitle(Object? linkNode) {
  if (linkNode is Map<String, dynamic>) {
    final title = linkNode['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
  }
  return null;
}

String? _readLinkHref(Object? linkNode) {
  if (linkNode is Map<String, dynamic>) {
    final href = linkNode['href']?.toString().trim();
    if (href != null && href.isNotEmpty) {
      return href;
    }
  }
  return null;
}

String? _readOpenProjectCommentBody(Map<String, dynamic> json) {
  final comment = json['comment'];
  if (comment is Map<String, dynamic>) {
    final raw = comment['raw']?.toString();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
  }
  return null;
}

String _resolveUrl(String value, Uri host) {
  if (value.isEmpty) {
    return value;
  }
  final uri = Uri.parse(value);
  if (uri.hasScheme) {
    return value;
  }
  return host.resolveUri(uri).toString();
}

RepositorySlug _parseRepositorySlug(String value) {
  final parts = value.split('/');
  if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
    throw FormatException(
      'Invalid repository slug "$value". Expected owner/repo.',
    );
  }
  return RepositorySlug(parts[0], parts[1]);
}

RepositorySlug parseRepositorySlugFromRepositoryUrl(String value) {
  final uri = Uri.parse(value);
  final segments = uri.pathSegments;
  final reposIndex = segments.indexOf('repos');
  if (reposIndex == -1 || reposIndex + 2 >= segments.length) {
    throw FormatException(
      'Invalid repository_url in GitHub search result item: "$value"',
    );
  }
  return RepositorySlug(segments[reposIndex + 1], segments[reposIndex + 2]);
}

class _OpenProjectConfig {
  const _OpenProjectConfig({required this.host, required this.token});

  final Uri host;
  final String token;
}

class _OpenProjectProjectRef {
  const _OpenProjectProjectRef({required this.id, required this.name});

  final int id;
  final String name;
}
