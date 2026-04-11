import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/git_utils.dart';

/// ```gherkin
/// Feature: Pre-push branch freshness check
///
///   As a contributor to Code Work Spawner
///   I want the pre-push hook to validate feature branches against the latest main
///   So that stale branches are blocked without slowing down exempt push paths
/// ```
void main() {
  /// ```gherkin
  /// Scenario: Accept a feature branch that includes the latest main
  ///   Given a feature branch based on the remote main branch
  ///   When running the pre-push freshness check
  ///   Then the script exits successfully
  /// ```
  test('Accept a feature branch that includes the latest main', () async {
    // Given a feature branch based on the remote main branch.
    final fixture = await _GitFixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkoutFeatureBranch();
    await fixture.commitFile('feature.txt', 'feature');

    // When running the pre-push freshness check.
    final result = await fixture.runScript();

    // Then the script exits successfully.
    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });

  /// ```gherkin
  /// Scenario: Reject a feature branch that is behind latest main
  ///   Given a feature branch that does not include a newer remote main commit
  ///   When running the pre-push freshness check
  ///   Then the script exits with rebase guidance
  /// ```
  test('Reject a feature branch that is behind latest main', () async {
    // Given a feature branch that does not include a newer remote main commit.
    final fixture = await _GitFixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkoutFeatureBranch();
    await fixture.commitFile('feature.txt', 'feature');
    await fixture.advanceRemoteMain();

    // When running the pre-push freshness check.
    final result = await fixture.runScript();

    // Then the script exits with rebase guidance.
    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains(
        "[pre-push] Branch 'feature' is not up to date with origin/main",
      ),
    );
    expect(result.stderr, contains('git rebase origin/main'));
  });

  /// ```gherkin
  /// Scenario: Skip the check when pushing main
  ///   Given the current branch is main and the configured remote is invalid
  ///   When running the pre-push freshness check
  ///   Then the script exits successfully without fetching
  /// ```
  test('Skip the check when pushing main', () async {
    // Given the current branch is main and the configured remote is invalid.
    final fixture = await _GitFixture.create();
    addTearDown(fixture.dispose);

    // When running the pre-push freshness check.
    final result = await fixture.runScript(['--remote', 'missing']);

    // Then the script exits successfully without fetching.
    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });

  /// ```gherkin
  /// Scenario: Skip the check for tag-only pushes
  ///   Given pre-push input only contains tag refs
  ///   When running the pre-push freshness check outside a Git repository
  ///   Then the script exits successfully before inspecting Git state
  /// ```
  test('Skip the check for tag-only pushes', () async {
    // Given pre-push input only contains tag refs.
    final directory = await Directory.systemTemp.createTemp(
      'check_branch_up_to_date_tag_',
    );
    addTearDown(() => directory.delete(recursive: true));
    const stdin = 'refs/tags/v1 abc refs/tags/v1 def\n';

    // When running the pre-push freshness check outside a Git repository.
    final result = await _runScript(
      workingDirectory: directory.path,
      stdin: stdin,
    );

    // Then the script exits successfully before inspecting Git state.
    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
  });

  /// ```gherkin
  /// Scenario: Skip the check in detached HEAD state
  ///   Given the repository is in detached HEAD state and the configured remote is invalid
  ///   When running the pre-push freshness check
  ///   Then the script exits successfully with a detached HEAD message
  /// ```
  test('Skip the check in detached HEAD state', () async {
    // Given the repository is in detached HEAD state and the configured remote is invalid.
    final fixture = await _GitFixture.create();
    addTearDown(fixture.dispose);
    await runGit([
      'checkout',
      '--detach',
      'HEAD',
    ], workingDirectory: fixture.repoPath);

    // When running the pre-push freshness check.
    final result = await fixture.runScript(['--remote', 'missing']);

    // Then the script exits successfully with a detached HEAD message.
    expect(result.exitCode, 0);
    expect(
      result.stdout,
      contains(
        '[pre-push] Detached HEAD detected; skipping base branch freshness check.',
      ),
    );
    expect(result.stderr, isEmpty);
  });

  /// ```gherkin
  /// Scenario: Fail closed when fetch fails
  ///   Given a feature branch with an invalid configured remote
  ///   When running the pre-push freshness check
  ///   Then the script exits with a fetch failure
  /// ```
  test('Fail closed when fetch fails', () async {
    // Given a feature branch with an invalid configured remote.
    final fixture = await _GitFixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkoutFeatureBranch();

    // When running the pre-push freshness check.
    final result = await fixture.runScript(['--remote', 'missing']);

    // Then the script exits with a fetch failure.
    expect(result.exitCode, 1);
    expect(result.stderr, contains('[pre-push] Failed to fetch missing/main:'));
  });
}

class _GitFixture {
  _GitFixture({required this.root, required this.repoPath});

  final Directory root;
  final String repoPath;

  static Future<_GitFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'check_branch_up_to_date_',
    );
    final remotePath = p.join(root.path, 'origin.git');
    final repoPath = p.join(root.path, 'repo');

    await Directory(repoPath).create();
    await runGit(['init', '--initial-branch=main'], workingDirectory: repoPath);
    await runGit([
      'config',
      'user.email',
      'test@example.com',
    ], workingDirectory: repoPath);
    await runGit([
      'config',
      'user.name',
      'Test User',
    ], workingDirectory: repoPath);
    await File(p.join(repoPath, 'README.md')).writeAsString('repo');
    await runGit(['add', '.'], workingDirectory: repoPath);
    await runGit(['commit', '-m', 'init'], workingDirectory: repoPath);

    await runGit([
      'init',
      '--bare',
      '--initial-branch=main',
      remotePath,
    ], workingDirectory: root.path);
    await runGit([
      'remote',
      'add',
      'origin',
      remotePath,
    ], workingDirectory: repoPath);
    await runGit(['push', '-u', 'origin', 'main'], workingDirectory: repoPath);

    return _GitFixture(root: root, repoPath: repoPath);
  }

  Future<void> checkoutFeatureBranch() async {
    await runGit(['checkout', '-b', 'feature'], workingDirectory: repoPath);
  }

  Future<void> commitFile(String relativePath, String contents) async {
    await File(p.join(repoPath, relativePath)).writeAsString(contents);
    await runGit(['add', relativePath], workingDirectory: repoPath);
    await runGit(['commit', '-m', 'test change'], workingDirectory: repoPath);
  }

  Future<void> advanceRemoteMain() async {
    await runGit(['checkout', 'main'], workingDirectory: repoPath);
    await commitFile('main.txt', 'main');
    await runGit(['push', 'origin', 'main'], workingDirectory: repoPath);
    await runGit(['checkout', 'feature'], workingDirectory: repoPath);
  }

  Future<ProcessResult> runScript([List<String> arguments = const []]) {
    return _runScript(workingDirectory: repoPath, arguments: arguments);
  }

  Future<void> dispose() {
    return root.delete(recursive: true);
  }
}

Future<ProcessResult> _runScript({
  required String workingDirectory,
  List<String> arguments = const [],
  String? stdin,
}) async {
  final process = await Process.start(
    'python3',
    [
      p.join(Directory.current.path, 'scripts', 'check_branch_up_to_date.py'),
      ...arguments,
    ],
    workingDirectory: workingDirectory,
    environment: _cleanGitEnvironment(),
  );
  if (stdin != null) {
    process.stdin.write(stdin);
  }
  await process.stdin.close();
  final stdout = await process.stdout.transform(systemEncoding.decoder).join();
  final stderr = await process.stderr.transform(systemEncoding.decoder).join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

Map<String, String> _cleanGitEnvironment() {
  return Map<String, String>.from(Platform.environment)
    ..removeWhere((key, _) => gitContextEnvironmentKeys.contains(key));
}
