import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/src/config/config.dart';
import 'package:code_work_spawner/src/core/cli_responder.dart';
import 'package:code_work_spawner/src/issue_tracker/issue_tracker_client.dart';

final Map<String, _FakeResponder> _fakeResponders = {};

CliResponderRunner fakeResponderRunner() =>
    FakeResponderRunner(Map<String, _FakeResponder>.from(_fakeResponders));

Future<void> writeResponderScript(
  File responderScript,
  Map<String, Object?> response, {
  String stderr = '',
  int exitCode = 0,
}) async {
  _fakeResponders[responderScript.path] = _FakeResponder(
    response: response,
    stderr: stderr,
    exitCode: exitCode,
  );
}

Future<void> writeCapturingResponderScript(
  File responderScript,
  Map<String, Object?> response, {
  File? cwdCapture,
  File? stdinCapture,
}) async {
  _fakeResponders[responderScript.path] = _FakeResponder(
    response: response,
    cwdCapture: cwdCapture,
    stdinCapture: stdinCapture,
  );
}

Future<void> writeJsonlResponderScript(
  File responderScript,
  Map<String, Object?> response,
) async {
  _fakeResponders[responderScript.path] = _FakeResponder(
    response: response,
    emitsJsonl: true,
  );
}

Future<void> writeDelayedLoggingResponderScript(
  File responderScript, {
  required File eventLog,
  required Duration delay,
  required Map<String, Object?> response,
}) async {
  _fakeResponders[responderScript.path] = _FakeResponder(
    response: response,
    eventLog: eventLog,
    delay: delay,
  );
}

class FakeResponderRunner extends CliResponderRunner {
  FakeResponderRunner(this._responders);

  final Map<String, _FakeResponder> _responders;

  @override
  Future<ResponderResult> run({
    required CliResponderConfig responder,
    required ProjectConfig project,
    required IssueThread thread,
    required String prompt,
    required String workspacePath,
    String? responderSessionId,
    ResponderInvocationMode invocationMode = ResponderInvocationMode.coldStart,
  }) async {
    final fake = _responders[responder.command];
    if (fake == null) {
      throw StateError(
        'No fake responder registered for command ${responder.command}.',
      );
    }

    final context = <String, String>{
      'prompt': prompt,
      'repo': project.repo,
      'project_key': project.key,
      'project_path': project.path,
      'workspace_path': workspacePath,
      'issue_number': thread.issue.number.toString(),
      'thread_json': encodePrettyJson(thread.toJson()),
      'responder_session_id': responderSessionId ?? '',
      'invocation_mode': invocationMode.value,
    };
    final stdinPayload = renderTemplate(responder.stdinTemplate, context);

    await fake.run(
      issueNumber: thread.issue.number,
      stdinPayload: stdinPayload,
      workspacePath: workspacePath,
    );
    final rawStdout = fake.rawStdout;
    if (fake.exitCode != 0) {
      throw CliResponderExecutionException(
        responderId: responder.id,
        command: responder.command,
        arguments: responder.args,
        exitCode: fake.exitCode,
        rawStdout: rawStdout,
        rawStderr: fake.stderr,
      );
    }

    return ResponderResult.fromJson(
      fake.response,
      responderId: responder.id,
      rawStdout: rawStdout,
      rawStderr: fake.stderr,
    );
  }
}

class _FakeResponder {
  _FakeResponder({
    required this.response,
    this.stderr = '',
    this.exitCode = 0,
    this.emitsJsonl = false,
    this.eventLog,
    this.delay = Duration.zero,
    this.cwdCapture,
    this.stdinCapture,
  });

  final Map<String, Object?> response;
  final String stderr;
  final int exitCode;
  final bool emitsJsonl;
  final File? eventLog;
  final Duration delay;
  final File? cwdCapture;
  final File? stdinCapture;

  String get rawStdout {
    if (!emitsJsonl) {
      return jsonEncode(response);
    }
    return [
      jsonEncode({'type': 'thread.started', 'thread_id': 'test-thread'}),
      jsonEncode({'type': 'turn.started'}),
      jsonEncode({
        'type': 'item.completed',
        'item': {
          'id': 'item_0',
          'type': 'agent_message',
          'text': jsonEncode(response),
        },
      }),
      jsonEncode({'type': 'turn.completed'}),
      '',
    ].join('\n');
  }

  Future<void> run({
    required int issueNumber,
    required String stdinPayload,
    required String workspacePath,
  }) async {
    await cwdCapture?.writeAsString(workspacePath);
    await stdinCapture?.writeAsString(stdinPayload);
    if (eventLog != null) {
      await _appendEvent('start', issueNumber);
      await Future<void>.delayed(delay);
      await _appendEvent('end', issueNumber);
    }
  }

  Future<void> _appendEvent(String phase, int issueNumber) async {
    final timestampMs = DateTime.now().microsecondsSinceEpoch ~/ 1000;
    final line = '$phase:$issueNumber:$timestampMs\n';
    for (var attempt = 0; attempt < 200; attempt += 1) {
      RandomAccessFile? log;
      try {
        log = eventLog!.openSync(mode: FileMode.append);
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
    await eventLog!.writeAsString(line, mode: FileMode.append);
  }
}
