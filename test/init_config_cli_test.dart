import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    /// Scenario: Print the starter config to stdout
    ///   Given the CLI is executed with the init-config command
    ///   When the process completes successfully
    ///   Then stdout contains the starter config content
    ///   And the printed config is valid when written to disk and loaded
    /// ```
    test('Print the starter config to stdout', () async {
      // Given the CLI is executed with the init-config command.
      final sandbox = await Directory.systemTemp.createTemp('cws-cli-stdout-');
      final configFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/code_work_spawner.dart',
        'init-config',
      ], workingDirectory: Directory.current.path);

      // When the process completes successfully.
      expect(result.exitCode, 0, reason: '${result.stderr}');

      // Then stdout contains the starter config content.
      final stdoutText = result.stdout as String;
      expect(stdoutText, contains('dataDir:'));
      expect(stdoutText, contains('# responders:'));
      expect(stdoutText, contains('# notifications:'));
      expect(stdoutText, contains(r'#     webhookUrl: ${CWS_DISCORD_WEBHOOK}'));
      expect(stdoutText, contains('projects:'));

      // And the printed config is valid when written to disk and loaded.
      await configFile.writeAsString(stdoutText);
      final config = await AppConfig.load(configFile.path);
      expect(config.projects['sample'], isNotNull);
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
      final outputFile = File(p.join(sandbox.path, 'agent-orchestrator.yaml'));
      await outputFile.writeAsString('original');

      // When the CLI writes without the force flag and then with the force flag.
      final withoutForce = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/code_work_spawner.dart',
        'init-config',
        '--output',
        outputFile.path,
      ], workingDirectory: Directory.current.path);
      final withForce = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/code_work_spawner.dart',
        'init-config',
        '--output',
        outputFile.path,
        '--force',
      ], workingDirectory: Directory.current.path);

      // Then the first run fails with an overwrite error.
      expect(withoutForce.exitCode, 2);
      expect(
        withoutForce.stderr as String,
        contains('Refusing to overwrite existing file'),
      );

      // And the forced run replaces the file with a valid starter config.
      expect(withForce.exitCode, 0, reason: '${withForce.stderr}');
      final contents = await outputFile.readAsString();
      expect(contents, contains('defaults:'));
      expect(contents, contains('projects:'));
      final config = await AppConfig.load(outputFile.path);
      expect(config.projects['sample'], isNotNull);
    });
  });
}
