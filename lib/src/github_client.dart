import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';

class GitHubClient {
  GitHubClient({this.ghCommand = 'gh'});

  final String ghCommand;
  Future<String?>? _authenticatedLoginFuture;
  static const int _pageSize = 100;

  Future<List<GitHubIssueSummary>> fetchUpdatedIssuesForRepos({
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
      if (since != null) 'updated:>=${since.toUtc().toIso8601String()}',
    ];

    final issues = <GitHubIssueSummary>[];
    for (var page = 1; true; page += 1) {
      final json = await _runJson([
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

  Future<IssueThread> fetchThread({
    required RepositorySlug repo,
    required GitHubIssueSummary issue,
  }) async {
    final comments = await _runJson([
      'api',
      '-X',
      'GET',
      _buildApiPath(
        repo,
        ['issues', '${issue.number}', 'comments'],
        {'per_page': '100'},
      ),
    ]);

    return IssueThread(
      issue: issue,
      comments: (comments as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(GitHubIssueComment.fromJson)
          .toList(growable: false),
    );
  }

  Future<PostedComment> createIssueComment({
    required RepositorySlug repo,
    required int issueNumber,
    required String body,
  }) async {
    final json = await _runJson([
      'api',
      '-X',
      'POST',
      _buildApiPath(repo, ['issues', '$issueNumber', 'comments']),
      '-f',
      'body=$body',
    ]);

    final map = json as Map<String, dynamic>;
    return PostedComment(
      id: map['id'] as int,
      url: map['html_url'] as String? ?? '',
      body: map['body'] as String? ?? body,
    );
  }

  Future<String?> getAuthenticatedLogin() {
    return _authenticatedLoginFuture ??= _loadAuthenticatedLogin();
  }

  Future<String?> _loadAuthenticatedLogin() async {
    final json = await _runJson(['api', 'user']);
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final login = json['login']?.toString().trim();
    if (login == null || login.isEmpty) {
      return null;
    }
    return login;
  }

  Future<Object?> _runJson(List<String> arguments) async {
    final result = await Process.run(ghCommand, arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        ghCommand,
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
      number: json['number'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: json['html_url'] as String? ?? '',
      updatedAt: DateTime.parse(json['updated_at'] as String),
      userLogin:
          (json['user'] as Map<String, dynamic>? ?? const {})['login']
              as String? ??
          'unknown',
      labels: labelsNode
          .map((label) => (label as Map<String, dynamic>)['name'].toString())
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
    final labelsNode = json['labels'] as List<dynamic>? ?? const [];
    return GitHubIssueSummary(
      repoSlug: RepositorySlug('', ''),
      number: json['number'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: json['html_url'] as String? ?? '',
      updatedAt: DateTime.parse(json['updated_at'] as String),
      userLogin:
          (json['user'] as Map<String, dynamic>? ?? const {})['login']
              as String? ??
          'unknown',
      labels: labelsNode
          .map((label) => (label as Map<String, dynamic>)['name'].toString())
          .toList(growable: false),
    );
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
      id: json['id'] as int,
      body: json['body'] as String? ?? '',
      userLogin:
          (json['user'] as Map<String, dynamic>? ?? const {})['login']
              as String? ??
          'unknown',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      url: json['html_url'] as String? ?? '',
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
