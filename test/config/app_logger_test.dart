import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: App logger environment configuration
  ///
  ///   As an operator running code_work_spawner
  ///   I want logger verbosity to be configurable through environment variables
  ///   So that I can increase or reduce log output without editing code
  /// ```
  group('AppLogger.resolveMinimumLevel', () {
    /// ```gherkin
    /// Scenario: Prefer the dedicated Code Work Spawner log level variable
    ///   Given both a generic log level and a Code Work Spawner log level are set
    ///   When resolving the app logger minimum level from the environment
    ///   Then the dedicated Code Work Spawner value takes precedence
    /// ```
    test('Prefer the dedicated Code Work Spawner log level variable', () {
      // Given both a generic log level and a Code Work Spawner log level are set.
      const environment = <String, String>{
        'LOG_LEVEL': 'error',
        'CWS_LOG_LEVEL': 'debug',
      };

      // When resolving the app logger minimum level from the environment.
      final level = AppLogger.resolveMinimumLevel(environment);

      // Then the dedicated Code Work Spawner value takes precedence.
      expect(level, AppLogLevel.debug);
    });

    /// ```gherkin
    /// Scenario: Fall back when the configured log level is invalid
    ///   Given a Code Work Spawner log level that is not recognized
    ///   When resolving the app logger minimum level from the environment
    ///   Then the logger falls back to the provided default level
    /// ```
    test('Fall back when the configured log level is invalid', () {
      // Given a Code Work Spawner log level that is not recognized.
      const environment = <String, String>{'CWS_LOG_LEVEL': 'verbose'};

      // When resolving the app logger minimum level from the environment.
      final level = AppLogger.resolveMinimumLevel(
        environment,
        fallback: AppLogLevel.warning,
      );

      // Then the logger falls back to the provided default level.
      expect(level, AppLogLevel.warning);
    });
  });
}
