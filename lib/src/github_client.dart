import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';

class GitHubClient {
  GitHubClient({this.ghCommand = 'gh'});

  final String ghCommand;
  Future<String?>? _authenticatedLoginFuture;

  Future<List<GitHubIssueSummary>> fetchUpdatedIssues({
    required RepositorySlug repo,
    required DateTime? since,
  }) async {
    final query = <String, String>{
      'state': 'all',
      'sort': 'updated',
      'direction': 'asc',
      'per_page': '100',
      if (since != null) 'since': since.toUtc().toIso8601String(),
    };

    final json = await _runJson([
      'api',
      '-X',
      'GET',
      _buildApiPath(repo, ['issues'], query),
    ]);

    return (json as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => !item.containsKey('pull_request'))
        .map(GitHubIssueSummary.fromJson)
        .toList(growable: false);
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
    required this.number,
    required this.title,
    required this.body,
    required this.state,
    required this.url,
    required this.updatedAt,
    required this.userLogin,
    required this.labels,
  });

  final int number;
  final String title;
  final String body;
  final String state;
  final String url;
  final DateTime updatedAt;
  final String userLogin;
  final List<String> labels;

  factory GitHubIssueSummary.fromJson(Map<String, dynamic> json) {
    final labelsNode = json['labels'] as List<dynamic>? ?? const [];
    return GitHubIssueSummary(
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
