import 'dart:io';

Future<void> makeScriptExecutable(File script) async {
  if (Platform.isWindows) {
    return;
  }

  final result = await Process.run('chmod', ['+x', script.path]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'chmod',
      ['+x', script.path],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

String bashScriptPath(String hostPath) {
  if (!Platform.isWindows) {
    return hostPath;
  }

  final normalized = hostPath.replaceAll('\\', '/');
  final drivePrefixMatch = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (drivePrefixMatch == null) {
    return normalized;
  }

  final driveLetter = drivePrefixMatch.group(1)!.toLowerCase();
  final rest = drivePrefixMatch.group(2)!;
  return '/mnt/$driveLetter/$rest';
}

String hostPathFromScript(String scriptPath) {
  if (!Platform.isWindows) {
    return scriptPath;
  }

  final trimmed = scriptPath.trim();
  final mntPathMatch = RegExp(r'^/mnt/([a-zA-Z])/(.*)$').firstMatch(trimmed);
  if (mntPathMatch == null) {
    return trimmed;
  }

  final driveLetter = mntPathMatch.group(1)!.toUpperCase();
  final rest = mntPathMatch.group(2)!.replaceAll('/', '\\');
  return '$driveLetter:\\$rest';
}
