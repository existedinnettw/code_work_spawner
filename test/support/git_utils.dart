import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as p;

Future<void> initGitRepo(Directory directory) async {
  await GitDir.init(directory.path, allowContent: true);
  await runGit([
    'config',
    'user.email',
    'test@example.com',
  ], workingDirectory: directory.path);
  await runGit([
    'config',
    'user.name',
    'Test User',
  ], workingDirectory: directory.path);
  await File(p.join(directory.path, 'README.md')).writeAsString('repo');
  await runGit(['add', '.'], workingDirectory: directory.path);
  await runGit(['commit', '-m', 'init'], workingDirectory: directory.path);
}

const Set<String> gitContextEnvironmentKeys = {
  'GIT_ALTERNATE_OBJECT_DIRECTORIES',
  'GIT_COMMON_DIR',
  'GIT_DIR',
  'GIT_IMPLICIT_WORK_TREE',
  'GIT_INDEX_FILE',
  'GIT_OBJECT_DIRECTORY',
  'GIT_PREFIX',
  'GIT_WORK_TREE',
};

Future<void> runGit(
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final environment = Map<String, String>.from(Platform.environment)
    ..removeWhere((key, _) => gitContextEnvironmentKeys.contains(key));
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
