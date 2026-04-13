import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

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
  File? reactionBodyFile,
  String? viewerLogin,
  bool failViewerLookup = false,
}) async {
  final issueLists =
      issueListResponsesByRepo ??
      <String, List<Map<String, Object?>>>{'owner/sample': issueListResponse};
  final comments =
      commentResponsesByRepo ??
      <String, Map<int, List<Map<String, Object?>>>>{
        'owner/sample': commentResponses,
      };
  final postIssueNumbers =
      postCommentIssueNumbersByRepo ??
      <String, Set<int>>{
        'owner/sample': {
          ...?postCommentIssueNumbers,
          ...?postCommentIssueNumber == null ? null : {postCommentIssueNumber},
        },
      };
  final searchItems =
      issueLists.entries
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

  _registerFakeGhCommand(
    command: ghScript.path,
    ghLog: ghLog,
    failViewerLookup: failViewerLookup,
    viewerLogin: viewerLogin,
    searchResponse: {
      'total_count': searchItems.length,
      'incomplete_results': false,
      'items': searchItems,
    },
    openSearchResponse: {
      'total_count': openSearchItems.length,
      'incomplete_results': false,
      'items': openSearchItems,
    },
    issueLists: issueLists,
    comments: comments,
    postIssueNumbers: postIssueNumbers,
    postedBodyFile: postedBodyFile,
    reactionBodyFile: reactionBodyFile,
  );
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

  _registerFakeGhCommand(
    command: ghScript.path,
    ghLog: ghLog,
    searchResponse: {
      'total_count': searchItems.length,
      'incomplete_results': false,
      'items': searchItems,
    },
    flakySearchStateFile: failureStateFile,
    issueLists: const {},
    comments: {'owner/sample': commentResponses},
    postIssueNumbers: const {},
  );
}

Future<void> writeWebhookForwardGhScript({
  required File ghScript,
  required String repo,
  required Map<String, Object?> issue,
  required List<Map<String, Object?>> comments,
  List<Map<String, Object?>> issueListResponse = const [],
  File? ghLog,
  File? postedBodyFile,
  String? viewerLogin,
}) async {
  final issueNumber = issue['number'] as int;
  final searchItems = issueListResponse
      .map(
        (searchIssue) => <String, Object?>{
          ...searchIssue,
          'repository_url': 'https://api.github.com/repos/$repo',
        },
      )
      .toList(growable: false);

  _registerFakeGhCommand(
    command: ghScript.path,
    ghLog: ghLog,
    viewerLogin: viewerLogin,
    searchResponse: {
      'total_count': searchItems.length,
      'incomplete_results': false,
      'items': searchItems,
    },
    issueLists: const {},
    comments: {
      repo: {issueNumber: comments},
    },
    postIssueNumbers: {
      repo: {issueNumber},
    },
    postedBodyFile: postedBodyFile,
    webhookPayload: {
      'action': 'created',
      'issue': issue,
      'comment': comments.last,
      'repository': {'full_name': repo},
    },
  );
}

Future<void> writeGitHubGosmeeGhScript({
  required File ghScript,
  required String repo,
  required int webhookId,
  required int issueNumber,
  required List<Map<String, Object?>> comments,
  List<Map<String, Object?>> issueListResponse = const [],
  File? ghLog,
  File? postedBodyFile,
  String? viewerLogin,
}) async {
  final searchItems = issueListResponse
      .map(
        (issue) => <String, Object?>{
          ...issue,
          'repository_url': 'https://api.github.com/repos/$repo',
        },
      )
      .toList(growable: false);

  _registerFakeGhCommand(
    command: ghScript.path,
    ghLog: ghLog,
    viewerLogin: viewerLogin,
    searchResponse: {
      'total_count': searchItems.length,
      'incomplete_results': false,
      'items': searchItems,
    },
    issueLists: const {},
    comments: {
      repo: {issueNumber: comments},
    },
    postIssueNumbers: {
      repo: {issueNumber},
    },
    postedBodyFile: postedBodyFile,
    webhookIdsByRepo: {repo: webhookId},
  );
}

void _registerFakeGhCommand({
  required String command,
  required Map<String, Object?> searchResponse,
  required Map<String, List<Map<String, Object?>>> issueLists,
  required Map<String, Map<int, List<Map<String, Object?>>>> comments,
  required Map<String, Set<int>> postIssueNumbers,
  File? ghLog,
  bool failViewerLookup = false,
  String? viewerLogin,
  Map<String, Object?>? openSearchResponse,
  File? postedBodyFile,
  File? reactionBodyFile,
  File? flakySearchStateFile,
  Map<String, Object?>? webhookPayload,
  Map<String, int>? webhookIdsByRepo,
}) {
  if (webhookPayload != null) {
    fakeStartedCommandHandlers[command] = (arguments) async {
      if (ghLog != null) {
        await _appendLine(ghLog, '${arguments.join(' ')}\n');
      }
      final process = FakeStartedExternalCommand();
      final targetUrl = _argumentValue(arguments, '--url=');
      if (targetUrl != null) {
        unawaited(_postGitHubWebhook(targetUrl, webhookPayload));
      }
      return process;
    };
  }

  fakeCommandHandlers[command] = (arguments, {timeout}) async {
    if (ghLog != null) {
      await _appendLine(ghLog, '${arguments.join(' ')}\n');
    }

    ProcessResult result(
      Object? stdout, {
      int exitCode = 0,
      String stderr = '',
    }) {
      final stdoutText = stdout is String ? stdout : jsonEncode(stdout);
      return ProcessResult(0, exitCode, stdoutText, stderr);
    }

    if (_argsMatch(arguments, ['api', 'user'])) {
      if (failViewerLookup) {
        return result('', exitCode: 1, stderr: 'viewer lookup failed\n');
      }
      return result({'login': viewerLogin ?? 'test-user'});
    }

    if (_argsMatchAt(arguments, 0, 'api') &&
        _argsMatchAt(arguments, 3, 'search/issues')) {
      if (flakySearchStateFile != null &&
          !await flakySearchStateFile.exists()) {
        await flakySearchStateFile.writeAsString('failed-once');
        return result(
          '',
          exitCode: 1,
          stderr:
              'error connecting to api.github.com\ncheck your internet connection or https://githubstatus.com\n',
        );
      }
      final query = arguments
          .where((argument) => argument.startsWith('q='))
          .map((argument) => argument.substring(2))
          .firstOrNull;
      return result(
        query?.contains('state:open') ?? false
            ? (openSearchResponse ?? searchResponse)
            : searchResponse,
      );
    }

    for (final entry in issueLists.entries) {
      final path = 'repos/${entry.key}/issues?';
      if (_argsMatchAt(arguments, 0, 'api') &&
          arguments.length > 3 &&
          arguments[3].startsWith(path)) {
        return result(entry.value);
      }
    }

    for (final repoEntry in comments.entries) {
      for (final entry in repoEntry.value.entries) {
        if (_argsMatchAt(arguments, 0, 'api') &&
            _argsMatchAt(
              arguments,
              3,
              'repos/${repoEntry.key}/issues/${entry.key}/comments?per_page=100',
            )) {
          return result(entry.value);
        }
      }
    }

    for (final repoEntry in postIssueNumbers.entries) {
      for (final issueNumber in repoEntry.value) {
        if (_argsMatchAt(arguments, 0, 'api') &&
            _argsMatchAt(
              arguments,
              3,
              'repos/${repoEntry.key}/issues/$issueNumber/comments',
            )) {
          final body = _argumentValue(arguments, 'body=');
          if (postedBodyFile != null && body != null) {
            await postedBodyFile.writeAsString(body);
          }
          return result({
            'id': 700,
            'html_url': 'https://example.test/comment/700',
            'body': 'posted',
          });
        }
      }
    }

    for (final repoEntry in comments.entries) {
      for (final issueEntry in repoEntry.value.entries) {
        for (final comment in issueEntry.value) {
          final commentId = comment['id'];
          if (commentId is int &&
              _argsMatchAt(arguments, 0, 'api') &&
              _argsMatchAt(
                arguments,
                3,
                'repos/${repoEntry.key}/issues/comments/$commentId/reactions',
              )) {
            final content = _argumentValue(arguments, 'content=');
            if (reactionBodyFile != null && content != null) {
              await reactionBodyFile.writeAsString(content);
            }
            return result({'id': 990, 'content': 'eyes'});
          }
        }
      }
    }

    for (final entry in (webhookIdsByRepo ?? const <String, int>{}).entries) {
      final hooksPath = 'repos/${entry.key}/hooks';
      if (_argsMatchAt(arguments, 0, 'api') &&
          _argsMatchAt(arguments, 3, hooksPath)) {
        return result({'id': entry.value});
      }
      if (_argsMatchAt(arguments, 0, 'api') &&
          _argsMatchAt(arguments, 3, '$hooksPath/${entry.value}')) {
        return result(null);
      }
    }

    return result(
      '',
      exitCode: 1,
      stderr: 'unexpected gh args: ${arguments.join(' ')}\n',
    );
  };
}

Future<void> _postGitHubWebhook(
  String targetUrl,
  Map<String, Object?> webhookPayload,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(targetUrl));
    request.headers.contentType = ContentType.json;
    request.headers.set('X-GitHub-Event', 'issue_comment');
    request.add(utf8.encode(jsonEncode(webhookPayload)));
    await request.close();
  } finally {
    client.close(force: true);
  }
}

bool _argsMatch(List<String> arguments, List<String> expected) =>
    arguments.length >= expected.length &&
    Iterable.generate(
      expected.length,
    ).every((index) => arguments[index] == expected[index]);

bool _argsMatchAt(List<String> arguments, int index, String expected) =>
    arguments.length > index && arguments[index] == expected;

String? _argumentValue(List<String> arguments, String prefix) {
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) {
      return argument.substring(prefix.length);
    }
  }
  return null;
}

Future<void> _appendLine(File file, String line) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    RandomAccessFile? log;
    try {
      log = file.openSync(mode: FileMode.append);
      log.lockSync(FileLock.exclusive);
      log.writeStringSync(line);
      log.unlockSync();
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    } finally {
      log?.closeSync();
    }
  }
  await file.writeAsString(line, mode: FileMode.append);
}
