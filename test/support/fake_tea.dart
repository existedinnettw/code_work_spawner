import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

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
      '"${bashScriptPath(teaLog.path)}"',
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
            '"${bashScriptPath(postedBodyFile.path)}"',
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
  await makeScriptExecutable(teaScript);
}
