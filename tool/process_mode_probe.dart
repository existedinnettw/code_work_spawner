import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:code_work_spawner/src/core/process_launcher.dart';

// The file is used to probe different modes of running external processes in Dart

// Usage example:
// Running command with Process.runSync: tea api -X GET "repos/bkinnightskytw/code_work_spawner/issues?state=open&limit=100&page=1&since=2026-04-10T06%3A06%3A25.000Z" -r bkinnightskytw/code_work_spawner
// `dart run .\tool\process_mode_probe.dart --mode process-run-sync --command tea --arg api --arg -X --arg GET --arg '"repos/bkinnightskytw/code_work_spawner/issues?state=open&limit=100&page=1"' --arg -r --arg 'bkinnightskytw/code_work_spawner'`
// `dart run .\tool\process_mode_probe.dart --mode process-run-sync --command tea --arg login --arg default`
// Aware that `tea` has known severe issues on Windows due to lipgloss/v2 query console color.
//

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'command',
      help: 'Executable to run, for example `tea` or `gh`.',
      mandatory: true,
    )
    ..addMultiOption(
      'arg',
      help: 'Repeat for each argument that should be passed to the command.',
    )
    ..addOption(
      'mode',
      help:
          'Comma-separated modes: all, launcher, process-run, process-run-sync, process-start, powershell-command.',
      defaultsTo: 'all',
    )
    ..addOption(
      'timeout-ms',
      help: 'Per-mode timeout in milliseconds.',
      defaultsTo: '5000',
    )
    ..addOption(
      'working-directory',
      help: 'Optional working directory for the command.',
    );

  // add help
  parser.addFlag(
    'help',
    abbr: 'h',
    help: 'Show this help message.',
    negatable: false,
  );

  final results = parser.parse(arguments);
  final command = results['command'] as String;
  final args = (results['arg'] as List<String>).toList(growable: false);
  final timeout = Duration(
    milliseconds: int.parse(results['timeout-ms'] as String),
  );
  final workingDirectory = results['working-directory'] as String?;
  final selectedModes = _parseModes(results['mode'] as String);
  final resolved = resolveExternalCommandForCurrentPlatform(command, args);

  final payload = <String, Object?>{
    'command': command,
    'arguments': args,
    'timeout_ms': timeout.inMilliseconds,
    'working_directory': workingDirectory,
    'resolved': <String, Object?>{
      'executable': resolved.executable,
      'arguments': resolved.arguments,
      'run_in_shell': resolved.runInShell,
    },
    'results': <Object?>[],
  };
  final resultList = payload['results'] as List<Object?>;

  for (final mode in selectedModes) {
    resultList.add(
      await _runMode(
        mode,
        command: command,
        arguments: args,
        timeout: timeout,
        workingDirectory: workingDirectory,
      ),
    );
  }

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
}

List<String> _parseModes(String configuredModes) {
  final trimmedModes = configuredModes
      .split(',')
      .map((mode) => mode.trim())
      .where((mode) => mode.isNotEmpty)
      .toList(growable: false);
  if (trimmedModes.contains('all')) {
    return const <String>[
      'launcher',
      'process-run',
      'process-run-sync',
      'process-start',
      'powershell-command',
    ];
  }
  return trimmedModes;
}

Future<Map<String, Object?>> _runMode(
  String mode, {
  required String command,
  required List<String> arguments,
  required Duration timeout,
  required String? workingDirectory,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final result = switch (mode) {
      'launcher' => await runExternalCommand(
        command,
        arguments,
        workingDirectory: workingDirectory,
        timeout: timeout,
      ),
      'process-run' =>
        await Process.run(
          command,
          arguments,
          workingDirectory: workingDirectory,
          runInShell: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException(
              'Command timed out after ${timeout.inMilliseconds}ms.',
              timeout,
            );
          },
        ),
      'process-start' => await _runWithProcessStart(
        command: command,
        arguments: arguments,
        timeout: timeout,
        workingDirectory: workingDirectory,
      ),
      'process-run-sync' => _runWithProcessRunSync(
        command: command,
        arguments: arguments,
        workingDirectory: workingDirectory,
      ),
      'powershell-command' => await _runViaPowerShellCommand(
        command: command,
        arguments: arguments,
        timeout: timeout,
        workingDirectory: workingDirectory,
      ),
      _ => throw ArgumentError('Unsupported mode: $mode'),
    };
    stopwatch.stop();
    return <String, Object?>{
      'mode': mode,
      'status': 'success',
      'duration_ms': stopwatch.elapsedMilliseconds,
      'exit_code': result.exitCode,
      'stdout_length': result.stdout.toString().length,
      'stderr_length': result.stderr.toString().length,
      'stdout_preview': _preview(result.stdout.toString()),
      'stderr_preview': _preview(result.stderr.toString()),
    };
  } on TimeoutException catch (error) {
    stopwatch.stop();
    return <String, Object?>{
      'mode': mode,
      'status': 'timeout',
      'duration_ms': stopwatch.elapsedMilliseconds,
      'message': error.message,
    };
  } catch (error, stackTrace) {
    stopwatch.stop();
    return <String, Object?>{
      'mode': mode,
      'status': 'error',
      'duration_ms': stopwatch.elapsedMilliseconds,
      'error': error.toString(),
      'stack_preview': _preview(stackTrace.toString()),
    };
  }
}

Future<ProcessResult> _runWithProcessStart({
  required String command,
  required List<String> arguments,
  required Duration timeout,
  required String? workingDirectory,
}) async {
  final process = await Process.start(
    command,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  await process.stdin.close();
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      throw TimeoutException(
        'Command timed out after ${timeout.inMilliseconds}ms.',
        timeout,
      );
    },
  );
  return ProcessResult(
    process.pid,
    exitCode,
    await stdoutFuture,
    await stderrFuture,
  );
}

ProcessResult _runWithProcessRunSync({
  required String command,
  required List<String> arguments,
  required String? workingDirectory,
}) {
  // print
  print(
    'Running command with Process.runSync: $command ${arguments.join(' ')}',
  );
  return Process.runSync(
    command,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

Future<ProcessResult> _runViaPowerShellCommand({
  required String command,
  required List<String> arguments,
  required Duration timeout,
  required String? workingDirectory,
}) async {
  final powerShellScript = r'''
$ErrorActionPreference = 'Stop'
$command = $args[0]
$commandArgs = if ($args.Length -gt 1) { $args[1..($args.Length - 1)] } else { @() }
& $command @commandArgs
if ($null -ne $LASTEXITCODE) {
  exit $LASTEXITCODE
}
''';

  return Process.run(
    'powershell.exe',
    <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      powerShellScript,
      command,
      ...arguments,
    ],
    workingDirectory: workingDirectory,
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  ).timeout(
    timeout,
    onTimeout: () {
      throw TimeoutException(
        'Command timed out after ${timeout.inMilliseconds}ms.',
        timeout,
      );
    },
  );
}

String _preview(String text, {int maxLength = 200}) {
  final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= maxLength) {
    return singleLine;
  }
  return '${singleLine.substring(0, maxLength)}...';
}
