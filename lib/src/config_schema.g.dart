// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config_schema.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfigDocument _$AppConfigDocumentFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AppConfigDocument', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const ['dataDir', 'worktreeDir', 'defaults', 'projects'],
      );
      final val = AppConfigDocument(
        dataDir: $checkedConvert('dataDir', (v) => v as String?),
        worktreeDir: $checkedConvert('worktreeDir', (v) => v as String?),
        defaults: $checkedConvert(
          'defaults',
          (v) => v == null
              ? null
              : AppConfigDefaultsDocument.fromJson(v as Map<String, dynamic>),
        ),
        projects: $checkedConvert(
          'projects',
          (v) => (v as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
              k,
              ProjectConfigDocument.fromJson(e as Map<String, dynamic>),
            ),
          ),
        ),
      );
      return val;
    });

Map<String, dynamic> _$AppConfigDocumentToJson(AppConfigDocument instance) =>
    <String, dynamic>{
      'dataDir': ?instance.dataDir,
      'worktreeDir': ?instance.worktreeDir,
      'defaults': ?instance.defaults?.toJson(),
      'projects': ?instance.projects?.map((k, e) => MapEntry(k, e.toJson())),
    };

AppConfigDefaultsDocument _$AppConfigDefaultsDocumentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('AppConfigDefaultsDocument', json, ($checkedConvert) {
  $checkKeys(json, allowedKeys: const ['issueAssistant']);
  final val = AppConfigDefaultsDocument(
    issueAssistant: $checkedConvert(
      'issueAssistant',
      (v) => v == null
          ? null
          : IssueAssistantConfigDocument.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$AppConfigDefaultsDocumentToJson(
  AppConfigDefaultsDocument instance,
) => <String, dynamic>{'issueAssistant': ?instance.issueAssistant?.toJson()};

ProjectConfigDocument _$ProjectConfigDocumentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ProjectConfigDocument', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'provider',
      'repo',
      'path',
      'defaultBranch',
      'sessionPrefix',
      'issueAssistant',
    ],
  );
  final val = ProjectConfigDocument(
    provider: $checkedConvert(
      'provider',
      (v) => $enumDecodeNullable(_$IssueTrackerProviderEnumMap, v),
    ),
    repo: $checkedConvert('repo', (v) => v as String?),
    path: $checkedConvert('path', (v) => v as String?),
    defaultBranch: $checkedConvert('defaultBranch', (v) => v as String?),
    sessionPrefix: $checkedConvert('sessionPrefix', (v) => v as String?),
    issueAssistant: $checkedConvert(
      'issueAssistant',
      (v) => v == null
          ? null
          : IssueAssistantConfigDocument.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$ProjectConfigDocumentToJson(
  ProjectConfigDocument instance,
) => <String, dynamic>{
  'provider': ?_$IssueTrackerProviderEnumMap[instance.provider],
  'repo': ?instance.repo,
  'path': ?instance.path,
  'defaultBranch': ?instance.defaultBranch,
  'sessionPrefix': ?instance.sessionPrefix,
  'issueAssistant': ?instance.issueAssistant?.toJson(),
};

const _$IssueTrackerProviderEnumMap = {
  IssueTrackerProvider.github: 'github',
  IssueTrackerProvider.gitea: 'gitea',
};

IssueAssistantConfigDocument _$IssueAssistantConfigDocumentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('IssueAssistantConfigDocument', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'enabled',
      'eventSource',
      'pollInterval',
      'maxConcurrentIssues',
      'mentionTriggers',
      'prompt',
      'responders',
      'capabilities',
      'notifications',
      'commentTag',
      'commentPrefixTemplate',
      'commentFooterTemplate',
    ],
  );
  final val = IssueAssistantConfigDocument(
    enabled: $checkedConvert('enabled', (v) => v as bool?),
    eventSource: $checkedConvert(
      'eventSource',
      (v) => $enumDecodeNullable(_$IssueAssistantEventSourceKindEnumMap, v),
    ),
    pollInterval: $checkedConvert('pollInterval', (v) => v as String?),
    maxConcurrentIssues: $checkedConvert(
      'maxConcurrentIssues',
      (v) => (v as num?)?.toInt(),
    ),
    mentionTriggers: $checkedConvert(
      'mentionTriggers',
      (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
    ),
    prompt: $checkedConvert('prompt', (v) => v as String?),
    responders: $checkedConvert(
      'responders',
      (v) => (v as List<dynamic>?)
          ?.map(
            (e) =>
                CliResponderConfigDocument.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    ),
    capabilities: $checkedConvert(
      'capabilities',
      (v) => (v as List<dynamic>?)
          ?.map((e) => $enumDecode(_$AssistantCapabilityEnumMap, e))
          .toList(),
    ),
    notifications: $checkedConvert(
      'notifications',
      (v) => (v as List<dynamic>?)
          ?.map(
            (e) =>
                NotificationConfigDocument.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    ),
    commentTag: $checkedConvert('commentTag', (v) => v as String?),
    commentPrefixTemplate: $checkedConvert(
      'commentPrefixTemplate',
      (v) => v as String?,
    ),
    commentFooterTemplate: $checkedConvert(
      'commentFooterTemplate',
      (v) => v as String?,
    ),
  );
  return val;
});

Map<String, dynamic> _$IssueAssistantConfigDocumentToJson(
  IssueAssistantConfigDocument instance,
) => <String, dynamic>{
  'enabled': ?instance.enabled,
  'eventSource': ?_$IssueAssistantEventSourceKindEnumMap[instance.eventSource],
  'pollInterval': ?instance.pollInterval,
  'maxConcurrentIssues': ?instance.maxConcurrentIssues,
  'mentionTriggers': ?instance.mentionTriggers,
  'prompt': ?instance.prompt,
  'responders': ?instance.responders?.map((e) => e.toJson()).toList(),
  'capabilities': ?instance.capabilities
      ?.map((e) => _$AssistantCapabilityEnumMap[e]!)
      .toList(),
  'notifications': ?instance.notifications?.map((e) => e.toJson()).toList(),
  'commentTag': ?instance.commentTag,
  'commentPrefixTemplate': ?instance.commentPrefixTemplate,
  'commentFooterTemplate': ?instance.commentFooterTemplate,
};

const _$IssueAssistantEventSourceKindEnumMap = {
  IssueAssistantEventSourceKind.ghPolling: 'gh/polling',
  IssueAssistantEventSourceKind.teaPolling: 'tea/polling',
  IssueAssistantEventSourceKind.ghGosmee: 'gh/gosmee',
  IssueAssistantEventSourceKind.ghWebhookForward: 'gh/webhook-forward',
  IssueAssistantEventSourceKind.teaGosmee: 'tea/gosmee',
};

const _$AssistantCapabilityEnumMap = {
  AssistantCapability.planning: 'planning',
  AssistantCapability.bugVerification: 'bug_verification',
};

CliResponderConfigDocument _$CliResponderConfigDocumentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CliResponderConfigDocument', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'id',
      'command',
      'args',
      'env',
      'stdinTemplate',
      'timeout',
    ],
  );
  final val = CliResponderConfigDocument(
    id: $checkedConvert('id', (v) => v as String?),
    command: $checkedConvert('command', (v) => v as String?),
    args: $checkedConvert(
      'args',
      (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
    ),
    env: $checkedConvert(
      'env',
      (v) =>
          (v as Map<String, dynamic>?)?.map((k, e) => MapEntry(k, e as String)),
    ),
    stdinTemplate: $checkedConvert('stdinTemplate', (v) => v as String?),
    timeout: $checkedConvert('timeout', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$CliResponderConfigDocumentToJson(
  CliResponderConfigDocument instance,
) => <String, dynamic>{
  'id': ?instance.id,
  'command': ?instance.command,
  'args': ?instance.args,
  'env': ?instance.env,
  'stdinTemplate': ?instance.stdinTemplate,
  'timeout': ?instance.timeout,
};

NotificationConfigDocument _$NotificationConfigDocumentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('NotificationConfigDocument', json, ($checkedConvert) {
  $checkKeys(
    json,
    allowedKeys: const [
      'type',
      'enabled',
      'events',
      'webhookUrl',
      'username',
      'avatarUrl',
    ],
  );
  final val = NotificationConfigDocument(
    type: $checkedConvert(
      'type',
      (v) => $enumDecodeNullable(_$NotificationTypeEnumMap, v),
    ),
    enabled: $checkedConvert('enabled', (v) => v as bool?),
    events: $checkedConvert(
      'events',
      (v) => (v as List<dynamic>?)
          ?.map((e) => $enumDecode(_$NotificationEventEnumMap, e))
          .toList(),
    ),
    webhookUrl: $checkedConvert('webhookUrl', (v) => v as String?),
    username: $checkedConvert('username', (v) => v as String?),
    avatarUrl: $checkedConvert('avatarUrl', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$NotificationConfigDocumentToJson(
  NotificationConfigDocument instance,
) => <String, dynamic>{
  'type': ?_$NotificationTypeEnumMap[instance.type],
  'enabled': ?instance.enabled,
  'events': ?instance.events
      ?.map((e) => _$NotificationEventEnumMap[e]!)
      .toList(),
  'webhookUrl': ?instance.webhookUrl,
  'username': ?instance.username,
  'avatarUrl': ?instance.avatarUrl,
};

const _$NotificationTypeEnumMap = {
  NotificationType.discordWebhook: 'discordWebhook',
  NotificationType.desktop: 'desktop',
};

const _$NotificationEventEnumMap = {
  NotificationEvent.mentionDetected: 'mention_detected',
  NotificationEvent.replyPosted: 'reply_posted',
  NotificationEvent.noReply: 'no_reply',
  NotificationEvent.responderFailed: 'responder_failed',
};
