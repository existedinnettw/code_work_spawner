import 'dart:convert';
import 'dart:io';

import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'comment_templates.dart';
import 'config_schema.dart';
export 'config_schema.dart' show AssistantCapability;

const String defaultIssueAssistantPrompt = '''
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
          pollInterval: '30s',
          maxConcurrentIssues: 3,
          mentionTriggers: const ['@codex', '@helper'],
        ),
      ),
      projects: {
        'sample': ProjectConfigDocument(
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

    return ProjectConfig(
      key: key,
      repo: repo,
      repoSlug: _parseRepositorySlug(repo, field: 'projects.$key.repo'),
      path: _expandHome(path),
      defaultBranch: document.defaultBranch ?? 'main',
      sessionPrefix: document.sessionPrefix ?? _deriveSessionPrefix(key),
      issueAssistant: defaultAssistant.merge(document.issueAssistant),
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

class _IssueAssistantConfigResolver {
  const _IssueAssistantConfigResolver();

  IssueAssistantConfig resolve({
    required IssueAssistantConfig? base,
    required IssueAssistantConfigDocument? overlay,
  }) {
    final responders = overlay?.responders;
    return IssueAssistantConfig(
      enabled: overlay?.enabled ?? base?.enabled ?? true,
      pollInterval: overlay?.pollInterval != null
          ? _parseDuration(overlay!.pollInterval!)
          : base?.pollInterval ?? const Duration(seconds: 30),
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

void _assertCamelCaseConfigKeys(Map<String, dynamic> root) {
  _assertCamelCaseMap(root, scope: '');

  final defaults = root['defaults'];
  if (defaults is Map<String, dynamic>) {
    final issueAssistant = defaults['issueAssistant'];
    if (issueAssistant is Map<String, dynamic>) {
      _assertCamelCaseMap(issueAssistant, scope: 'defaults.issueAssistant');
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
      }
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

${_YamlEmitter().write({'projects': projectsSection})}

    # issueAssistant:
    #   enabled: ${assistant?.enabled ?? true}
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
