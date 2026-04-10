import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_logger.dart';
import 'package:executable/executable.dart';
import 'package:path/path.dart' as p;

class ResolvedExternalCommand {
  ResolvedExternalCommand({
    required this.executable,
    required this.arguments,
    required this.usesBashShim,
    required this.runInShell,
  });

  final String executable;
  final List<String> arguments;
  final bool usesBashShim;
  final bool runInShell;
}

final AppLogger _processLauncherLogger = AppLogger(
  'code_work_spawner.process_launcher',
);

ResolvedExternalCommand resolveExternalCommandForCurrentPlatform(
  String executable,
  List<String> arguments, {
  bool? isWindows,
}) {
  final isWindowsPlatform = isWindows ?? Platform.isWindows;
  final localExecutablePath = _resolveLocalExecutablePath(executable);
  final resolvedExecutablePath =
      localExecutablePath ?? _resolveExecutablePathOnPath(executable);
  final effectiveExecutable = resolvedExecutablePath ?? executable;
  final extension = p.extension(effectiveExecutable).toLowerCase();
  final shouldUseBash = extension.isEmpty || extension == '.sh';

  if (isWindowsPlatform && shouldUseBash && localExecutablePath != null) {
    final bashScriptPath = _toBashPath(localExecutablePath);
    _processLauncherLogger.debug(
      'resolved WSL bash shim executable=$localExecutablePath '
      'bash_script=$bashScriptPath '
      'args=${_renderLauncherArguments(arguments)}',
    );
    return ResolvedExternalCommand(
      executable: 'wsl.exe',
      arguments: ['--exec', 'bash', bashScriptPath, ...arguments],
      usesBashShim: true,
      runInShell: false,
    );
  }

  return ResolvedExternalCommand(
    executable: effectiveExecutable,
    arguments: arguments,
    usesBashShim: false,
    // Only batch files require shell mediation on Windows. Native executables
    // such as Scoop shims should run directly to avoid hanging shell wrappers.
    runInShell: isWindowsPlatform && _requiresWindowsShell(extension),
  );
}

bool _requiresWindowsShell(String extension) {
  return extension == '.bat' || extension == '.cmd';
}

String? _resolveLocalExecutablePath(String executable) {
  final localFile = File(executable);
  if (!localFile.existsSync()) {
    return null;
  }
  return localFile.path;
}

String? _resolveExecutablePathOnPath(String executable) {
  if (_looksLikePathReference(executable)) {
    return null;
  }
  return Executable(executable).findSync();
}

bool _looksLikePathReference(String executable) {
  return executable.contains(r'\') ||
      executable.contains('/') ||
      executable.startsWith('.');
}

String _toBashPath(String windowsPath) {
  final normalized = windowsPath.replaceAll('\\', '/');
  final drivePrefixMatch = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (drivePrefixMatch == null) {
    return normalized;
  }

  final driveLetter = drivePrefixMatch.group(1)!.toLowerCase();
  final rest = drivePrefixMatch.group(2)!;
  return '/mnt/$driveLetter/$rest';
}

Future<ProcessResult> runExternalCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration? timeout,
}) async {
  final resolved = resolveExternalCommandForCurrentPlatform(
    executable,
    arguments,
  );
  final effectiveEnvironment = _effectiveEnvironmentForResolvedCommand(
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    usesBashShim: resolved.usesBashShim,
  );
  final mode = Platform.isWindows && !resolved.usesBashShim
      ? 'windows-wrapper'
      : 'process-run';
  _processLauncherLogger.debug(
    'launch mode=$mode executable=${resolved.executable} '
    'requested_executable=$executable run_in_shell=${resolved.runInShell} '
    'uses_bash_shim=${resolved.usesBashShim} '
    'working_directory=${workingDirectory ?? "(inherit)"} '
    'timeout_ms=${timeout?.inMilliseconds ?? 0} '
    'args=${_renderLauncherArguments(resolved.arguments)}',
  );
  if (Platform.isWindows && !resolved.usesBashShim) {
    _processLauncherLogger.debug(
      'process_run in runExternalCommand - windows wrapper',
    );
    return _runExternalCommandViaWindowsWrapper(
      executable: resolved.executable,
      arguments: resolved.arguments,
      workingDirectory: workingDirectory,
      environment: effectiveEnvironment,
      includeParentEnvironment: includeParentEnvironment,
      timeout: timeout,
    );
  }
  final stopwatch = Stopwatch()..start();
  try {
    _processLauncherLogger.debug('process_run in runExternalCommand');
    final result = timeout == null
        ? await Process.run(
            resolved.executable,
            resolved.arguments,
            workingDirectory: workingDirectory,
            environment: effectiveEnvironment,
            includeParentEnvironment: includeParentEnvironment,
            runInShell: resolved.runInShell,
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          )
        : await Process.run(
            resolved.executable,
            resolved.arguments,
            workingDirectory: workingDirectory,
            environment: effectiveEnvironment,
            includeParentEnvironment: includeParentEnvironment,
            runInShell: resolved.runInShell,
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
    stopwatch.stop();
    _processLauncherLogger.debug(
      'finished mode=$mode exit_code=${result.exitCode} '
      'duration_ms=${stopwatch.elapsedMilliseconds} '
      'stdout_len=${result.stdout.toString().length} '
      'stderr_len=${result.stderr.toString().length}',
    );
    return result;
  } on TimeoutException {
    stopwatch.stop();
    _processLauncherLogger.debug(
      'timeout mode=$mode duration_ms=${stopwatch.elapsedMilliseconds}',
    );
    rethrow;
  }
}

Future<ProcessResult> _runExternalCommandViaWindowsWrapper({
  required String executable,
  required List<String> arguments,
  required String? workingDirectory,
  required Map<String, String>? environment,
  required bool includeParentEnvironment,
  required Duration? timeout,
}) async {
  const timeoutExitCode = 124;
  final sandbox = await Directory.systemTemp.createTemp(
    'cws-process-launcher-',
  );
  final stdoutPath = p.join(sandbox.path, 'stdout.txt');
  final stderrPath = p.join(sandbox.path, 'stderr.txt');
  final scriptPath = p.join(sandbox.path, 'run.ps1');
  final script = File(scriptPath);

  _processLauncherLogger.debug('after fopen');

  try {
    await script.writeAsString(
      _buildWindowsWrapperScript(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        stdoutPath: stdoutPath,
        stderrPath: stderrPath,
        timeout: timeout,
      ),
    );
    final stopwatch = Stopwatch()..start();
    _processLauncherLogger.debug(
      'wrapper start executable=$executable '
      'script=${script.path} stdout_path=$stdoutPath stderr_path=$stderrPath',
    );
    final wrapperResult = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    stopwatch.stop();
    final stdoutText = await _readWrapperOutput(stdoutPath);
    final stderrText = await _readWrapperOutput(stderrPath);
    _processLauncherLogger.debug(
      'wrapper finished exit_code=${wrapperResult.exitCode} '
      'duration_ms=${stopwatch.elapsedMilliseconds} '
      'stdout_len=${stdoutText.length} stderr_len=${stderrText.length} '
      'wrapper_stdout_len=${wrapperResult.stdout.toString().length} '
      'wrapper_stderr_len=${wrapperResult.stderr.toString().length}',
    );
    if (wrapperResult.exitCode == timeoutExitCode) {
      throw TimeoutException(
        'Command timed out after ${timeout!.inMilliseconds}ms.',
        timeout,
      );
    }
    return ProcessResult(
      wrapperResult.pid,
      wrapperResult.exitCode,
      stdoutText,
      stderrText.isEmpty ? wrapperResult.stderr : stderrText,
    );
  } finally {
    await sandbox.delete(recursive: true);
  }
}

String _buildWindowsWrapperScript({
  required String executable,
  required List<String> arguments,
  required String? workingDirectory,
  required String stdoutPath,
  required String stderrPath,
  required Duration? timeout,
}) {
  final timeoutMilliseconds = timeout?.inMilliseconds ?? 0;
  return '''
\$ErrorActionPreference = 'Stop'
\$stdoutPath = ${_powerShellSingleQuoted(stdoutPath)}
\$stderrPath = ${_powerShellSingleQuoted(stderrPath)}
try {
  \$commandPath = ${_powerShellSingleQuoted(executable)}

  \$startProcess = @{
    FilePath = \$commandPath
    ArgumentList = ${_renderPowerShellArray(arguments)}
    PassThru = \$true
    WindowStyle = 'Hidden'
    RedirectStandardOutput = \$stdoutPath
    RedirectStandardError = \$stderrPath
  }
  if (${workingDirectory == null ? '\$false' : '\$true'}) {
    \$startProcess.WorkingDirectory = ${_powerShellSingleQuoted(workingDirectory ?? '')}
  }
  \$process = Start-Process @startProcess

  \$timedOut = \$false
  if ($timeoutMilliseconds -gt 0) {
    if (-not \$process.WaitForExit($timeoutMilliseconds)) {
      \$timedOut = \$true
      try {
        Stop-Process -Id \$process.Id -Force
      } catch {
      }
    }
  } else {
    \$process.WaitForExit()
  }

  if (\$timedOut) {
    exit 124
  }

  exit \$process.ExitCode
} catch {
  Set-Content -LiteralPath \$stderrPath -Value \$_.ToString() -Encoding utf8
  exit 127
}
''';
}

Future<String> _readWrapperOutput(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return '';
  }
  return file.readAsString();
}

String _renderPowerShellArray(List<String> arguments) {
  final renderedArguments = arguments.map(_powerShellSingleQuoted).join(', ');
  return '@($renderedArguments)';
}

String _powerShellSingleQuoted(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _renderLauncherArguments(List<String> arguments) {
  return arguments.map(_summarizeLauncherArgument).join(' ');
}

String _summarizeLauncherArgument(String value) {
  if (value.startsWith('body=')) {
    return 'body=<redacted>';
  }
  if (value.length <= 120) {
    return value;
  }
  return '${value.substring(0, 117)}...';
}

Future<Process> startExternalCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  bool runInShell = false,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  final resolved = resolveExternalCommandForCurrentPlatform(
    executable,
    arguments,
  );
  final effectiveEnvironment = _effectiveEnvironmentForResolvedCommand(
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    usesBashShim: resolved.usesBashShim,
  );
  return Process.start(
    resolved.executable,
    resolved.arguments,
    workingDirectory: workingDirectory,
    environment: effectiveEnvironment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell || resolved.runInShell,
    mode: mode,
  );
}

Map<String, String>? _effectiveEnvironmentForResolvedCommand({
  required Map<String, String>? environment,
  required bool includeParentEnvironment,
  required bool usesBashShim,
}) {
  if (!usesBashShim || environment == null || environment.isEmpty) {
    return environment;
  }

  final effectiveEnvironment = Map<String, String>.from(environment);
  final existingWslenvFromProcess = includeParentEnvironment
      ? Platform.environment['WSLENV']
      : null;
  final existingWslenv =
      effectiveEnvironment['WSLENV'] ?? existingWslenvFromProcess;
  final forwardedKeys = <String>{
    ...?existingWslenv?.split(':').where((entry) => entry.isNotEmpty),
    ...effectiveEnvironment.keys.where((key) => key != 'WSLENV'),
  };
  effectiveEnvironment['WSLENV'] = forwardedKeys.join(':');
  return effectiveEnvironment;
}
