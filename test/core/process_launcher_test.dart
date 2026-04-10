import 'dart:io';

import 'package:code_work_spawner/src/core/process_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: Process launcher command resolution
  ///
  ///   As a maintainer running the app on Windows
  ///   I want native executables to avoid unnecessary shell wrappers
  ///   So that tracker CLIs do not hang before returning their output
  /// ```
  group('resolveExternalCommandForCurrentPlatform', () {
    /// ```gherkin
    /// Scenario: Execute Windows native executables directly
    ///   Given a Windows executable path for a native CLI
    ///   When the process launcher resolves the command
    ///   Then it keeps the original executable path
    ///   And it does not force the command to run in a shell
    /// ```
    test('Execute Windows native executables directly', () {
      // Given a Windows executable path for a native CLI.
      const executable = r'C:\Users\bensung\scoop\shims\tea.exe';

      // When the process launcher resolves the command.
      final resolved = resolveExternalCommandForCurrentPlatform(
        executable,
        const <String>['--version'],
        isWindows: true,
      );

      // Then it keeps the original executable path.
      expect(resolved.executable, executable);

      // And it does not force the command to run in a shell.
      expect(resolved.runInShell, isFalse);
      expect(resolved.usesBashShim, isFalse);
    });

    /// ```gherkin
    /// Scenario: Keep Windows batch files on the shell path
    ///   Given a Windows command script path
    ///   When the process launcher resolves the command
    ///   Then it leaves the script path unchanged
    ///   And it marks the command to run in a shell
    /// ```
    test('Keep Windows batch files on the shell path', () {
      // Given a Windows command script path.
      const executable = r'C:\tools\helper.cmd';

      // When the process launcher resolves the command.
      final resolved = resolveExternalCommandForCurrentPlatform(
        executable,
        const <String>['sync'],
        isWindows: true,
      );

      // Then it leaves the script path unchanged.
      expect(resolved.executable, executable);

      // And it marks the command to run in a shell.
      expect(resolved.runInShell, isTrue);
      expect(resolved.usesBashShim, isFalse);
    });

    /// ```gherkin
    /// Scenario: Wrap local extensionless scripts through WSL bash on Windows
    ///   Given a local extensionless script file on Windows
    ///   When the process launcher resolves the command
    ///   Then it swaps the executable to wsl.exe
    ///   And it forwards the script path as a bash path
    /// ```
    test(
      'Wrap local extensionless scripts through WSL bash on Windows',
      () async {
        // Given a local extensionless script file on Windows.
        final sandbox = await Directory.systemTemp.createTemp(
          'cws-process-launcher-',
        );
        final script = File(p.join(sandbox.path, 'fake-tea'));
        await script.writeAsString('#!/usr/bin/env bash\nprintf \'[]\\n\'\n');

        try {
          // When the process launcher resolves the command.
          final resolved = resolveExternalCommandForCurrentPlatform(
            script.path,
            const <String>['api'],
            isWindows: true,
          );

          // Then it swaps the executable to wsl.exe.
          expect(resolved.executable, 'wsl.exe');
          expect(resolved.usesBashShim, isTrue);

          // And it forwards the script path as a bash path.
          expect(resolved.runInShell, isFalse);
          expect(resolved.arguments.first, '--exec');
          expect(resolved.arguments[1], 'bash');
          expect(resolved.arguments[2], startsWith('/mnt/'));
        } finally {
          await sandbox.delete(recursive: true);
        }
      },
    );
  });
}
