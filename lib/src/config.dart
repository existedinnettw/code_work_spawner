import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'comment_templates.dart';
import 'config_schema.dart';
export 'config_schema.dart'
    show
        AssistantCapability,
        IssueAssistantEventSourceKind,
        IssueAssistantReconciliationKind,
        IssueTrackerProvider,
        NotificationConfigDocument,
        NotificationEvent,
        NotificationType;

const String defaultIssueAssistantPrompt = '''
You are a repository issue thread assistant.

Decide whether to reply. Rules:
- If the latest trigger explicitly mentions the assistant, always return "reply".
- If the discussion already has a good enough answer, return "no_reply".
- Supported modes are "planning" and "bug_verification".
- For planning requests, provide practical architecture and implementation guidance.
- For bug_verification requests, you may inspect the local repository and run temporary tests in the current workspace. Do not create commits or persistent artifacts.
- Always return strict JSON only.

JSON schema:
{
  "decision": "reply" | "no_reply",
  "mode": "planning" | "bug_verification",
  "markdown": "markdown response, omitted for no_reply",
  "summary": "short internal summary"
}

Repository metadata:
- repo: {{repo}}
- tracker_provider: {{tracker_provider}}
- project_key: {{project_key}}
- project_path: {{project_path}}
- issue_number: {{issue_number}}
- issue_title: {{issue_title}}
- issue_url: {{issue_url}}
- mention_triggers: {{mention_triggers}}
- trigger: {{trigger}}
- capabilities: {{capabilities}}

Issue body:
{{issue_body}}

Current issue thread JSON:
{{thread_json}}
''';

class AppConfig {
  AppConfig({
    required this.configPath,
    required this.dataDir,
    required this.worktreeDir,
    required this.defaults,
    required this.projects,
  });

  final String configPath;
  final String? dataDir;
  final String? worktreeDir;
  final IssueAssistantConfig defaults;
  final Map<String, ProjectConfig> projects;

  static Future<AppConfig> load(String path) async {
    final file = File(path);
    final contents = await file.readAsString();
    final yaml = loadYaml(contents);
    if (yaml is! YamlMap) {
      throw const FormatException('Config root must be a YAML map.');
    }

    final root = _normalizeYamlNode(yaml);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Config root must be a YAML map.');
    }

    _assertCamelCaseConfigKeys(root);
    _normalizeLegacyEventSourceConfig(root);
    final document = _parseDocument(root);
    return _fromDocument(path, document);
  }

  static String renderInitialConfig() {
    return _InitialConfigRenderer().render(_initialTemplateDocument());
  }

  static AppConfig _fromDocument(String path, AppConfigDocument document) {
    final defaults = IssueAssistantConfig.fromDocument(
      document.defaults?.issueAssistant,
    );
    final projectDocuments = document.projects;
    if (projectDocuments == null || projectDocuments.isEmpty) {
      throw const FormatException('projects must be a non-empty map.');
    }

    final projects = <String, ProjectConfig>{};
    for (final entry in projectDocuments.entries) {
      projects[entry.key] = ProjectConfig.fromDocument(
        key: entry.key,
        document: entry.value,
        defaultAssistant: defaults,
      );
    }

    return AppConfig(
      configPath: p.normalize(p.absolute(path)),
      dataDir: _expandOptionalPath(document.dataDir),
      worktreeDir: _expandOptionalPath(document.worktreeDir),
      defaults: defaults,
      projects: projects,
    );
  }

  static AppConfigDocument _parseDocument(Map<String, dynamic> root) {
    try {
      return AppConfigDocument.fromJson(root);
    } catch (error) {
      throw FormatException(error.toString());
    }
  }

  static AppConfigDocument _initialTemplateDocument() {
    return AppConfigDocument(
      dataDir: '~/.agent-orchestrator',
      worktreeDir: '~/.worktrees',
      defaults: AppConfigDefaultsDocument(
        issueAssistant: IssueAssistantConfigDocument(
          enabled: true,
          eventSource: IssueAssistantEventSourceDocument(
            type: IssueAssistantEventSourceKind.ghPolling,
            pollInterval: '30s',
          ),
          maxConcurrentIssues: 3,
          mentionTriggers: const ['@codex', '@helper'],
        ),
      ),
      projects: {
        'sample': ProjectConfigDocument(
          provider: IssueTrackerProvider.github,
          repo: 'owner/repo',
          path: '~/path/to/repo',
          defaultBranch: 'main',
        ),
      },
    );
  }
}

class ProjectConfig {
  ProjectConfig({
    required this.key,
    required this.provider,
    required this.repo,
    required this.repoSlug,
    required this.path,
    required this.defaultBranch,
    required this.sessionPrefix,
    required this.issueAssistant,
  });

  final String key;
  final IssueTrackerProvider provider;
  final String repo;
  final RepositorySlug repoSlug;
  final String path;
  final String defaultBranch;
  final String sessionPrefix;
  final IssueAssistantConfig issueAssistant;

  factory ProjectConfig.fromDocument({
    required String key,
    required ProjectConfigDocument document,
    required IssueAssistantConfig defaultAssistant,
  }) {
    final repo = document.repo?.trim();
    if (repo == null || repo.isEmpty) {
      throw FormatException(
        'Missing required config field: projects.$key.repo',
      );
    }
    final path = document.path?.trim();
    if (path == null || path.isEmpty) {
      throw FormatException(
        'Missing required config field: projects.$key.path',
      );
    }

    final provider = document.provider ?? IssueTrackerProvider.github;
    var issueAssistant = defaultAssistant.merge(document.issueAssistant);
    if (document.issueAssistant?.eventSource?.type == null &&
        issueAssistant.eventSource is PollingIssueEventSourceConfig) {
      issueAssistant = issueAssistant.copyWith(
        eventSource:
            (issueAssistant.eventSource as PollingIssueEventSourceConfig)
                .copyWith(
                  type: provider == IssueTrackerProvider.github
                      ? IssueAssistantEventSourceKind.ghPolling
                      : IssueAssistantEventSourceKind.teaPolling,
                ),
      );
    }
    switch (issueAssistant.eventSource.type) {
      case IssueAssistantEventSourceKind.ghPolling:
      case IssueAssistantEventSourceKind.ghGosmee:
      case IssueAssistantEventSourceKind.ghWebhookForward:
        if (provider != IssueTrackerProvider.github) {
          throw FormatException(
            'projects.$key.issueAssistant.eventSource '
            '${_eventSourceConfigValue(issueAssistant.eventSource.type)} '
            'requires provider: github.',
          );
        }
      case IssueAssistantEventSourceKind.teaPolling:
        if (provider != IssueTrackerProvider.gitea) {
          throw FormatException(
            'projects.$key.issueAssistant.eventSource tea/polling '
            'requires provider: gitea.',
          );
        }
      case IssueAssistantEventSourceKind.teaGosmee:
        if (provider != IssueTrackerProvider.gitea) {
          throw FormatException(
            'projects.$key.issueAssistant.eventSource tea/gosmee '
            'requires provider: gitea.',
          );
        }
    }

    return ProjectConfig(
      key: key,
      provider: provider,
      repo: repo,
      repoSlug: _parseRepositorySlug(repo, field: 'projects.$key.repo'),
      path: _expandHome(path),
      defaultBranch: document.defaultBranch ?? 'main',
      sessionPrefix: document.sessionPrefix ?? _deriveSessionPrefix(key),
      issueAssistant: issueAssistant,
    );
  }

  static RepositorySlug _parseRepositorySlug(
    String value, {
    required String field,
  }) {
    final parts = value.split('/');
    if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
      throw FormatException(
        'Invalid repository slug for $field: "$value". Expected owner/repo.',
      );
    }
    return RepositorySlug(parts[0], parts[1]);
  }
}

class IssueAssistantConfig {
  IssueAssistantConfig({
    required this.enabled,
    required this.eventSource,
    required this.maxConcurrentIssues,
    required this.mentionTriggers,
    required this.prompt,
    required this.responders,
    required this.capabilities,
    required this.notifications,
    required this.commentTag,
    required this.commentPrefixTemplate,
    required this.commentFooterTemplate,
  });

  final bool enabled;
  final IssueEventSourceConfig eventSource;
  final int maxConcurrentIssues;
  final List<String> mentionTriggers;
  final String prompt;
  final List<CliResponderConfig> responders;
  final Set<AssistantCapability> capabilities;
  final List<NotificationConfig> notifications;
  final String commentTag;
  final String commentPrefixTemplate;
  final String commentFooterTemplate;

  factory IssueAssistantConfig.fromDocument(
    IssueAssistantConfigDocument? document,
  ) {
    return const _IssueAssistantConfigResolver()
        .resolve(base: null, overlay: null)
        .merge(document);
  }

  IssueAssistantConfig merge(IssueAssistantConfigDocument? overlay) {
    return const _IssueAssistantConfigResolver().resolve(
      base: this,
      overlay: overlay,
    );
  }

  IssueAssistantConfig copyWith({IssueEventSourceConfig? eventSource}) {
    return IssueAssistantConfig(
      enabled: enabled,
      eventSource: eventSource ?? this.eventSource,
      maxConcurrentIssues: maxConcurrentIssues,
      mentionTriggers: mentionTriggers,
      prompt: prompt,
      responders: responders,
      capabilities: capabilities,
      notifications: notifications,
      commentTag: commentTag,
      commentPrefixTemplate: commentPrefixTemplate,
      commentFooterTemplate: commentFooterTemplate,
    );
  }
}

sealed class IssueEventSourceConfig {
  const IssueEventSourceConfig({required this.type});

  final IssueAssistantEventSourceKind type;

  bool get usesChannelEventSource => !_isPollingEventSource(type);
}

class PollingIssueEventSourceConfig extends IssueEventSourceConfig {
  const PollingIssueEventSourceConfig({
    required super.type,
    required this.pollInterval,
  });

  final Duration pollInterval;

  PollingIssueEventSourceConfig copyWith({
    IssueAssistantEventSourceKind? type,
    Duration? pollInterval,
  }) {
    return PollingIssueEventSourceConfig(
      type: type ?? this.type,
      pollInterval: pollInterval ?? this.pollInterval,
    );
  }
}

class ChannelIssueEventSourceConfig extends IssueEventSourceConfig {
  const ChannelIssueEventSourceConfig({
    required super.type,
    required this.reconciliation,
    required this.reconcileInterval,
  });

  final IssueAssistantReconciliationKind reconciliation;
  final Duration reconcileInterval;

  ChannelIssueEventSourceConfig copyWith({
    IssueAssistantEventSourceKind? type,
    IssueAssistantReconciliationKind? reconciliation,
    Duration? reconcileInterval,
  }) {
    return ChannelIssueEventSourceConfig(
      type: type ?? this.type,
      reconciliation: reconciliation ?? this.reconciliation,
      reconcileInterval: reconcileInterval ?? this.reconcileInterval,
    );
  }
}

class CliResponderConfig {
  CliResponderConfig({
    required this.id,
    required this.command,
    required this.args,
    required this.env,
    required this.stdinTemplate,
    required this.timeout,
  });

  final String id;
  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String stdinTemplate;
  final Duration timeout;

  factory CliResponderConfig.fromDocument(CliResponderConfigDocument document) {
    final id = document.id?.trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('Responder id is required.');
    }
    final command = document.command?.trim();
    if (command == null || command.isEmpty) {
      throw FormatException('Responder "$id" must define command.');
    }

    return CliResponderConfig(
      id: id,
      command: command,
      args: _normalizeArgs(document.args ?? const <String>[]),
      env: document.env ?? const <String, String>{},
      stdinTemplate: document.stdinTemplate ?? '{{prompt}}',
      timeout: _parseDuration(document.timeout ?? '10m'),
    );
  }

  static List<String> _normalizeArgs(Iterable<String> args) {
    return args
        .map((arg) => arg == '--json-output' ? '--json' : arg)
        .toList(growable: false);
  }
}

class NotificationConfig {
  NotificationConfig({
    required this.type,
    required this.enabled,
    required this.events,
    required this.webhookUrl,
    required this.username,
    required this.avatarUrl,
  });

  final NotificationType type;
  final bool enabled;
  final Set<NotificationEvent> events;
  final String? webhookUrl;
  final String? username;
  final String? avatarUrl;

  factory NotificationConfig.fromDocument(NotificationConfigDocument document) {
    final type = document.type;
    if (type == null) {
      throw const FormatException('Notification type is required.');
    }

    return NotificationConfig(
      type: type,
      enabled: document.enabled ?? true,
      events:
          (document.events ??
                  const <NotificationEvent>[NotificationEvent.replyPosted])
              .toSet(),
      webhookUrl: _expandOptionalEnvironmentString(document.webhookUrl),
      username: _expandOptionalEnvironmentString(document.username),
      avatarUrl: _expandOptionalEnvironmentString(document.avatarUrl),
    );
  }
}

class _IssueAssistantConfigResolver {
  const _IssueAssistantConfigResolver();

  IssueAssistantConfig resolve({
    required IssueAssistantConfig? base,
    required IssueAssistantConfigDocument? overlay,
  }) {
    final responders = overlay?.responders;
    final notifications = overlay?.notifications;
    return IssueAssistantConfig(
      enabled: overlay?.enabled ?? base?.enabled ?? true,
      eventSource: _resolveEventSource(
        base: base?.eventSource,
        overlay: overlay?.eventSource,
      ),
      maxConcurrentIssues: _resolvePositiveInt(
        value: overlay?.maxConcurrentIssues,
        fallback: base?.maxConcurrentIssues ?? 3,
        fieldName: 'maxConcurrentIssues',
      ),
      mentionTriggers:
          overlay?.mentionTriggers ?? base?.mentionTriggers ?? const <String>[],
      prompt: overlay?.prompt ?? base?.prompt ?? defaultIssueAssistantPrompt,
      responders: responders != null
          ? responders
                .map(CliResponderConfig.fromDocument)
                .toList(growable: false)
          : base?.responders ?? const <CliResponderConfig>[],
      capabilities: overlay?.capabilities != null
          ? overlay!.capabilities!.toSet()
          : base?.capabilities ??
                {
                  AssistantCapability.planning,
                  AssistantCapability.bugVerification,
                },
      notifications: notifications != null
          ? notifications
                .map(NotificationConfig.fromDocument)
                .toList(growable: false)
          : base?.notifications ?? const <NotificationConfig>[],
      commentTag:
          overlay?.commentTag ?? base?.commentTag ?? 'code-work-spawner',
      commentPrefixTemplate:
          overlay?.commentPrefixTemplate ??
          base?.commentPrefixTemplate ??
          defaultCommentPrefixTemplate,
      commentFooterTemplate:
          overlay?.commentFooterTemplate ??
          base?.commentFooterTemplate ??
          defaultCommentFooterTemplate,
    );
  }

  IssueEventSourceConfig _resolveEventSource({
    required IssueEventSourceConfig? base,
    required IssueAssistantEventSourceDocument? overlay,
  }) {
    final type =
        overlay?.type ?? base?.type ?? IssueAssistantEventSourceKind.ghPolling;
    if (_isPollingEventSource(type)) {
      if (overlay?.reconciliation != null ||
          overlay?.reconcileInterval != null) {
        throw FormatException(
          'Polling event sources do not support reconciliation settings.',
        );
      }
      final fallbackPollInterval = switch (base) {
        PollingIssueEventSourceConfig(:final pollInterval) => pollInterval,
        ChannelIssueEventSourceConfig(:final reconcileInterval) =>
          reconcileInterval,
        null => const Duration(seconds: 30),
      };
      return PollingIssueEventSourceConfig(
        type: type,
        pollInterval: overlay?.pollInterval != null
            ? _parseDuration(overlay!.pollInterval!)
            : fallbackPollInterval,
      );
    }

    final fallbackReconcileInterval = switch (base) {
      ChannelIssueEventSourceConfig(:final reconcileInterval) =>
        reconcileInterval,
      PollingIssueEventSourceConfig(:final pollInterval) => pollInterval,
      null => const Duration(seconds: 30),
    };
    return ChannelIssueEventSourceConfig(
      type: type,
      reconciliation:
          overlay?.reconciliation ??
          switch (base) {
            ChannelIssueEventSourceConfig(:final reconciliation) =>
              reconciliation,
            _ => IssueAssistantReconciliationKind.continuous,
          },
      reconcileInterval: overlay?.reconcileInterval != null
          ? _parseDuration(overlay!.reconcileInterval!)
          : overlay?.pollInterval != null
          ? _parseDuration(overlay!.pollInterval!)
          : fallbackReconcileInterval,
    );
  }
}

String _eventSourceConfigValue(IssueAssistantEventSourceKind value) {
  return switch (value) {
    IssueAssistantEventSourceKind.ghPolling => 'gh/polling',
    IssueAssistantEventSourceKind.teaPolling => 'tea/polling',
    IssueAssistantEventSourceKind.ghGosmee => 'gh/gosmee',
    IssueAssistantEventSourceKind.ghWebhookForward => 'gh/webhook-forward',
    IssueAssistantEventSourceKind.teaGosmee => 'tea/gosmee',
  };
}

bool _isPollingEventSource(IssueAssistantEventSourceKind value) {
  return switch (value) {
    IssueAssistantEventSourceKind.ghPolling => true,
    IssueAssistantEventSourceKind.teaPolling => true,
    IssueAssistantEventSourceKind.ghGosmee => false,
    IssueAssistantEventSourceKind.ghWebhookForward => false,
    IssueAssistantEventSourceKind.teaGosmee => false,
  };
}

String renderTemplate(String template, Map<String, String> values) {
  var output = template;
  for (final entry in values.entries) {
    output = output.replaceAll('{{${entry.key}}}', entry.value);
  }
  return output;
}

String encodePrettyJson(Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}

Object? _normalizeYamlNode(Object? value) {
  if (value is YamlMap) {
    return value.map(
      (key, dynamicValue) =>
          MapEntry(key.toString(), _normalizeYamlNode(dynamicValue)),
    );
  }
  if (value is YamlList) {
    return value.map(_normalizeYamlNode).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, dynamicValue) =>
          MapEntry(key.toString(), _normalizeYamlNode(dynamicValue)),
    );
  }
  if (value is List) {
    return value.map(_normalizeYamlNode).toList(growable: false);
  }
  return value;
}

Duration _parseDuration(String input) {
  final match = RegExp(r'^(\d+)([smhd])$').firstMatch(input.trim());
  if (match == null) {
    throw FormatException('Invalid duration: $input');
  }

  final value = int.parse(match.group(1)!);
  return switch (match.group(2)!) {
    's' => Duration(seconds: value),
    'm' => Duration(minutes: value),
    'h' => Duration(hours: value),
    'd' => Duration(days: value),
    _ => throw FormatException('Invalid duration unit: $input'),
  };
}

int _resolvePositiveInt({
  required int? value,
  required int fallback,
  required String fieldName,
}) {
  final resolved = value ?? fallback;
  if (resolved < 1) {
    throw FormatException(
      '$fieldName must be an integer greater than or equal to 1.',
    );
  }
  return resolved;
}

String _expandHome(String path) {
  if (!path.startsWith('~/')) {
    return p.normalize(p.absolute(path));
  }

  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw const FileSystemException('HOME is not set.');
  }
  return p.normalize(p.join(home, path.substring(2)));
}

String? _expandOptionalPath(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  return _expandHome(path);
}

String? _expandOptionalEnvironmentString(String? value) {
  if (value == null || value.isEmpty) {
    return value;
  }
  return value.replaceAllMapped(RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'), (
    match,
  ) {
    return Platform.environment[match.group(1)!] ?? '';
  });
}

void _assertCamelCaseConfigKeys(Map<String, dynamic> root) {
  _assertCamelCaseMap(root, scope: '');

  final defaults = root['defaults'];
  if (defaults is Map<String, dynamic>) {
    final issueAssistant = defaults['issueAssistant'];
    if (issueAssistant is Map<String, dynamic>) {
      _assertCamelCaseMap(issueAssistant, scope: 'defaults.issueAssistant');
      final eventSource = issueAssistant['eventSource'];
      if (eventSource is Map<String, dynamic>) {
        _assertCamelCaseMap(
          eventSource,
          scope: 'defaults.issueAssistant.eventSource',
        );
      }
      final responders = issueAssistant['responders'];
      if (responders is List) {
        for (final responder in responders) {
          if (responder is Map<String, dynamic>) {
            _assertCamelCaseMap(
              responder,
              scope: 'defaults.issueAssistant.responders',
            );
          }
        }
      }
      final notifications = issueAssistant['notifications'];
      if (notifications is List) {
        for (final notification in notifications) {
          if (notification is Map<String, dynamic>) {
            _assertCamelCaseMap(
              notification,
              scope: 'defaults.issueAssistant.notifications',
            );
          }
        }
      }
    }
  }

  final projects = root['projects'];
  if (projects is Map<String, dynamic>) {
    for (final entry in projects.entries) {
      final project = entry.value;
      if (project is! Map<String, dynamic>) {
        continue;
      }
      _assertCamelCaseMap(project, scope: 'projects.${entry.key}');
      final issueAssistant = project['issueAssistant'];
      if (issueAssistant is Map<String, dynamic>) {
        _assertCamelCaseMap(
          issueAssistant,
          scope: 'projects.${entry.key}.issueAssistant',
        );
        final eventSource = issueAssistant['eventSource'];
        if (eventSource is Map<String, dynamic>) {
          _assertCamelCaseMap(
            eventSource,
            scope: 'projects.${entry.key}.issueAssistant.eventSource',
          );
        }
        final responders = issueAssistant['responders'];
        if (responders is List) {
          for (final responder in responders) {
            if (responder is Map<String, dynamic>) {
              _assertCamelCaseMap(
                responder,
                scope: 'projects.${entry.key}.issueAssistant.responders',
              );
            }
          }
        }
        final notifications = issueAssistant['notifications'];
        if (notifications is List) {
          for (final notification in notifications) {
            if (notification is Map<String, dynamic>) {
              _assertCamelCaseMap(
                notification,
                scope: 'projects.${entry.key}.issueAssistant.notifications',
              );
            }
          }
        }
      }
    }
  }
}

void _normalizeLegacyEventSourceConfig(Map<String, dynamic> root) {
  void normalizeIssueAssistant(
    Map<String, dynamic> issueAssistant, {
    required IssueAssistantEventSourceKind? defaultType,
  }) {
    final rawEventSource = issueAssistant['eventSource'];
    Map<String, dynamic>? normalizedEventSource;

    if (rawEventSource is String) {
      normalizedEventSource = <String, dynamic>{'type': rawEventSource};
    } else if (rawEventSource is Map<String, dynamic>) {
      normalizedEventSource = Map<String, dynamic>.from(rawEventSource);
    } else if (rawEventSource == null) {
      if (issueAssistant.containsKey('pollInterval') ||
          issueAssistant.containsKey('reconciliation') ||
          issueAssistant.containsKey('reconcileInterval')) {
        normalizedEventSource = <String, dynamic>{};
      }
    }

    if (normalizedEventSource == null) {
      return;
    }

    if (defaultType != null && !normalizedEventSource.containsKey('type')) {
      normalizedEventSource['type'] = _eventSourceConfigValue(defaultType);
    }

    for (final field in [
      'pollInterval',
      'reconciliation',
      'reconcileInterval',
    ]) {
      if (issueAssistant.containsKey(field) &&
          !normalizedEventSource.containsKey(field)) {
        normalizedEventSource[field] = issueAssistant.remove(field);
      }
    }

    issueAssistant['eventSource'] = normalizedEventSource;
  }

  final defaults = root['defaults'];
  if (defaults is Map<String, dynamic>) {
    final issueAssistant = defaults['issueAssistant'];
    if (issueAssistant is Map<String, dynamic>) {
      normalizeIssueAssistant(
        issueAssistant,
        defaultType: IssueAssistantEventSourceKind.ghPolling,
      );
    }
  }

  final projects = root['projects'];
  if (projects is Map<String, dynamic>) {
    for (final entry in projects.entries) {
      final project = entry.value;
      if (project is! Map<String, dynamic>) {
        continue;
      }
      final issueAssistant = project['issueAssistant'];
      if (issueAssistant is! Map<String, dynamic>) {
        continue;
      }
      normalizeIssueAssistant(
        issueAssistant,
        defaultType: project['provider'] == 'gitea'
            ? IssueAssistantEventSourceKind.teaPolling
            : IssueAssistantEventSourceKind.ghPolling,
      );
    }
  }
}

void _assertCamelCaseMap(Map<String, dynamic> map, {required String scope}) {
  for (final key in map.keys) {
    if (key.contains('_')) {
      final qualified = scope.isEmpty ? key : '$scope.$key';
      throw FormatException('Unsupported config field: $qualified');
    }
  }
}

String _deriveSessionPrefix(String key) {
  if (key.contains('-')) {
    return key
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toLowerCase();
  }

  if (key.contains('_')) {
    return key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toLowerCase();
  }

  return key.substring(0, key.length < 3 ? key.length : 3).toLowerCase();
}

class _InitialConfigRenderer {
  String render(AppConfigDocument document) {
    final root = document.toJson();
    final defaultsSection = root.remove('defaults') as Map<String, dynamic>?;
    final projectsSection = root.remove('projects') as Map<String, dynamic>?;
    final assistant = document.defaults?.issueAssistant;

    return '''
# Starter config for code_work_spawner.
# Required fields are active. Optional settings are shown as commented examples.
#
# Update the sample repo, path, and responder command before running the app.

${_YamlEmitter().write(root)}

${_YamlEmitter().write({'defaults': defaultsSection})}

    # capabilities: ["planning", "bug_verification"]
    # commentTag: code-work-spawner
    # commentPrefixTemplate: |
${_commentBlock(defaultCommentPrefixTemplate, indent: '    #   ')}
    # commentFooterTemplate: |
${_commentBlock(defaultCommentFooterTemplate, indent: '    #   ')}
    # prompt: |
${_commentBlock(defaultIssueAssistantPrompt, indent: '    #   ')}
    # responders:
    #   - id: codex
    #     command: codex
    #     args: ["exec", "--json"]
    #     timeout: 10m
    #   - id: opencode
    #     command: opencode
    #     timeout: 10m
    # notifications:
    #   - type: discordWebhook
    #     enabled: true
    #     events: ["reply_posted", "responder_failed"]
    #     webhookUrl: \${CWS_DISCORD_WEBHOOK}
    #     username: code-work-spawner
    #   - type: desktop
    #     enabled: true
    #     events: ["mention_detected", "responder_failed"]

${_YamlEmitter().write({'projects': projectsSection})}

    # issueAssistant:
    #   enabled: ${assistant?.enabled ?? true}
    #   eventSource:
    #     type: gh/gosmee
    #     reconciliation: startup-only
    #     reconcileInterval: 30s
    #   mentionTriggers: ["@helper"]
    # sessionPrefix: sample
'''
        .trimRight();
  }

  String _commentBlock(String value, {required String indent}) {
    return value.split('\n').map((line) => '$indent$line').join('\n');
  }
}

class _YamlEmitter {
  String write(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    _writeMap(buffer, map, 0);
    return buffer.toString().trimRight();
  }

  void _writeMap(StringBuffer buffer, Map<String, dynamic> map, int indent) {
    final prefix = ' ' * indent;
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        buffer.writeln('$prefix${entry.key}:');
        _writeMap(buffer, value, indent + 2);
        continue;
      }
      if (value is List) {
        if (value.isEmpty) {
          buffer.writeln('$prefix${entry.key}: []');
          continue;
        }
        if (value.every((item) => item is! Map && item is! List)) {
          final rendered = value.map(_renderScalar).join(', ');
          buffer.writeln('$prefix${entry.key}: [$rendered]');
          continue;
        }
        buffer.writeln('$prefix${entry.key}:');
        _writeList(buffer, value, indent + 2);
        continue;
      }
      if (value is String && value.contains('\n')) {
        buffer.writeln('$prefix${entry.key}: |');
        for (final line in value.split('\n')) {
          buffer.writeln('${' ' * (indent + 2)}$line');
        }
        continue;
      }
      buffer.writeln('$prefix${entry.key}: ${_renderScalar(value)}');
    }
  }

  void _writeList(StringBuffer buffer, List<dynamic> values, int indent) {
    final prefix = ' ' * indent;
    for (final value in values) {
      if (value is Map<String, dynamic>) {
        final entries = value.entries.toList(growable: false);
        if (entries.isEmpty) {
          buffer.writeln('$prefix- {}');
          continue;
        }
        final first = entries.first;
        buffer.writeln(
          '$prefix- ${first.key}: ${_renderInlineValue(first.value)}',
        );
        if (entries.length > 1) {
          _writeMap(
            buffer,
            Map<String, dynamic>.fromEntries(entries.skip(1)),
            indent + 2,
          );
        }
        continue;
      }
      buffer.writeln('$prefix- ${_renderScalar(value)}');
    }
  }

  String _renderInlineValue(Object? value) {
    if (value is String && value.contains('\n')) {
      return '|';
    }
    if (value is List && value.every((item) => item is! Map && item is! List)) {
      return '[${value.map(_renderScalar).join(', ')}]';
    }
    return _renderScalar(value);
  }

  String _renderScalar(Object? value) {
    if (value is String) {
      if (value.isEmpty) {
        return '""';
      }
      if (RegExp(r'^[A-Za-z0-9_./{}\-]+$').hasMatch(value)) {
        return value;
      }
      return jsonEncode(value);
    }
    if (value is bool || value is num) {
      return value.toString();
    }
    if (value == null) {
      return 'null';
    }
    return jsonEncode(value);
  }
}
