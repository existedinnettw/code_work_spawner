import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:github/github.dart';
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

    /// ```gherkin
    /// Scenario: Route project workspaces through the configured SCM client
    ///   Given a workspace manager with a fake GitHub SCM client
    ///   And a project config that selects GitHub as its SCM provider
    ///   When creating and disposing an ephemeral workspace for that project
    ///   Then the workspace manager delegates both operations to the matching SCM client
    /// ```
    test('Route project workspaces through the configured SCM client', () async {
      // Given a workspace manager with a fake GitHub SCM client.
      final client = _RecordingScmClient();
      final manager = WorkspaceManager(
        worktreeRoot: '/tmp/worktrees',
        clients: {ScmProvider.github: client},
      );

      // And a project config that selects GitHub as its SCM provider.
      final project = ProjectConfig(
        key: 'sample',
        provider: IssueTrackerProvider.github,
        scm: const ScmConfig(provider: ScmProvider.github),
        repo: 'owner/sample',
        repoSlug: RepositorySlug('owner', 'sample'),
        path: '/tmp/source-repo',
        defaultBranch: 'main',
        sessionPrefix: 'sam',
        issueAssistant: IssueAssistantConfig(
          enabled: true,
          eventSource: const PollingIssueEventSourceConfig(
            type: IssueAssistantEventSourceKind.ghPolling,
            pollInterval: Duration(seconds: 30),
          ),
          maxConcurrentIssues: 3,
          mentionTriggers: const ['@helper'],
          prompt: defaultIssueAssistantPrompt,
          responders: const <CliResponderConfig>[],
          capabilities: {AssistantCapability.planning},
          notifications: const <NotificationConfig>[],
          commentTag: 'code-work-spawner',
          commentPrefixTemplate: defaultCommentPrefixTemplate,
          commentFooterTemplate: defaultCommentFooterTemplate,
        ),
      );

      // When creating and disposing an ephemeral workspace for that project.
      final workspacePath = await manager.createEphemeralWorkspace(project);
      await manager.disposeEphemeralWorkspace(project, workspacePath);

      // Then the workspace manager delegates both operations to the matching SCM client.
      expect(client.createdProjectPath, '/tmp/source-repo');
      expect(client.createdWorkspaceRoot, '/tmp/worktrees');
      expect(client.disposedWorkspacePath, '/tmp/workspaces/sample');
    });

    /// ```gherkin
    /// Scenario: Route project workspaces through the GitLab SCM client
    ///   Given a workspace manager with a fake GitLab SCM client
    ///   And a project config that selects GitLab as its SCM provider
    ///   When creating and disposing an ephemeral workspace for that project
    ///   Then the workspace manager delegates both operations to the GitLab SCM client
    /// ```
    test('Route project workspaces through the GitLab SCM client', () async {
      // Given a workspace manager with a fake GitLab SCM client.
      final client = _RecordingScmClient();
      final manager = WorkspaceManager(
        worktreeRoot: '/tmp/worktrees',
        clients: {ScmProvider.gitlab: client},
      );

      // And a project config that selects GitLab as its SCM provider.
      final project = ProjectConfig(
        key: 'sample',
        provider: IssueTrackerProvider.gitlab,
        scm: const ScmConfig(provider: ScmProvider.gitlab),
        repo: 'group/subgroup/sample',
        repoSlug: null,
        path: '/tmp/source-repo',
        defaultBranch: 'main',
        sessionPrefix: 'sam',
        issueAssistant: IssueAssistantConfig(
          enabled: true,
          eventSource: const PollingIssueEventSourceConfig(
            type: IssueAssistantEventSourceKind.glabPolling,
            pollInterval: Duration(seconds: 30),
          ),
          maxConcurrentIssues: 3,
          mentionTriggers: const ['@helper'],
          prompt: defaultIssueAssistantPrompt,
          responders: const <CliResponderConfig>[],
          capabilities: {AssistantCapability.planning},
          notifications: const <NotificationConfig>[],
          commentTag: 'code-work-spawner',
          commentPrefixTemplate: defaultCommentPrefixTemplate,
          commentFooterTemplate: defaultCommentFooterTemplate,
        ),
      );

      // When creating and disposing an ephemeral workspace for that project.
      final workspacePath = await manager.createEphemeralWorkspace(project);
      await manager.disposeEphemeralWorkspace(project, workspacePath);

      // Then the workspace manager delegates both operations to the GitLab SCM client.
      expect(client.createdProjectPath, '/tmp/source-repo');
      expect(client.createdWorkspaceRoot, '/tmp/worktrees');
      expect(client.disposedWorkspacePath, '/tmp/workspaces/sample');
    });
  });
}

class _RecordingScmClient implements ScmClient {
  String? createdProjectPath;
  String? createdWorkspaceRoot;
  String? disposedWorkspacePath;

  @override
  Future<String> createEphemeralWorkspace({
    required String projectPath,
    required String? workspaceRoot,
  }) async {
    createdProjectPath = projectPath;
    createdWorkspaceRoot = workspaceRoot;
    return '/tmp/workspaces/sample';
  }

  @override
  Future<void> disposeEphemeralWorkspace(String workspacePath) async {
    disposedWorkspacePath = workspacePath;
  }
}
