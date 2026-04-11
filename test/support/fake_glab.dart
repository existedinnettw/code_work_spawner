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
  Map<String, int>? webhookIdsByRepo,
}) async {
  final postIssueNumbers =
      postCommentIssueNumbersByRepo ??
      <String, Set<int>>{
        for (final entry in issueListResponsesByRepo.entries)
          entry.key: entry.value
              .map((issue) => issue['iid'])
              .whereType<int>()
              .toSet(),
      };
  fakeCommandHandlers[glabScript.path] = (arguments, {timeout}) async {
    if (glabLog != null) {
      await glabLog.writeAsString(
        '${arguments.join(' ')}\n',
        mode: FileMode.append,
      );
    }

    ProcessResult result(
      Object? stdout, {
      int exitCode = 0,
      String stderr = '',
    }) {
      return ProcessResult(
        0,
        exitCode,
        stdout is String ? stdout : jsonEncode(stdout),
        stderr,
      );
    }

    if (_matches(arguments, 0, 'api') && _matches(arguments, 1, 'user')) {
      if (failViewerLookup) {
        return result('', exitCode: 1, stderr: 'viewer lookup failed\n');
      }
      return result({'username': viewerLogin ?? 'glab-user'});
    }

    for (final entry in issueListResponsesByRepo.entries) {
      final repo = Uri.encodeComponent(entry.key);
      if (_matches(arguments, 0, 'api') &&
          arguments.length > 3 &&
          arguments[3].startsWith('projects/$repo/issues?state=opened')) {
        return result(entry.value);
      }
    }

    for (final repoEntry in commentResponsesByRepo.entries) {
      final repo = Uri.encodeComponent(repoEntry.key);
      for (final entry in repoEntry.value.entries) {
        if (_matches(arguments, 0, 'api') &&
            _matches(
              arguments,
              3,
              'projects/$repo/issues/${entry.key}/notes?per_page=100',
            )) {
          return result(entry.value);
        }
      }
    }

    for (final repoEntry in postIssueNumbers.entries) {
      final repo = Uri.encodeComponent(repoEntry.key);
      for (final issueNumber in repoEntry.value) {
        if (_matches(arguments, 0, 'api') &&
            _matches(
              arguments,
              3,
              'projects/$repo/issues/$issueNumber/notes',
            )) {
          final body = _valueArg(arguments, 'body=');
          if (postedBodyFile != null && body != null) {
            await postedBodyFile.writeAsString(body);
          }
          return result({
            'id': 901,
            'body': 'posted',
            'noteable_url':
                'https://gitlab.example.test/group/subgroup/sample/issues/$issueNumber',
          });
        }
      }
    }

    for (final entry in (webhookIdsByRepo ?? const <String, int>{}).entries) {
      final repo = Uri.encodeComponent(entry.key);
      if (_matches(arguments, 0, 'api') &&
          _matches(arguments, 2, 'POST') &&
          _matches(arguments, 3, 'projects/$repo/hooks')) {
        return result({'id': entry.value});
      }
      if (_matches(arguments, 0, 'api') &&
          _matches(arguments, 2, 'DELETE') &&
          _matches(arguments, 3, 'projects/$repo/hooks/${entry.value}')) {
        return result(null);
      }
    }

    return result(
      '',
      exitCode: 1,
      stderr: 'unexpected glab args: ${arguments.join(' ')}\n',
    );
  };
}

bool _matches(List<String> arguments, int index, String value) =>
    arguments.length > index && arguments[index] == value;

String? _valueArg(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }
  return null;
}
