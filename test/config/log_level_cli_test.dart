import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:test/test.dart';

import '../support/cli_utils.dart';

void main() {
  /// ```gherkin
  /// Feature: CLI log level option
  ///
  ///   As an operator running code_work_spawner
  ///   I want to configure log verbosity with a CLI flag
  ///   So that I can easily collect the right level of diagnostics
  /// ```
  group('code_work_spawner --log-level', () {
    setUp(AppEnvironment.resetForTest);

    tearDown(() {
      AppEnvironment.resetForTest();
      AppLogger.configure(minimumLevel: AppLogLevel.info, useColors: false);
    });

    /// ```gherkin
    /// Scenario: Parse a valid log level from the CLI
    ///   Given the operator passes --log-level WARN
    ///   When the CLI argument parser initializes logging
    ///   Then the configured minimum level is warning
    /// ```
    test('Parse a valid log level from the CLI', () async {
      // Given the operator passes --log-level WARN.
      final result = await runCli(['--log-level', 'WARN', '--help']);

      // When the CLI argument parser initializes logging.
      final minimumLevel = AppLogger.minimumLevel;

      // Then the configured minimum level is warning.
      expect(result.exitCode, 0);
      expect(minimumLevel, AppLogLevel.warning);
    });

    /// ```gherkin
    /// Scenario: Reject an invalid CLI log level
    ///   Given the operator passes --log-level verbose
    ///   When the CLI validates the value
    ///   Then the command exits with a non-zero status and prints allowed values
    /// ```
    test('Reject an invalid CLI log level', () async {
      // Given the operator passes --log-level verbose.
      final result = await runCli(['--log-level', 'verbose']);

      // When the CLI validates the value.
      final output = result.stdout;

      // Then the command exits with a non-zero status and prints allowed values.
      expect(result.exitCode, isNonZero);
      expect(output, contains('Invalid value for --log-level "verbose".'));
      expect(
        output,
        contains('Allowed values: trace, debug, info, warn, error.'),
      );
    });

    /// ```gherkin
    /// Scenario: CLI log level overrides environment variables
    ///   Given LOG_LEVEL is set to error in the environment
    ///   When the operator passes --log-level debug
    ///   Then the minimum logging level is debug
    /// ```
    test('CLI log level overrides environment variables', () async {
      // Given LOG_LEVEL is set to error in the environment.
      AppEnvironment.resetForTest(const <String, String>{'LOG_LEVEL': 'error'});

      // When the operator passes --log-level debug.
      final result = await runCli(['--log-level', 'debug', '--help']);

      // Then the minimum logging level is debug.
      expect(result.exitCode, 0);
      expect(AppLogger.minimumLevel, AppLogLevel.debug);
    });

    /// ```gherkin
    /// Scenario: Default log level falls back to info
    ///   Given no CLI or environment log level is configured
    ///   When the CLI initializes logging
    ///   Then the minimum logging level is info
    /// ```
    test('Default log level falls back to info', () async {
      // Given no CLI or environment log level is configured.
      AppEnvironment.resetForTest(const <String, String>{});

      // When the CLI initializes logging.
      final result = await runCli(['--help']);

      // Then the minimum logging level is info.
      expect(result.exitCode, 0);
      expect(AppLogger.minimumLevel, AppLogLevel.info);
    });
  });
}
