import 'dart:io';

import 'package:code_work_spawner/src/gherkin_test_validator.dart';

void main() {
  final validator = GherkinTestValidator();
  final issues = validator.validateDirectory(Directory('test'));

  if (issues.isEmpty) {
    stdout.writeln('Gherkin test format validation passed.');
    return;
  }

  stderr.writeln('Gherkin test format validation failed:');
  for (final issue in issues) {
    stderr.writeln('- $issue');
  }
  exitCode = 1;
}
