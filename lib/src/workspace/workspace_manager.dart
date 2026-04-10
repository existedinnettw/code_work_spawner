import '../config/config.dart';
import 'scm_client.dart';

class WorkspaceManager {
  WorkspaceManager({this.worktreeRoot, Map<ScmProvider, ScmClient>? clients})
    : _clients = clients ?? defaultScmClients();

  final String? worktreeRoot;
  final Map<ScmProvider, ScmClient> _clients;

  Future<String> createEphemeralWorkspace(ProjectConfig project) {
    return _clientFor(project.scm.provider).createEphemeralWorkspace(
      projectPath: project.path,
      workspaceRoot: worktreeRoot,
    );
  }

  Future<void> disposeEphemeralWorkspace(ProjectConfig project, String path) {
    return _clientFor(project.scm.provider).disposeEphemeralWorkspace(path);
  }

  Future<String> createEphemeralWorktree(
    String projectPath, {
    ScmProvider provider = ScmProvider.github,
  }) {
    return _clientFor(provider).createEphemeralWorkspace(
      projectPath: projectPath,
      workspaceRoot: worktreeRoot,
    );
  }

  Future<void> disposeEphemeralWorktree(
    String workspacePath, {
    ScmProvider provider = ScmProvider.github,
  }) {
    return _clientFor(provider).disposeEphemeralWorkspace(workspacePath);
  }

  ScmClient _clientFor(ScmProvider provider) {
    final client = _clients[provider];
    if (client == null) {
      throw UnsupportedError('SCM provider ${provider.name} is not supported.');
    }
    return client;
  }
}
