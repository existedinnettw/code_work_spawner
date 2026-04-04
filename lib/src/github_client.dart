import 'dart:convert';
import 'dart:io';

class GitHubClient {
  GitHubClient({this.ghCommand = 'gh'});

  final String ghCommand;

  Future<List<GitHubIssueSummary>> fetchUpdatedIssues({
    required String repo,
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
      'repos/$repo/issues${_encodeQuery(query)}',
    ]);

    return (json as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => !item.containsKey('pull_request'))
        .map(GitHubIssueSummary.fromJson)
        .toList(growable: false);
  }

  Future<IssueThread> fetchThread({
    required String repo,
    required GitHubIssueSummary issue,
  }) async {
    final comments = await _runJson([
      'api',
      '-X',
      'GET',
      'repos/$repo/issues/${issue.number}/comments?per_page=100',
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
    required String repo,
    required int issueNumber,
    required String body,
  }) async {
    final json = await _runJson([
      'api',
      '-X',
      'POST',
      'repos/$repo/issues/$issueNumber/comments',
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

  String _encodeQuery(Map<String, String> query) {
    if (query.isEmpty) {
      return '';
    }

    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return '?$encoded';
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
