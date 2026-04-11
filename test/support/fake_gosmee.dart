import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

Future<void> writeGosmeeForwardScript({
  required File gosmeeScript,
  required String publicUrl,
  required Map<String, Object?> payload,
  File? gosmeeLog,
}) async {
  registerFakeGosmeeCommand(
    command: gosmeeScript.path,
    publicUrl: publicUrl,
    payload: payload,
    gosmeeLog: gosmeeLog,
  );
}

void registerFakeGosmeeCommand({
  required String command,
  required String publicUrl,
  Map<String, Object?>? payload,
  File? gosmeeLog,
  String webhookHeader = 'X-Gitea-Event',
}) {
  fakeCommandHandlers[command] = (arguments, {timeout}) async {
    if (gosmeeLog != null) {
      await _appendLine(gosmeeLog, '${arguments.join(' ')}\n');
    }
    if (_matchesNewUrl(arguments)) {
      return ProcessResult(0, 0, publicUrl, '');
    }
    return ProcessResult(
      0,
      1,
      '',
      'unexpected gosmee args: ${arguments.join(' ')}\n',
    );
  };

  fakeStartedCommandHandlers[command] = (arguments) async {
    if (gosmeeLog != null) {
      await _appendLine(gosmeeLog, '${arguments.join(' ')}\n');
    }
    final process = FakeStartedExternalCommand();
    if (arguments.length >= 3 &&
        arguments[0] == 'client' &&
        arguments[1] == publicUrl) {
      if (payload != null) {
        unawaited(_postWebhook(arguments[2], payload, webhookHeader));
      }
      return process;
    }
    process.addStderr('unexpected gosmee args: ${arguments.join(' ')}\n');
    process.complete(1);
    return process;
  };
}

bool _matchesNewUrl(List<String> arguments) {
  return arguments.length >= 4 &&
      arguments[0] == '--output' &&
      arguments[1] == 'json' &&
      arguments[2] == 'client' &&
      arguments[3] == '--new-url';
}

Future<void> _postWebhook(
  String targetUrl,
  Map<String, Object?> payload,
  String webhookHeader,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(targetUrl));
    request.headers.contentType = ContentType.json;
    request.headers.set(webhookHeader, 'issue_comment');
    request.write(jsonEncode(payload));
    await request.close();
  } finally {
    client.close(force: true);
  }
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
