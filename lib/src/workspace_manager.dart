import 'dart:io';

import 'package:path/path.dart' as p;

class WorkspaceManager {
  Future<String> createEphemeralWorktree(String projectPath) async {
    final parent = await Directory.systemTemp.createTemp('cws-worktree-');
    final workspacePath = p.join(parent.path, 'repo');
    final result = await Process.run('git', [
      '-C',
      projectPath,
      'worktree',
      'add',
      '--detach',
      workspacePath,
      'HEAD',
    ]);

    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        [
          '-C',
          projectPath,
          'worktree',
          'add',
          '--detach',
          workspacePath,
          'HEAD',
        ],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    return workspacePath;
  }

  Future<void> disposeEphemeralWorktree(String workspacePath) async {
    final result = await Process.run('git', [
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
}
