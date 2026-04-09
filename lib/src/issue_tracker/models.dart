import 'package:github/github.dart';

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
      number: readIntField(json, 'number', fallbackKey: 'index'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: readUrlField(json),
      updatedAt: DateTime.parse(readStringField(json, 'updated_at')),
      userLogin:
          readLoginField(json['user']) ?? readLoginField(json['poster']) ?? '',
      labels: labelsNode
          .map(
            (label) => readStringField(label as Map<String, dynamic>, 'name'),
          )
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
      number: readIntField(json, 'id'),
      title: json['subject'] as String? ?? '',
      body: description?['raw'] as String? ?? '',
      state: 'open',
      url: resolveTrackerUrl(readUrlField(json), host),
      updatedAt: DateTime.parse(readStringField(json, 'updatedAt')),
      userLogin:
          readLinkTitleField(
            (json['_links'] as Map<String, dynamic>?)?['author'],
          ) ??
          '',
      labels: const <String>[],
    );
  }

  factory GitHubIssueSummary.fromGitLabJson(
    String trackerProject,
    Map<String, dynamic> json,
  ) {
    final labelsNode = json['labels'] as List<dynamic>? ?? const <dynamic>[];
    return GitHubIssueSummary(
      trackerProject: trackerProject,
      repoSlug: null,
      number: readIntField(json, 'iid'),
      title: json['title'] as String? ?? '',
      body: json['description'] as String? ?? '',
      state: json['state'] as String? ?? 'opened',
      url: readUrlField(json),
      updatedAt: DateTime.parse(readStringField(json, 'updated_at')),
      userLogin: readLoginField(json['author']) ?? '',
      labels: labelsNode
          .map((label) => label.toString())
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
      parseRepositorySlugFromRepositoryUrl(repositoryUrl),
      json,
    );
  }

  factory GitHubIssueSummary.fromJson(Map<String, dynamic> json) {
    final trackerProject = json['repo'] as String? ?? '';
    RepositorySlug? repoSlug;
    try {
      repoSlug = parseRepositorySlug(trackerProject);
    } on FormatException {
      repoSlug = null;
    }
    return GitHubIssueSummary(
      trackerProject: trackerProject,
      repoSlug: repoSlug,
      number: readIntField(json, 'number'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      state: json['state'] as String? ?? 'open',
      url: readStringField(json, 'url'),
      updatedAt: DateTime.parse(readStringField(json, 'updated_at')),
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
      id: readIntField(json, 'id'),
      body: json['body'] as String? ?? '',
      userLogin:
          readLoginField(json['user']) ?? readLoginField(json['poster']) ?? '',
      createdAt: DateTime.parse(readStringField(json, 'created_at')),
      updatedAt: DateTime.parse(readStringField(json, 'updated_at')),
      url: readUrlField(json),
    );
  }

  factory GitHubIssueComment.fromOpenProjectJson(
    Map<String, dynamic> json,
    Uri host,
  ) {
    return GitHubIssueComment(
      id: readIntField(json, 'id'),
      body: readOpenProjectCommentBody(json) ?? '',
      userLogin:
          readLinkTitleField(
            (json['_links'] as Map<String, dynamic>?)?['user'],
          ) ??
          '',
      createdAt: DateTime.parse(readStringField(json, 'createdAt')),
      updatedAt: DateTime.parse(readStringField(json, 'updatedAt')),
      url: resolveTrackerUrl(readUrlField(json), host),
    );
  }

  factory GitHubIssueComment.fromGitLabJson(
    Map<String, dynamic> json,
    String issueUrl,
  ) {
    return GitHubIssueComment(
      id: readIntField(json, 'id'),
      body: json['body'] as String? ?? '',
      userLogin: readLoginField(json['author']) ?? '',
      createdAt: DateTime.parse(readStringField(json, 'created_at')),
      updatedAt: DateTime.parse(readStringField(json, 'updated_at')),
      url: buildGitLabNoteUrl(issueUrl: issueUrl, json: json),
    );
  }

  static String buildGitLabNoteUrl({
    required String issueUrl,
    required Map<String, dynamic> json,
  }) {
    final noteUrl = readOptionalStringField(json, 'web_url');
    if (noteUrl != null && noteUrl.isNotEmpty) {
      return noteUrl;
    }
    final resolvedIssueUrl =
        readOptionalStringField(json, 'noteable_url') ??
        readOptionalStringField(json, 'issue_web_url') ??
        issueUrl;
    if (resolvedIssueUrl.isEmpty) {
      return resolvedIssueUrl;
    }
    return '$resolvedIssueUrl#note_${readIntField(json, "id")}';
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

  bool get isOpen => issue.state == 'open' || issue.state == 'opened';

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

int readIntField(Map<String, dynamic> json, String key, {String? fallbackKey}) {
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

String readStringField(
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

String? readOptionalStringField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

String readUrlField(Map<String, dynamic> json) {
  return json['html_url'] as String? ??
      json['web_url'] as String? ??
      json['url'] as String? ??
      json['htmlUrl'] as String? ??
      readLinkHrefField((json['_links'] as Map<String, dynamic>?)?['self']) ??
      '';
}

String? readLoginField(Object? userNode) {
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

String? readLinkTitleField(Object? linkNode) {
  if (linkNode is Map<String, dynamic>) {
    final title = linkNode['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
  }
  return null;
}

String? readLinkHrefField(Object? linkNode) {
  if (linkNode is Map<String, dynamic>) {
    final href = linkNode['href']?.toString().trim();
    if (href != null && href.isNotEmpty) {
      return href;
    }
  }
  return null;
}

String? readOpenProjectCommentBody(Map<String, dynamic> json) {
  final comment = json['comment'];
  if (comment is Map<String, dynamic>) {
    final raw = comment['raw']?.toString();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
  }
  return null;
}

String resolveTrackerUrl(String value, Uri host) {
  if (value.isEmpty) {
    return value;
  }
  final uri = Uri.parse(value);
  if (uri.hasScheme) {
    return value;
  }
  return host.resolveUri(uri).toString();
}

RepositorySlug parseRepositorySlug(String value) {
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
