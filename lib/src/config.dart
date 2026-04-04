import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'comment_templates.dart';

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

    final root = _asMap(yaml);
    final dialect = _detectDialect(root);
    return switch (dialect) {
      _ConfigDialect.current => _loadCurrentConfig(path, root),
      _ConfigDialect.aoSubset => _loadAoSubsetConfig(path, root),
    };
  }

  static AppConfig _loadCurrentConfig(String path, Map<String, dynamic> root) {
    _validateKeys(
      scope: 'config',
      map: root,
      allowed: {'defaults', 'projects', 'dataDir', 'worktreeDir'},
    );
    final defaultsMap = _asMap(root['defaults']);
    final defaultAssistantMap = _asMap(defaultsMap['issueAssistant']);
    final defaults = IssueAssistantConfig.fromMap(defaultAssistantMap);
    final projects = _loadProjects(
      root['projects'],
      defaultAssistant: defaults,
      defaultAssistantMap: defaultAssistantMap,
    );

    return AppConfig(
      configPath: p.normalize(p.absolute(path)),
      dataDir: _expandOptionalPath(root['dataDir']?.toString()),
      worktreeDir: _expandOptionalPath(root['worktreeDir']?.toString()),
      defaults: defaults,
      projects: projects,
    );
  }

  static AppConfig _loadAoSubsetConfig(String path, Map<String, dynamic> root) {
    _validateKeys(
      scope: 'config',
      map: root,
      allowed: {'defaults', 'projects', 'dataDir', 'worktreeDir'},
    );

    final defaultsMap = _asMap(root['defaults']);
    _validateKeys(
      scope: 'defaults',
      map: defaultsMap,
      allowed: {
        'defaultBranch',
        'default_branch',
        'sessionPrefix',
        'session_prefix',
      },
    );

    final defaultAssistantMap = <String, dynamic>{};
    final defaults = IssueAssistantConfig.fromMap(defaultAssistantMap);
    final projects = _loadAoSubsetProjects(
      root['projects'],
      defaultsMap: defaultsMap,
      defaultAssistant: defaults,
      defaultAssistantMap: defaultAssistantMap,
    );

    return AppConfig(
      configPath: p.normalize(p.absolute(path)),
      dataDir: _expandOptionalPath(root['dataDir']?.toString()),
      worktreeDir: _expandOptionalPath(root['worktreeDir']?.toString()),
      defaults: defaults,
      projects: projects,
    );
  }

  static Map<String, ProjectConfig> _loadProjects(
    Object? projectsNode, {
    required IssueAssistantConfig defaultAssistant,
    required Map<String, dynamic> defaultAssistantMap,
  }) {
    if (projectsNode is! YamlMap || projectsNode.isEmpty) {
      throw const FormatException('projects must be a non-empty map.');
    }

    final projects = <String, ProjectConfig>{};
    for (final entry in projectsNode.entries) {
      final key = entry.key.toString();
      final value = _asMap(entry.value);
      projects[key] = ProjectConfig.fromMap(
        key: key,
        map: value,
        defaultAssistant: defaultAssistant,
        defaultAssistantMap: defaultAssistantMap,
      );
    }
    return projects;
  }

  static Map<String, ProjectConfig> _loadAoSubsetProjects(
    Object? projectsNode, {
    required Map<String, dynamic> defaultsMap,
    required IssueAssistantConfig defaultAssistant,
    required Map<String, dynamic> defaultAssistantMap,
  }) {
    if (projectsNode is! YamlMap || projectsNode.isEmpty) {
      throw const FormatException('projects must be a non-empty map.');
    }

    final projects = <String, ProjectConfig>{};
    for (final entry in projectsNode.entries) {
      final key = entry.key.toString();
      final value = _asMap(entry.value);
      _validateKeys(
        scope: 'projects.$key',
        map: value,
        allowed: {
          'repo',
          'path',
          'defaultBranch',
          'default_branch',
          'sessionPrefix',
          'session_prefix',
        },
      );
      final merged = <String, dynamic>{...defaultsMap, ...value};
      projects[key] = ProjectConfig.fromMap(
        key: key,
        map: merged,
        defaultAssistant: defaultAssistant,
        defaultAssistantMap: defaultAssistantMap,
      );
    }
    return projects;
  }

  static _ConfigDialect _detectDialect(Map<String, dynamic> root) {
    final defaultsMap = _asMap(root['defaults']);
    if (defaultsMap.containsKey('issueAssistant')) {
      return _ConfigDialect.current;
    }
    return _ConfigDialect.aoSubset;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value == null) {
      return <String, dynamic>{};
    }

    if (value is YamlMap) {
      return value.map(
        (key, dynamicValue) => MapEntry(key.toString(), dynamicValue),
      );
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    throw FormatException('Expected map, got ${value.runtimeType}.');
  }

  static void _validateKeys({
    required String scope,
    required Map<String, dynamic> map,
    required Set<String> allowed,
  }) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unsupported config field: $scope.$key');
      }
    }
  }
}

class ProjectConfig {
  ProjectConfig({
    required this.key,
    required this.repo,
    required this.repoSlug,
    required this.path,
    required this.defaultBranch,
    required this.sessionPrefix,
    required this.issueAssistant,
  });

  final String key;
  final String repo;
  final RepositorySlug repoSlug;
  final String path;
  final String defaultBranch;
  final String sessionPrefix;
  final IssueAssistantConfig issueAssistant;

  factory ProjectConfig.fromMap({
    required String key,
    required Map<String, dynamic> map,
    required IssueAssistantConfig defaultAssistant,
    required Map<String, dynamic> defaultAssistantMap,
  }) {
    final assistantMap = AppConfig._asMap(map['issueAssistant']);
    final mergedAssistantMap = <String, dynamic>{
      ...defaultAssistantMap,
      ...assistantMap,
    };
    final repo = map['repo']?.toString() ?? _missing('projects.$key.repo');
    return ProjectConfig(
      key: key,
      repo: repo,
      repoSlug: _parseRepositorySlug(repo, field: 'projects.$key.repo'),
      path: _expandHome(
        map['path']?.toString() ?? _missing('projects.$key.path'),
      ),
      defaultBranch:
          map['defaultBranch']?.toString() ??
          map['default_branch']?.toString() ??
          'main',
      sessionPrefix:
          map['sessionPrefix']?.toString() ??
          map['session_prefix']?.toString() ??
          _deriveSessionPrefix(key),
      issueAssistant: assistantMap.isEmpty
          ? defaultAssistant
          : IssueAssistantConfig.fromMap(mergedAssistantMap),
    );
  }

  static String _missing(String field) {
    throw FormatException('Missing required config field: $field');
  }

  static RepositorySlug _parseRepositorySlug(
    String value, {
    required String field,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException('Missing required config field: $field');
    }

    final parts = trimmed.split('/');
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
    required this.pollInterval,
    required this.maxConcurrentIssues,
    required this.mentionTriggers,
    required this.prompt,
    required this.responders,
    required this.capabilities,
    required this.commentTag,
    required this.commentPrefixTemplate,
    required this.commentFooterTemplate,
  });

  final bool enabled;
  final Duration pollInterval;
  final int maxConcurrentIssues;
  final List<String> mentionTriggers;
  final String prompt;
  final List<CliResponderConfig> responders;
  final Set<AssistantCapability> capabilities;
  final String commentTag;
  final String commentPrefixTemplate;
  final String commentFooterTemplate;

  factory IssueAssistantConfig.fromMap(Map<String, dynamic> map) {
    final respondersNode = map['responders'];
    final responders = respondersNode is List
        ? respondersNode
              .map((item) => CliResponderConfig.fromMap(AppConfig._asMap(item)))
              .toList(growable: false)
        : const <CliResponderConfig>[];

    final capabilitiesNode = map['capabilities'];
    final capabilities = capabilitiesNode is List
        ? capabilitiesNode
              .map((item) => AssistantCapability.parse(item.toString()))
              .toSet()
        : {AssistantCapability.planning, AssistantCapability.bugVerification};
    final maxConcurrentIssues = _parsePositiveInt(
      map['maxConcurrentIssues'],
      fieldName: 'maxConcurrentIssues',
      defaultValue: 3,
    );

    return IssueAssistantConfig(
      enabled: map['enabled'] as bool? ?? true,
      pollInterval: _parseDuration(map['pollInterval']?.toString() ?? '30s'),
      maxConcurrentIssues: maxConcurrentIssues,
      mentionTriggers:
          (map['mentionTriggers'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
      prompt: map['prompt']?.toString() ?? _defaultPrompt,
      responders: responders,
      capabilities: capabilities,
      commentTag: map['commentTag']?.toString() ?? 'code-work-spawner',
      commentPrefixTemplate:
          map['commentPrefixTemplate']?.toString() ??
          defaultCommentPrefixTemplate,
      commentFooterTemplate:
          map['commentFooterTemplate']?.toString() ??
          defaultCommentFooterTemplate,
    );
  }
  static Duration _parseDuration(String input) {
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

  static int _parsePositiveInt(
    Object? value, {
    required String fieldName,
    required int defaultValue,
  }) {
    if (value == null) {
      return defaultValue;
    }
    final parsed = int.tryParse(value.toString());
    if (parsed == null || parsed < 1) {
      throw FormatException(
        '$fieldName must be an integer greater than or equal to 1.',
      );
    }
    return parsed;
  }

  static const String _defaultPrompt = '''
You are a GitHub issue thread assistant.

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

  factory CliResponderConfig.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final command = map['command']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Responder id is required.');
    }
    if (command == null || command.isEmpty) {
      throw FormatException('Responder "$id" must define command.');
    }

    final args = _normalizeArgs(
      (map['args'] as List?)?.map((item) => item.toString()) ??
          const <String>[],
    );
    final env = AppConfig._asMap(
      map['env'],
    ).map((key, value) => MapEntry(key, value.toString()));

    return CliResponderConfig(
      id: id,
      command: command,
      args: args,
      env: env,
      stdinTemplate: map['stdinTemplate']?.toString() ?? '{{prompt}}',
      timeout: IssueAssistantConfig._parseDuration(
        map['timeout']?.toString() ?? '10m',
      ),
    );
  }

  static List<String> _normalizeArgs(Iterable<String> args) {
    return args
        .map((arg) => arg == '--json-output' ? '--json' : arg)
        .toList(growable: false);
  }
}

enum AssistantCapability {
  planning,
  bugVerification;

  static AssistantCapability parse(String input) {
    return switch (input) {
      'planning' => AssistantCapability.planning,
      'bugVerification' ||
      'bug_verification' => AssistantCapability.bugVerification,
      _ => throw FormatException('Unsupported capability: $input'),
    };
  }
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

enum _ConfigDialect { current, aoSubset }
