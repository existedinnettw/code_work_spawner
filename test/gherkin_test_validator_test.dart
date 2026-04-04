import 'dart:io';

import 'package:code_work_spawner/src/gherkin_test_validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: Gherkin test validator
  ///
  ///   As a maintainer of the repository
  ///   I want test files to be validated against the required Gherkin comment format
  ///   So that future tests stay consistent and reviewable
  /// ```
  group('GherkinTestValidator', () {
    /// ```gherkin
    /// Scenario: Accept a correctly formatted test file
    ///   Given a Dart test file that follows the required Feature and Scenario doc-comment structure
    ///   When the validator checks that file
    ///   Then it reports no validation issues
    /// ```
    test('Accept a correctly formatted test file', () async {
      // Given a Dart test file that follows the required Feature and Scenario doc-comment structure.
      final tempDir = await Directory.systemTemp.createTemp('gherkin-good-');
      final testFile = File(p.join(tempDir.path, 'good_test.dart'));
      await testFile.writeAsString(_goodTestFile);
      final validator = GherkinTestValidator();

      // When the validator checks that file.
      final issues = validator.validateFile(testFile);

      // Then it reports no validation issues.
      expect(issues, isEmpty);
    });

    /// ```gherkin
    /// Scenario: Reject a test file that does not follow the required format
    ///   Given a Dart test file that uses plain test declarations without the required Gherkin doc comments
    ///   When the validator checks that file
    ///   Then it reports validation issues for the missing structure
    /// ```
    test('Reject a test file that does not follow the required format', () async {
      // Given a Dart test file that uses plain test declarations without the required Gherkin doc comments.
      final tempDir = await Directory.systemTemp.createTemp('gherkin-bad-');
      final testFile = File(p.join(tempDir.path, 'bad_test.dart'));
      await testFile.writeAsString(_badTestFile);
      final validator = GherkinTestValidator();

      // When the validator checks that file.
      final issues = validator.validateFile(testFile);

      // Then it reports validation issues for the missing structure.
      expect(issues, isNotEmpty);
      expect(
        issues.map((issue) => issue.message),
        contains('group(...) must be preceded by a Gherkin Feature doc block.'),
      );
      expect(
        issues.map((issue) => issue.message),
        contains('test(...) must be preceded by a Gherkin Scenario doc block.'),
      );
    });
  });
}

const String _goodTestFile = r'''
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: Example feature
  ///
  ///   As a user
  ///   I want readable tests
  ///   So that I can understand their behavior quickly
  /// ```
  group('ExampleGroup', () {
    /// ```gherkin
    /// Scenario: Run a simple assertion
    ///   Given a valid example
    ///   When the test is executed
    ///   Then the assertion succeeds
    /// ```
    test('Run a simple assertion', () {
      // Given a valid example.
      final value = 1;

      // When the test is executed.
      final result = value + 1;

      // Then the assertion succeeds.
      expect(result, 2);
    });
  });
}
''';

const String _badTestFile = r'''
import 'package:test/test.dart';

void main() {
  group('Feature: Wrong', () {
    test('Scenario: Wrong', () {
      expect(1 + 1, 2);
    });
  });
}
''';
