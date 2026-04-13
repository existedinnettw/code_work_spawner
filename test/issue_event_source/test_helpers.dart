import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:path/path.dart' as p;

import '../test_support.dart';

Future<({Directory sandbox, Directory repoDir})> createSandboxRepo({
  required String prefix,
}) async {
  final sandbox = await Directory.systemTemp.createTemp(prefix);
  final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
  await initGitRepo(repoDir);
  return (sandbox: sandbox, repoDir: repoDir);
}

Future<File> writeSingleProjectIssueAssistantConfig({
  required Directory sandbox,
  required String responderPath,
  required String provider,
  required String repo,
  required String repoPath,
  required List<String> eventSourceLines,
}) async {
  final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
  final eventSourceYaml = eventSourceLines
      .map((line) => '        $line')
      .join('\n');
  await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
    mentionTriggers: ["@helper"]
    responders:
      - id: primary
        command: $responderPath
        timeout: 1m
projects:
  sample:
    issueTracker:
      provider: $provider
      eventSource:
$eventSourceYaml
    repo: $repo
    path: $repoPath
''');
  return configFile;
}

Future<void> runAppUntil({
  required IssueAssistantApp app,
  required Future<bool> Function() isReady,
  int maxAttempts = 200,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final runFuture = app.run();
  try {
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (await isReady()) {
        break;
      }
      await Future<void>.delayed(pollInterval);
    }
  } finally {
    await app.close();
  }
  await runFuture;
}
