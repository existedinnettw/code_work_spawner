import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as p;

import '../config/app_environment.dart';
import '../config/config.dart';

abstract interface class ScmClient {
  Future<String> createEphemeralWorkspace({
    required String projectPath,
    required String? workspaceRoot,
  });

  Future<void> disposeEphemeralWorkspace(String workspacePath);
}

class GitHubScmClient extends _GitWorktreeScmClient {}

class GitLabScmClient extends _GitWorktreeScmClient {}

class GiteaScmClient extends _GitWorktreeScmClient {}

abstract class _GitWorktreeScmClient implements ScmClient {
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

  @override
  Future<String> createEphemeralWorkspace({
    required String projectPath,
    required String? workspaceRoot,
  }) async {
    final repository = await GitDir.fromExisting(projectPath);
    final parent = await _createWorktreeParent(workspaceRoot);
    final workspacePath = p.join(parent.path, 'repo');
    final command = [
      '-C',
      repository.path,
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

  @override
  Future<void> disposeEphemeralWorkspace(String workspacePath) async {
    await GitDir.fromExisting(workspacePath);
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

  Future<Directory> _createWorktreeParent(String? workspaceRoot) async {
    if (workspaceRoot == null) {
      return Directory.systemTemp.createTemp('cws-worktree-');
    }

    final root = Directory(workspaceRoot);
    await root.create(recursive: true);
    return Directory(
      p.join(
        root.path,
        'cws-worktree-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync();
  }

  Future<ProcessResult> _runGit(List<String> arguments) {
    final environment = Map<String, String>.from(AppEnvironment.variables)
      ..removeWhere((key, _) => _gitContextEnvironmentKeys.contains(key));
    return Process.run(
      'git',
      arguments,
      environment: environment,
      includeParentEnvironment: false,
    );
  }
}

Map<ScmProvider, ScmClient> defaultScmClients() => {
  ScmProvider.github: GitHubScmClient(),
  ScmProvider.gitlab: GitLabScmClient(),
  ScmProvider.gitea: GiteaScmClient(),
};
