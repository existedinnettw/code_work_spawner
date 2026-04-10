import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

Future<void> writeFakeGlabScript({
  required File glabScript,
  required Map<String, List<Map<String, Object?>>> issueListResponsesByRepo,
  required Map<String, Map<int, List<Map<String, Object?>>>>
  commentResponsesByRepo,
  File? glabLog,
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
              .map((issue) => issue['iid'])
              .whereType<int>()
              .toSet(),
      };

  final buffer = StringBuffer()
    ..writeln('#!/usr/bin/env bash')
    ..writeln('set -euo pipefail');

  if (glabLog != null) {
    buffer.writeln(
      r'''printf '%s\n' "$*" >> '''
      '"${bashScriptPath(glabLog.path)}"',
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
      ..writeln(jsonEncode({'username': viewerLogin ?? 'glab-user'}))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  for (final entry in issueListResponsesByRepo.entries) {
    final repo = Uri.encodeComponent(entry.key);
    buffer
      ..writeln(
        r'''if [[ "$1" == "api" && "$4" == "projects/'''
        '$repo'
        r'''/issues?state=opened"* ]]; then''',
      )
      ..writeln("  cat <<'JSON'")
      ..writeln(jsonEncode(entry.value))
      ..writeln('JSON')
      ..writeln('  exit 0')
      ..writeln('fi');
  }

  for (final repoEntry in commentResponsesByRepo.entries) {
    final repo = Uri.encodeComponent(repoEntry.key);
    for (final entry in repoEntry.value.entries) {
      buffer
        ..writeln(
          'if [[ "\$1" == "api" && "\$4" == '
          '"projects/$repo/issues/${entry.key}/notes?per_page=100" ]]; then',
        )
        ..writeln("  cat <<'JSON'")
        ..writeln(jsonEncode(entry.value))
        ..writeln('JSON')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
  }

  for (final repoEntry in normalizedPostCommentIssueNumbersByRepo.entries) {
    final repo = Uri.encodeComponent(repoEntry.key);
    for (final issueNumber in repoEntry.value) {
      buffer
        ..writeln(
          'if [[ "\$1" == "api" && "\$4" == '
          '"projects/$repo/issues/$issueNumber/notes" ]]; then',
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
            'id': 901,
            'body': 'posted',
            'noteable_url':
                'https://gitlab.example.test/group/subgroup/sample/issues/$issueNumber',
          }),
        )
        ..writeln('JSON')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
  }

  buffer
    ..writeln(r'''echo "unexpected glab args: $*" >&2''')
    ..writeln('exit 1');

  await glabScript.writeAsString(buffer.toString());
  await makeScriptExecutable(glabScript);
}
