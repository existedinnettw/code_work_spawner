import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart tool/pub_get_on_pubspec_change.dart '
      '<previous-head> <new-head> <checkout-flag>',
    );
    exitCode = 64;
    return;
  }

  final [previousHead, newHead, checkoutFlag] = args;
  if (checkoutFlag != '1') {
    return;
  }

  if (!await _isCommit(previousHead) || !await _isCommit(newHead)) {
    return;
  }

  final diff = await Process.run('git', [
    'diff',
    '--quiet',
    previousHead,
    newHead,
    '--',
    'pubspec.yaml',
  ]);

  switch (diff.exitCode) {
    case 0:
      return;
    case 1:
      break;
    default:
      stderr.write(diff.stderr);
      exitCode = diff.exitCode;
      return;
  }

  final pubGet = await Process.start('dart', ['pub', 'get']);
  await stdout.addStream(pubGet.stdout);
  await stderr.addStream(pubGet.stderr);
  exitCode = await pubGet.exitCode;
}

Future<bool> _isCommit(String revision) async {
  final result = await Process.run('git', [
    'rev-parse',
    '--verify',
    '--quiet',
    '$revision^{commit}',
  ]);

  return result.exitCode == 0;
}
