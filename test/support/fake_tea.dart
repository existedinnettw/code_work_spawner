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
  final postIssueNumbers =
      postCommentIssueNumbersByRepo ??
      <String, Set<int>>{
        for (final entry in issueListResponsesByRepo.entries)
          entry.key: entry.value
              .map((issue) => issue['index'] ?? issue['number'])
              .whereType<int>()
              .toSet(),
      };
  fakeCommandHandlers[teaScript.path] = (arguments, {timeout}) async {
    if (teaLog != null) {
      await teaLog.writeAsString(
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
      return result({'login': viewerLogin ?? 'tea-user'});
    }

    for (final entry in issueListResponsesByRepo.entries) {
      if (_matches(arguments, 0, 'api') &&
          arguments.length > 3 &&
          arguments[3].startsWith('repos/${entry.key}/issues?state=open')) {
        return result(entry.value);
      }
    }

    for (final repoEntry in commentResponsesByRepo.entries) {
      for (final entry in repoEntry.value.entries) {
        if (_matches(arguments, 0, 'api') &&
            _matches(
              arguments,
              3,
              'repos/${repoEntry.key}/issues/${entry.key}/comments?limit=100',
            )) {
          return result(entry.value);
        }
      }
    }

    for (final repoEntry in postIssueNumbers.entries) {
      for (final issueNumber in repoEntry.value) {
        if (_matches(arguments, 0, 'api') &&
            _matches(
              arguments,
              3,
              'repos/${repoEntry.key}/issues/$issueNumber/comments',
            )) {
          final body = _valueArg(arguments, 'body=');
          if (postedBodyFile != null && body != null) {
            await postedBodyFile.writeAsString(body);
          }
          return result({
            'id': 701,
            'url': 'https://gitea.example.test/comment/701',
            'body': 'posted',
          });
        }
      }
    }

    return result(
      '',
      exitCode: 1,
      stderr: 'unexpected tea args: ${arguments.join(' ')}\n',
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
