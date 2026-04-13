import 'dart:io';
import 'dart:convert';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../test_support.dart';

void expectEventSourceUnderIssueTrackerBlock(String yaml) {
  final lines = const LineSplitter().convert(yaml);
  final issueTrackerIndex = lines.indexWhere(
    (line) => RegExp(r'^\s*issueTracker:\s*$').hasMatch(line),
  );
  expect(
    issueTrackerIndex,
    isNonNegative,
    reason: 'Expected an issueTracker block in the emitted config.',
  );

  final issueTrackerIndent = _leadingSpaces(lines[issueTrackerIndex]);
  var foundNestedEventSource = false;

  for (var index = issueTrackerIndex + 1; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      continue;
    }
    final indent = _leadingSpaces(line);
    if (indent <= issueTrackerIndent) {
      break;
    }
    if (RegExp(r'^\s*eventSource:\s*$').hasMatch(line)) {
      foundNestedEventSource = true;
      break;
    }
  }

  expect(
    foundNestedEventSource,
    isTrue,
    reason: 'Expected eventSource to be nested under issueTracker.',
  );
}

int _leadingSpaces(String value) => value.length - value.trimLeft().length;

Map<String, dynamic> parseYamlToMap(String yaml) {
  final decoded = loadYaml(yaml);
  if (decoded is! YamlMap) {
    throw const FormatException('Expected YAML root map.');
  }
  return _normalizeYamlNode(decoded) as Map<String, dynamic>;
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

void main() {
  /// ```gherkin
  /// Feature: Init-config CLI
  ///
  ///   As a maintainer setting up code_work_spawner
  ///   I want a starter config command that can print or write a valid template
  ///   So that I can bootstrap configuration without reading the code first
  /// ```
  group('code_work_spawner init-config', () {
    /// ```gherkin
    /// Scenario: Show init-config in top-level help
    ///   Given the CLI is executed with the top-level help flag
    ///   When the process completes successfully
    ///   Then stdout lists the init-config command in the available commands section
    /// ```
    test('Show init-config in top-level help', () async {
      // Given the CLI is executed with the top-level help flag.
      final result = await runCli(['--help']);

      // When the process completes successfully.
      expect(result.exitCode, 0, reason: result.stderr);

      // Then stdout lists the init-config command in the available commands section.
      expect(result.stdout, contains('Available commands:'));
      expect(result.stdout, contains('init-config'));
      expect(result.stdout, contains('--glab-command'));
      expect(result.stdout, contains('--gosmee-command'));
    });

    /// ```gherkin
    /// Scenario: Print the starter config to stdout
    ///   Given the CLI is executed with the init-config command
    ///   When the process completes successfully
    ///   Then stdout contains the starter config content
    ///   And the printed config is valid when written to disk and loaded
    /// ```
    test('Print the starter config to stdout', () async {
      // Given the CLI is executed with the init-config command.
      final sandbox = await Directory.systemTemp.createTemp('cws-cli-stdout-');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      final result = await runCli(['init-config']);

      // When the process completes successfully.
      expect(result.exitCode, 0, reason: result.stderr);

      // Then stdout contains the starter config content.
      expect(result.stdout, contains('dataDir:'));
      expect(result.stdout, contains('# responders:'));
      expect(result.stdout, contains('# notifications:'));
      expect(
        result.stdout,
        contains(r'#     webhookUrl: ${CWS_DISCORD_WEBHOOK}'),
      );
      expect(result.stdout, contains('# maxResponsesAfterHuman: 1'));
      expect(result.stdout, contains('#   - type: desktop'));
      expect(result.stdout, contains('issueTracker:'));
      expect(result.stdout, contains('provider: github'));
      expectEventSourceUnderIssueTrackerBlock(result.stdout);
      expect(result.stdout, contains('scm:'));
      expect(result.stdout, contains('projects:'));

      final root = parseYamlToMap(result.stdout);
      final project =
          (root['projects'] as Map<String, dynamic>)['sample']
              as Map<String, dynamic>;
      final issueTracker = project['issueTracker'] as Map<String, dynamic>;
      expect(issueTracker['eventSource'], isA<Map<String, dynamic>>());
      final defaults = root['defaults'] as Map<String, dynamic>;
      final issueAssistant = defaults['issueAssistant'] as Map<String, dynamic>;
      expect(issueAssistant.containsKey('eventSource'), isFalse);

      // And the printed config is valid when written to disk and loaded.
      await configFile.writeAsString(result.stdout);
      final config = await AppConfig.load(configFile.path);
      expect(config.projects['sample'], isNotNull);
      expect(config.defaults.maxResponsesAfterHuman, 1);
    });

    /// ```gherkin
    /// Scenario: Refuse overwrite unless force is provided
    ///   Given an existing output file for the init-config command
    ///   When the CLI writes without the force flag and then with the force flag
    ///   Then the first run fails with an overwrite error
    ///   And the forced run replaces the file with a valid starter config
    /// ```
    test('Refuse overwrite unless force is provided', () async {
      // Given an existing output file for the init-config command.
      final sandbox = await Directory.systemTemp.createTemp('cws-cli-force-');
      final outputFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await outputFile.writeAsString('original');

      // When the CLI writes without the force flag and then with the force flag.
      final withoutForce = await runCli([
        'init-config',
        '--output',
        outputFile.path,
      ]);
      final withForce = await runCli([
        'init-config',
        '--output',
        outputFile.path,
        '--force',
      ]);

      // Then the first run fails with an overwrite error.
      expect(withoutForce.exitCode, 2);
      expect(
        withoutForce.stderr,
        contains('Refusing to overwrite existing file'),
      );

      // And the forced run replaces the file with a valid starter config.
      expect(withForce.exitCode, 0, reason: withForce.stderr);
      final contents = await outputFile.readAsString();
      expect(contents, contains('defaults:'));
      expect(contents, contains('issueTracker:'));
      expect(contents, contains('provider: github'));
      expectEventSourceUnderIssueTrackerBlock(contents);
      expect(contents, contains('# maxResponsesAfterHuman: 1'));
      expect(contents, contains('scm:'));
      expect(contents, contains('projects:'));

      final root = parseYamlToMap(contents);
      final project =
          (root['projects'] as Map<String, dynamic>)['sample']
              as Map<String, dynamic>;
      final issueTracker = project['issueTracker'] as Map<String, dynamic>;
      expect(issueTracker['eventSource'], isA<Map<String, dynamic>>());
      final defaults = root['defaults'] as Map<String, dynamic>;
      final issueAssistant = defaults['issueAssistant'] as Map<String, dynamic>;
      expect(issueAssistant.containsKey('eventSource'), isFalse);
      final config = await AppConfig.load(outputFile.path);
      expect(config.projects['sample'], isNotNull);
      expect(config.defaults.maxResponsesAfterHuman, 1);
    });
  });
}
