import 'dart:io';

class GherkinValidationIssue {
  GherkinValidationIssue({
    required this.path,
    required this.line,
    required this.message,
  });

  final String path;
  final int line;
  final String message;

  @override
  String toString() => '$path:$line: $message';
}

class GherkinTestValidator {
  List<GherkinValidationIssue> validateDirectory(Directory testDirectory) {
    if (!testDirectory.existsSync()) {
      return const <GherkinValidationIssue>[];
    }

    final issues = <GherkinValidationIssue>[];
    final files =
        testDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('_test.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final file in files) {
      issues.addAll(validateFile(file));
    }
    return issues;
  }

  List<GherkinValidationIssue> validateFile(File file) {
    final lines = file.readAsLinesSync();
    final issues = <GherkinValidationIssue>[];
    var inMultilineString = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (_isInsideMultilineString(line, inMultilineString)) {
        inMultilineString = !inMultilineString;
        continue;
      }
      if (inMultilineString) {
        continue;
      }
      if (_isGroupDeclaration(line)) {
        issues.addAll(_validateGroup(file.path, lines, index));
      }
      if (_isTestDeclaration(line)) {
        issues.addAll(_validateTest(file.path, lines, index));
      }
    }

    return issues;
  }

  List<GherkinValidationIssue> _validateGroup(
    String path,
    List<String> lines,
    int declarationIndex,
  ) {
    final issues = <GherkinValidationIssue>[];
    final docBlock = _precedingDocBlock(lines, declarationIndex);
    if (docBlock.isEmpty) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message:
              'group(...) must be preceded by a Gherkin Feature doc block.',
        ),
      );
    } else {
      final content = docBlock.join('\n');
      if (!content.contains('```gherkin')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Feature doc block must use ```gherkin fencing.',
          ),
        );
      }
      if (!content.contains('Feature:')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Feature doc block must contain "Feature:".',
          ),
        );
      }
    }

    final runtimeName = _extractFirstStringArgument(lines[declarationIndex]);
    if (runtimeName != null && runtimeName.startsWith('Feature:')) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message: 'Runtime group name must not start with "Feature:".',
        ),
      );
    }

    return issues;
  }

  List<GherkinValidationIssue> _validateTest(
    String path,
    List<String> lines,
    int declarationIndex,
  ) {
    final issues = <GherkinValidationIssue>[];
    final docBlock = _precedingDocBlock(lines, declarationIndex);
    if (docBlock.isEmpty) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message:
              'test(...) must be preceded by a Gherkin Scenario doc block.',
        ),
      );
    } else {
      final content = docBlock.join('\n');
      if (!content.contains('```gherkin')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Scenario doc block must use ```gherkin fencing.',
          ),
        );
      }
      if (!content.contains('Scenario:')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Scenario doc block must contain "Scenario:".',
          ),
        );
      }
      if (!content.contains('Given ')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Scenario doc block must contain a Given step.',
          ),
        );
      }
      if (!content.contains('When ')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Scenario doc block must contain a When step.',
          ),
        );
      }
      if (!content.contains('Then ')) {
        issues.add(
          GherkinValidationIssue(
            path: path,
            line: declarationIndex + 1,
            message: 'Scenario doc block must contain a Then step.',
          ),
        );
      }
    }

    final runtimeName = _extractFirstStringArgument(lines[declarationIndex]);
    if (runtimeName != null && runtimeName.startsWith('Scenario:')) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message: 'Runtime test name must not start with "Scenario:".',
        ),
      );
    }

    final body = _extractTestBody(lines, declarationIndex);
    if (!body.contains('// Given')) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message: 'Test body must contain a "// Given" comment.',
        ),
      );
    }
    if (!body.contains('// When')) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message: 'Test body must contain a "// When" comment.',
        ),
      );
    }
    if (!body.contains('// Then')) {
      issues.add(
        GherkinValidationIssue(
          path: path,
          line: declarationIndex + 1,
          message: 'Test body must contain a "// Then" comment.',
        ),
      );
    }

    return issues;
  }

  List<String> _precedingDocBlock(List<String> lines, int declarationIndex) {
    final block = <String>[];
    var cursor = declarationIndex - 1;

    while (cursor >= 0 && lines[cursor].trim().isEmpty) {
      cursor--;
    }

    while (cursor >= 0 && lines[cursor].trimLeft().startsWith('///')) {
      block.insert(0, lines[cursor]);
      cursor--;
    }

    return block;
  }

  String _extractTestBody(List<String> lines, int declarationIndex) {
    final buffer = StringBuffer();
    var braceDepth = 0;
    var started = false;

    for (var index = declarationIndex; index < lines.length; index++) {
      final line = lines[index];
      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        if (char == '{') {
          braceDepth++;
          started = true;
        } else if (char == '}') {
          braceDepth--;
        }
      }

      if (started) {
        buffer.writeln(line);
      }

      if (started && braceDepth <= 0) {
        break;
      }
    }

    return buffer.toString();
  }

  String? _extractFirstStringArgument(String line) {
    final match = RegExp(r"(?:group|test)\(\s*'([^']*)'").firstMatch(line);
    return match?.group(1);
  }

  bool _isGroupDeclaration(String line) =>
      RegExp(r'^\s*group\(').hasMatch(line.trimLeft());

  bool _isTestDeclaration(String line) =>
      RegExp(r'^\s*test\(').hasMatch(line.trimLeft());

  bool _isInsideMultilineString(String line, bool currentlyInside) {
    final tripleSingle = "'''".allMatches(line).length;
    final tripleDouble = '"""'.allMatches(line).length;
    final toggles = tripleSingle + tripleDouble;
    if (toggles == 0) {
      return false;
    }

    if (!currentlyInside && toggles.isOdd) {
      return true;
    }

    if (currentlyInside && toggles.isOdd) {
      return true;
    }

    return false;
  }
}
