import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void main() {
  /// ```gherkin
  /// Feature: Worktree management
  ///
  ///   As a maintainer running bug verification jobs
  ///   I want ephemeral git worktrees to respect the configured worktree root
  ///   So that temporary workspaces are created in a predictable location
  /// ```
  group('WorkspaceManager.createEphemeralWorktree', () {
    /// ```gherkin
    /// Scenario: Create and dispose a worktree under the configured root
    ///   Given a git repository and a dedicated worktree root directory
    ///   When creating and then disposing an ephemeral worktree
    ///   Then the worktree is created beneath the configured root
    ///   And cleanup removes the generated worktree directory without deleting the root
    /// ```
    test('Create and dispose a worktree under the configured root', () async {
      // Given a git repository and a dedicated worktree root directory.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-worktree-root-',
      );
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      final worktreeRoot = await Directory(
        p.join(sandbox.path, 'worktrees'),
      ).create();
      await initGitRepo(repoDir);
      final manager = WorkspaceManager(worktreeRoot: worktreeRoot.path);

      // When creating and then disposing an ephemeral worktree.
      final workspacePath = await manager.createEphemeralWorktree(repoDir.path);
      final workspaceDirectory = Directory(workspacePath);
      final parentDirectory = Directory(p.dirname(workspacePath));
      await manager.disposeEphemeralWorktree(workspacePath);

      // Then the worktree is created beneath the configured root.
      expect(p.isWithin(worktreeRoot.path, workspacePath), isTrue);

      // And cleanup removes the generated worktree directory without deleting the root.
      expect(await workspaceDirectory.exists(), isFalse);
      expect(await parentDirectory.exists(), isFalse);
      expect(await worktreeRoot.exists(), isTrue);
    });
  });
}
