import 'dart:io';

import 'package:path/path.dart' as p;

class _ResolvedCommand {
  _ResolvedCommand({
    required this.executable,
    required this.arguments,
    required this.usesBashShim,
  });

  final String executable;
  final List<String> arguments;
  final bool usesBashShim;
}

_ResolvedCommand _resolveCommand(String executable, List<String> arguments) {
  final extension = p.extension(executable).toLowerCase();
  final shouldUseBash = extension.isEmpty || extension == '.sh';

  if (Platform.isWindows && shouldUseBash && File(executable).existsSync()) {
    final bashScriptPath = _toBashPath(executable);
    return _ResolvedCommand(
      executable: 'wsl.exe',
      arguments: ['--exec', 'bash', bashScriptPath, ...arguments],
      usesBashShim: true,
    );
  }

  return _ResolvedCommand(
    executable: executable,
    arguments: arguments,
    usesBashShim: false,
  );
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
}) {
  final resolved = _resolveCommand(executable, arguments);
  final effectiveEnvironment = _effectiveEnvironmentForResolvedCommand(
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    usesBashShim: resolved.usesBashShim,
  );
  return Process.run(
    resolved.executable,
    resolved.arguments,
    workingDirectory: workingDirectory,
    environment: effectiveEnvironment,
    includeParentEnvironment: includeParentEnvironment,
  );
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
  final resolved = _resolveCommand(executable, arguments);
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
    runInShell: runInShell,
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
