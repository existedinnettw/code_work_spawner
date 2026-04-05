import 'package:json_annotation/json_annotation.dart';

part 'config_schema.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class AppConfigDocument {
  const AppConfigDocument({
    this.dataDir,
    this.worktreeDir,
    this.defaults,
    this.projects,
  });

  final String? dataDir;
  final String? worktreeDir;
  final AppConfigDefaultsDocument? defaults;
  final Map<String, ProjectConfigDocument>? projects;

  factory AppConfigDocument.fromJson(Map<String, dynamic> json) =>
      _$AppConfigDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigDocumentToJson(this);
}

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class AppConfigDefaultsDocument {
  const AppConfigDefaultsDocument({this.issueAssistant});

  final IssueAssistantConfigDocument? issueAssistant;

  factory AppConfigDefaultsDocument.fromJson(Map<String, dynamic> json) =>
      _$AppConfigDefaultsDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigDefaultsDocumentToJson(this);
}

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class ProjectConfigDocument {
  const ProjectConfigDocument({
    this.repo,
    this.path,
    this.defaultBranch,
    this.sessionPrefix,
    this.issueAssistant,
  });

  final String? repo;
  final String? path;
  final String? defaultBranch;
  final String? sessionPrefix;
  final IssueAssistantConfigDocument? issueAssistant;

  factory ProjectConfigDocument.fromJson(Map<String, dynamic> json) =>
      _$ProjectConfigDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectConfigDocumentToJson(this);
}

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class IssueAssistantConfigDocument {
  const IssueAssistantConfigDocument({
    this.enabled,
    this.pollInterval,
    this.maxConcurrentIssues,
    this.mentionTriggers,
    this.prompt,
    this.responders,
    this.capabilities,
    this.notifications,
    this.commentTag,
    this.commentPrefixTemplate,
    this.commentFooterTemplate,
  });

  final bool? enabled;
  final String? pollInterval;
  final int? maxConcurrentIssues;
  final List<String>? mentionTriggers;
  final String? prompt;
  final List<CliResponderConfigDocument>? responders;
  final List<AssistantCapability>? capabilities;
  final List<NotificationConfigDocument>? notifications;
  final String? commentTag;
  final String? commentPrefixTemplate;
  final String? commentFooterTemplate;

  factory IssueAssistantConfigDocument.fromJson(Map<String, dynamic> json) =>
      _$IssueAssistantConfigDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$IssueAssistantConfigDocumentToJson(this);
}

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class CliResponderConfigDocument {
  const CliResponderConfigDocument({
    this.id,
    this.command,
    this.args,
    this.env,
    this.stdinTemplate,
    this.timeout,
  });

  final String? id;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? stdinTemplate;
  final String? timeout;

  factory CliResponderConfigDocument.fromJson(Map<String, dynamic> json) =>
      _$CliResponderConfigDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$CliResponderConfigDocumentToJson(this);
}

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: true,
  explicitToJson: true,
  includeIfNull: false,
)
class NotificationConfigDocument {
  const NotificationConfigDocument({
    this.type,
    this.enabled,
    this.events,
    this.webhookUrl,
    this.username,
    this.avatarUrl,
  });

  final NotificationType? type;
  final bool? enabled;
  final List<NotificationEvent>? events;
  final String? webhookUrl;
  final String? username;
  final String? avatarUrl;

  factory NotificationConfigDocument.fromJson(Map<String, dynamic> json) =>
      _$NotificationConfigDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$NotificationConfigDocumentToJson(this);
}

@JsonEnum(fieldRename: FieldRename.snake)
enum AssistantCapability { planning, bugVerification }

enum NotificationType { discordWebhook, desktop }

@JsonEnum(fieldRename: FieldRename.snake)
enum NotificationEvent {
  mentionDetected,
  replyPosted,
  noReply,
  responderFailed,
}
