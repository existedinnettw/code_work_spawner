import 'dart:io';

import 'package:path/path.dart' as p;

class WorkspaceManager {
  WorkspaceManager({this.worktreeRoot});

  final String? worktreeRoot;
  static const Set<String> _gitContextEnvironmentKeys = {
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_COMMON_DIR',
    'GIT_DIR',
    'GIT_IMPLICIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_PREFIX',
    'GIT_WORK_TREE',
  };

  Future<String> createEphemeralWorktree(String projectPath) async {
    final parent = await _createWorktreeParent();
    final workspacePath = p.join(parent.path, 'repo');
    final command = [
      '-C',
      projectPath,
      'worktree',
      'add',
      '--detach',
      workspacePath,
      'HEAD',
    ];
    final result = await _runGit(command);

    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        command,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    return workspacePath;
  }

  Future<Directory> _createWorktreeParent() async {
    if (worktreeRoot == null) {
      return Directory.systemTemp.createTemp('cws-worktree-');
    }

    final root = Directory(worktreeRoot!);
    await root.create(recursive: true);
    return Directory(
      p.join(
        root.path,
        'cws-worktree-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync();
  }

  Future<void> disposeEphemeralWorktree(String workspacePath) async {
    final result = await _runGit([
      '-C',
      workspacePath,
      'worktree',
      'remove',
      '--force',
      workspacePath,
    ]);

    if (result.exitCode != 0) {
      final directory = Directory(p.dirname(workspacePath));
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    }

    final tempRoot = Directory(p.dirname(workspacePath));
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  }

  Future<ProcessResult> _runGit(List<String> arguments) {
    final environment = Map<String, String>.from(Platform.environment)
      ..removeWhere((key, _) => _gitContextEnvironmentKeys.contains(key));
    return Process.run(
      'git',
      arguments,
      environment: environment,
      includeParentEnvironment: false,
    );
  }
}
