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
  final openSearchItems = searchItems
      .where((item) => item['state'] == 'open')
      .toList(growable: false);
  final allSearchResponse = jsonEncode({
    'total_count': searchItems.length,
    'incomplete_results': false,
    'items': searchItems,
  });
  final openSearchResponse = jsonEncode({
    'total_count': openSearchItems.length,
    'incomplete_results': false,
    'items': openSearchItems,
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
    ..writeln(r'''  query=""''')
    ..writeln(r'''  for arg in "$@"; do''')
    ..writeln(r'''    if [[ "$arg" == q=* ]]; then''')
    ..writeln(r'''      query="${arg#q=}"''')
    ..writeln(r'''    fi''')
    ..writeln(r'''  done''')
    ..writeln(r'''  if [[ "$query" == *"state:open"* ]]; then''')
    ..writeln("  cat <<'JSON'")
    ..writeln(openSearchResponse)
    ..writeln('JSON')
    ..writeln(r'''  else''')
    ..writeln("  cat <<'JSON'")
    ..writeln(allSearchResponse)
    ..writeln('JSON')
    ..writeln(r'''  fi''')
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

Future<void> writeFlakySearchGhScript({
  required File ghScript,
  required File failureStateFile,
  required List<Map<String, Object?>> issueListResponse,
  required Map<int, List<Map<String, Object?>>> commentResponses,
  File? ghLog,
}) async {
  final searchItems = issueListResponse
      .map(
        (issue) => <String, Object?>{
          ...issue,
          'repository_url': 'https://api.github.com/repos/owner/sample',
        },
      )
      .toList(growable: false);
  final searchResponse = jsonEncode({
    'total_count': searchItems.length,
    'incomplete_results': false,
    'items': searchItems,
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

  buffer
    ..writeln(r'''if [[ "$1" == "api" && "$2" == "user" ]]; then''')
    ..writeln("  cat <<'JSON'")
    ..writeln(jsonEncode({'login': 'test-user'}))
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  buffer
    ..writeln(r'''if [[ "$1" == "api" && "$4" == "search/issues" ]]; then''')
    ..writeln('  if [[ ! -f "${failureStateFile.path}" ]]; then')
    ..writeln('    touch "${failureStateFile.path}"')
    ..writeln(r'''    echo "error connecting to api.github.com" >&2''')
    ..writeln(
      r'''    echo "check your internet connection or https://githubstatus.com" >&2''',
    )
    ..writeln('    exit 1')
    ..writeln(r'''  fi''')
    ..writeln("  cat <<'JSON'")
    ..writeln(searchResponse)
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  for (final entry in commentResponses.entries) {
    buffer
      ..writeln(
        'if [[ "\$1" == "api" && "\$4" == '
        '"repos/owner/sample/issues/${entry.key}/comments?per_page=100" ]]; then',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode(entry.value))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  buffer
    ..writeln(r'''echo "unexpected gh args: $*" >&2''')
    ..writeln('exit 1');

  await ghScript.writeAsString(buffer.toString());
  await Process.run('chmod', ['+x', ghScript.path]);
}

Future<void> writeFakeTeaScript({
  required File teaScript,
  required Map<String, List<Map<String, Object?>>> issueListResponsesByRepo,
  required Map<String, Map<int, List<Map<String, Object?>>>>
  commentResponsesByRepo,
  File? teaLog,
  Map<String, Set<int>>? postCommentIssueNumbersByRepo,
  File? postedBodyFile,
  String? viewerLogin,
  bool failViewerLookup = false,
}) async {
  final normalizedPostCommentIssueNumbersByRepo =
      postCommentIssueNumbersByRepo ??
      <String, Set<int>>{
        for (final entry in issueListResponsesByRepo.entries)
          entry.key: entry.value
              .map((issue) => issue['index'] ?? issue['number'])
              .whereType<int>()
              .toSet(),
      };

  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('set -euo pipefail');

  if (teaLog != null) {
    buffer.writeln(
      r'''printf '%s\n' "$*" >> '''
      '"${teaLog.path}"',
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
      ..writeln(jsonEncode({'login': viewerLogin ?? 'tea-user'}))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  for (final entry in issueListResponsesByRepo.entries) {
    final repo = entry.key;
    buffer
      ..writeln(
        r'''if [[ "$1" == "api" && "$4" == "repos/'''
        '$repo'
        r'''/issues?state=open"* ]]; then''',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode(entry.value))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  for (final repoEntry in commentResponsesByRepo.entries) {
    final repo = repoEntry.key;
    for (final entry in repoEntry.value.entries) {
      buffer
        ..writeln(
          'if [[ "\$1" == "api" && "\$4" == '
          '"repos/$repo/issues/${entry.key}/comments?limit=100" ]]; then',
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
            'id': 701,
            'url': 'https://gitea.example.test/comment/701',
            'body': 'posted',
          }),
        )
        ..writeln('JSON')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
  }

  buffer
    ..writeln(r'''echo "unexpected tea args: $*" >&2''')
    ..writeln('exit 1');

  await teaScript.writeAsString(buffer.toString());
  await Process.run('chmod', ['+x', teaScript.path]);
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
timestamp_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}
printf 'start:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(timestamp_ms)" >> "${eventLog.path}"
cat >/dev/null
sleep ${delay.inSeconds}
printf 'end:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(timestamp_ms)" >> "${eventLog.path}"
cat <<'JSON'
${jsonEncode(response)}
JSON
''');
  await Process.run('chmod', ['+x', responderScript.path]);
}

Future<void> writeWebhookForwardGhScript({
  required File ghScript,
  required String repo,
  required Map<String, Object?> issue,
  required List<Map<String, Object?>> comments,
  File? ghLog,
  File? postedBodyFile,
  String? viewerLogin,
}) async {
  final issueNumber = issue['number'] as int;
  final payload = {
    'action': 'created',
    'issue': issue,
    'comment': comments.last,
    'repository': {'full_name': repo},
  };

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
  buffer
    ..writeln("  cat <<'JSON'")
    ..writeln(jsonEncode({'login': viewerLogin ?? 'test-user'}))
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  buffer
    ..writeln(
      'if [[ "\$1" == "api" && "\$4" == '
      '"repos/$repo/issues/$issueNumber/comments?per_page=100" ]]; then',
    )
    ..writeln("  cat <<'JSON'")
    ..writeln(jsonEncode(comments))
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

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
        'id': 702,
        'html_url': 'https://example.test/comment/702',
        'body': 'posted',
      }),
    )
    ..writeln('JSON')
    ..writeln('  exit 0')
    ..writeln('fi');

  buffer
    ..writeln(r'''if [[ "$1" == "webhook" && "$2" == "forward" ]]; then''')
    ..writeln(r'''  url=""''')
    ..writeln(r'''  for arg in "$@"; do''')
    ..writeln(r'''    if [[ "$arg" == --url=* ]]; then''')
    ..writeln(r'''      url="${arg#--url=}"''')
    ..writeln(r'''    fi''')
    ..writeln(r'''  done''')
    ..writeln(r'''  if [[ -z "$url" ]]; then''')
    ..writeln(r'''    echo "missing --url" >&2''')
    ..writeln('    exit 1')
    ..writeln(r'''  fi''')
    ..writeln(r'''  curl -sS -X POST \''')
    ..writeln(r'''    -H "Content-Type: application/json" \''')
    ..writeln(r'''    -H "X-GitHub-Event: issue_comment" \''')
    ..writeln(r'''    --data-binary @- "$url" <<'JSON' >/dev/null''')
    ..writeln(jsonEncode(payload))
    ..writeln('JSON')
    ..writeln(r'''  while true; do''')
    ..writeln(r'''    sleep 60''')
    ..writeln(r'''  done''')
    ..writeln('fi');

  buffer
    ..writeln(r'''echo "unexpected gh args: $*" >&2''')
    ..writeln('exit 1');

  await ghScript.writeAsString(buffer.toString());
  await Process.run('chmod', ['+x', ghScript.path]);
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
