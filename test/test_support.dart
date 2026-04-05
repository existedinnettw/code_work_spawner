import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as p;

Future<void> writeFakeGhScript({
  required File ghScript,
  required List<Map<String, Object?>> issueListResponse,
  required Map<int, List<Map<String, Object?>>> commentResponses,
  Map<String, List<Map<String, Object?>>>? issueListResponsesByRepo,
  Map<String, Map<int, List<Map<String, Object?>>>>? commentResponsesByRepo,
  File? ghLog,
  int? postCommentIssueNumber,
  Set<int>? postCommentIssueNumbers,
  Map<String, Set<int>>? postCommentIssueNumbersByRepo,
  File? postedBodyFile,
  String? viewerLogin,
  bool failViewerLookup = false,
}) async {
  final normalizedIssueListResponsesByRepo =
      issueListResponsesByRepo ??
      <String, List<Map<String, Object?>>>{'owner/sample': issueListResponse};
  final normalizedCommentResponsesByRepo =
      commentResponsesByRepo ??
      <String, Map<int, List<Map<String, Object?>>>>{
        'owner/sample': commentResponses,
      };
  final normalizedPostCommentIssueNumbersByRepo =
      postCommentIssueNumbersByRepo ??
      <String, Set<int>>{
        'owner/sample': {
          ...?postCommentIssueNumbers,
          ...?postCommentIssueNumber == null ? null : {postCommentIssueNumber},
        },
      };
  final searchItems =
      normalizedIssueListResponsesByRepo.entries
          .expand(
            (entry) => entry.value.map(
              (issue) => <String, Object?>{
                ...issue,
                'repository_url': 'https://api.github.com/repos/${entry.key}',
              },
            ),
          )
          .toList(growable: false)
        ..sort((left, right) {
          final leftUpdatedAt = left['updated_at'] as String? ?? '';
          final rightUpdatedAt = right['updated_at'] as String? ?? '';
          return leftUpdatedAt.compareTo(rightUpdatedAt);
        });

  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('set -euo pipefail');

  if (ghLog != null) {
    buffer.writeln(
      r'''printf '%s\n' "$*" >> '''
      '"${ghLog.path}"',
    );
  }

  buffer.writeln(r'''if [[ "$1" == "api" && "$2" == "user" ]]; then''');
  if (failViewerLookup) {
    buffer
      ..writeln(r'''  echo "viewer lookup failed" >&2''')
      ..writeln('  exit 1')
      ..writeln('fi');
  } else {
    buffer
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode({'login': viewerLogin ?? 'test-user'}))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  buffer
    ..writeln(r'''if [[ "$1" == "api" && "$4" == "search/issues" ]]; then''')
    ..writeln("  cat <<'JSON'")
    ..writeln(
      jsonEncode({
        'total_count': searchItems.length,
        'incomplete_results': false,
        'items': searchItems,
      }),
    )
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  for (final entry in normalizedIssueListResponsesByRepo.entries) {
    final repo = entry.key;
    buffer
      ..writeln(
        'if [[ "\$1" == "api" && "\$4" == repos/$repo/issues\\?* ]]; then',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode(entry.value))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  for (final repoEntry in normalizedCommentResponsesByRepo.entries) {
    final repo = repoEntry.key;
    for (final entry in repoEntry.value.entries) {
      buffer
        ..writeln(
          'if [[ "\$1" == "api" && "\$4" == '
          '"repos/$repo/issues/${entry.key}/comments?per_page=100" ]]; then',
        )
        ..writeln("  cat <<'JSON'")
        ..writeln(jsonEncode(entry.value))
        ..writeln('JSON')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
  }

  for (final repoEntry in normalizedPostCommentIssueNumbersByRepo.entries) {
    final repo = repoEntry.key;
    for (final issueNumber in repoEntry.value) {
      buffer
        ..writeln(
          'if [[ "\$1" == "api" && "\$4" == '
          '"repos/$repo/issues/$issueNumber/comments" ]]; then',
        )
        ..writeln(r'''  for arg in "$@"; do''')
        ..writeln(r'''    :''');
      if (postedBodyFile != null) {
        buffer
          ..writeln(r'''    if [[ "$arg" == body=* ]]; then''')
          ..writeln(
            r'''      printf '%s' "${arg#body=}" > '''
            '"${postedBodyFile.path}"',
          )
          ..writeln(r'''    fi''');
      }
      buffer
        ..writeln(r'''  done''')
        ..writeln("  cat <<'JSON'")
        ..writeln(
          jsonEncode({
            'id': 700,
            'html_url': 'https://example.test/comment/700',
            'body': 'posted',
          }),
        )
        ..writeln('JSON')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
  }

  buffer
    ..writeln(r'''echo "unexpected gh args: $*" >&2''')
    ..writeln('exit 1');

  await ghScript.writeAsString(buffer.toString());
  await Process.run('chmod', ['+x', ghScript.path]);
}

Future<void> writeResponderScript(
  File responderScript,
  Map<String, Object?> response, {
  String stderr = '',
  int exitCode = 0,
}) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
${stderr.isEmpty ? '' : "printf '%s\\n' ${jsonEncode(stderr)} >&2"}
cat <<'JSON'
${jsonEncode(response)}
JSON
exit $exitCode
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

Future<void> writeJsonlResponderScript(
  File responderScript,
  Map<String, Object?> response,
) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'JSON'
{"type":"thread.started","thread_id":"test-thread"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":${jsonEncode(jsonEncode(response))}}}
{"type":"turn.completed"}
JSON
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

Future<void> writeDelayedLoggingResponderScript(
  File responderScript, {
  required File eventLog,
  required Duration delay,
  required Map<String, Object?> response,
}) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
printf 'start:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(date +%s)" >> "${eventLog.path}"
cat >/dev/null
sleep ${delay.inSeconds}
printf 'end:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(date +%s)" >> "${eventLog.path}"
cat <<'JSON'
${jsonEncode(response)}
JSON
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

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
