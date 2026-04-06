import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';

import 'config_schema.dart';

class GitHubClient {
  GitHubClient({this.ghCommand = 'gh', this.teaCommand = 'tea'});

  final String ghCommand;
  final String teaCommand;
  final Map<IssueTrackerProvider, Future<String?>> _authenticatedLoginFutures =
      <IssueTrackerProvider, Future<String?>>{};
  static const int _pageSize = 100;

  Future<List<GitHubIssueSummary>> fetchUpdatedIssuesForRepos({
    required IssueTrackerProvider provider,
    required Iterable<RepositorySlug> repos,
    required DateTime? since,
  }) {
    return switch (provider) {
      IssueTrackerProvider.github => _fetchUpdatedGitHubIssues(
        repos: repos,
        since: since,
      ),
      IssueTrackerProvider.gitea => _fetchUpdatedGiteaIssues(
        repos: repos,
        since: since,
      ),
    };
  }

  Future<IssueThread> fetchThread({
    required IssueTrackerProvider provider,
    required RepositorySlug repo,
    required GitHubIssueSummary issue,
  }) async {
    final comments = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson([
        'api',
        '-X',
        'GET',
        _buildApiPath(
          repo,
          ['issues', '${issue.number}', 'comments'],
          {'per_page': '100'},
        ),
      ]),
      IssueTrackerProvider.gitea => await _runTeaJson([
        'api',
        '-X',
        'GET',
        _buildApiPath(
          repo,
          ['issues', '${issue.number}', 'comments'],
          {'limit': '100'},
        ),
        '-r',
        repo.fullName,
      ]),
    };

    return IssueThread(
      issue: issue,
      comments: (comments as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(GitHubIssueComment.fromJson)
          .toList(growable: false),
    );
  }

  Future<PostedComment> createIssueComment({
    required IssueTrackerProvider provider,
    required RepositorySlug repo,
    required int issueNumber,
    required String body,
  }) async {
    final json = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson([
        'api',
        '-X',
        'POST',
        _buildApiPath(repo, ['issues', '$issueNumber', 'comments']),
        '-f',
        'body=$body',
      ]),
      IssueTrackerProvider.gitea => await _runTeaJson([
        'api',
        '-X',
        'POST',
        _buildApiPath(repo, ['issues', '$issueNumber', 'comments']),
        '-f',
        'body=$body',
        '-r',
        repo.fullName,
      ]),
    };

    final map = json as Map<String, dynamic>;
    return PostedComment(
      id: _readInt(map, 'id'),
      url: _readUrl(map),
      body: map['body'] as String? ?? body,
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
    };
  }

  Future<List<GitHubIssueSummary>> _fetchUpdatedGitHubIssues({
    required Iterable<RepositorySlug> repos,
    required DateTime? since,
  }) async {
    final repoList = repos.toList(growable: false);
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
    required Iterable<RepositorySlug> repos,
    required DateTime? since,
  }) async {
    final issues = <GitHubIssueSummary>[];

    for (final repo in repos) {
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

  Future<String?> _loadAuthenticatedLogin({
    required IssueTrackerProvider provider,
  }) async {
    final json = switch (provider) {
      IssueTrackerProvider.github => await _runGhJson(['api', 'user']),
      IssueTrackerProvider.gitea => await _runTeaJson(['api', 'user']),
    };
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final login = json['login']?.toString().trim();
    if (login == null || login.isEmpty) {
      return null;
    }
    return login;
  }

  Future<Object?> _runGhJson(List<String> arguments) {
    return _runJson(ghCommand, arguments);
  }

  Future<Object?> _runTeaJson(List<String> arguments) {
    return _runJson(teaCommand, arguments);
  }

  Future<Object?> _runJson(String command, List<String> arguments) async {
    final result = await Process.run(command, arguments);
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
}

class GitHubIssueSummary {
  GitHubIssueSummary({
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

  final RepositorySlug repoSlug;
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

  factory GitHubIssueSummary.fromJson(Map<String, dynamic> json) {
    return GitHubIssueSummary.fromRepositoryJson(RepositorySlug('', ''), json);
  }

  Map<String, Object?> toJson() => {
    'repo': repoSlug.fullName,
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
