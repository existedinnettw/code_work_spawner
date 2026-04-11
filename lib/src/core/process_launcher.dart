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
    required this.runInShell,
  });

  final String executable;
  final List<String> arguments;
  final bool runInShell;
}

final AppLogger _processLauncherLogger = AppLogger(
  'code_work_spawner.process_launcher',
);

abstract interface class ExternalCommandExecutor {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    Duration? timeout,
  });

  Future<StartedExternalCommand> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
    ProcessStartMode mode,
  });
}

abstract interface class StartedExternalCommand {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

class DefaultExternalCommandExecutor implements ExternalCommandExecutor {
  const DefaultExternalCommandExecutor();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    Duration? timeout,
  }) {
    return runExternalCommand(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      timeout: timeout,
    );
  }

  @override
  Future<StartedExternalCommand> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return ProcessStartedExternalCommand(
      await startExternalCommand(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: runInShell,
        mode: mode,
      ),
    );
  }
}

class ProcessStartedExternalCommand implements StartedExternalCommand {
  ProcessStartedExternalCommand(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

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
  return ResolvedExternalCommand(
    executable: effectiveExecutable,
    arguments: arguments,
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
  const mode = 'process-start';
  _processLauncherLogger.debug(
    'launch mode=$mode executable=${resolved.executable} '
    'requested_executable=$executable run_in_shell=${resolved.runInShell} '
    'working_directory=${workingDirectory ?? "(inherit)"} '
    'timeout_ms=${timeout?.inMilliseconds ?? 0} '
    'args=${_renderLauncherArguments(resolved.arguments)}',
  );
  final stopwatch = Stopwatch()..start();
  try {
    _processLauncherLogger.debug('process_start in runExternalCommand');
    final result = await _runExternalCommandWithCapturedOutput(
      executable: resolved.executable,
      arguments: resolved.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: resolved.runInShell,
      timeout: timeout,
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

Future<ProcessResult> _runExternalCommandWithCapturedOutput({
  required String executable,
  required List<String> arguments,
  required String? workingDirectory,
  required Map<String, String>? environment,
  required bool includeParentEnvironment,
  required bool runInShell,
  required Duration? timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  try {
    final exitCode = timeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            timeout,
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              throw TimeoutException(
                'Command timed out after ${timeout.inMilliseconds}ms.',
                timeout,
              );
            },
          );
    final stdoutText = await stdoutFuture;
    final stderrText = await stderrFuture;
    return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    rethrow;
  }
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
  return Process.start(
    resolved.executable,
    resolved.arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: runInShell || resolved.runInShell,
    mode: mode,
  );
}
