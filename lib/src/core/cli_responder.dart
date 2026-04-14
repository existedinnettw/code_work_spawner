import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/config.dart';
import '../issue_tracker/issue_tracker_client.dart';
import 'process_launcher.dart';

class CliResponderRunner {
  Future<ResponderResult> run({
    required CliResponderConfig responder,
    required ProjectConfig project,
    required IssueThread thread,
    required String prompt,
    required String workspacePath,
  }) async {
    final context = _buildContext(
      project: project,
      thread: thread,
      prompt: prompt,
      workspacePath: workspacePath,
    );

    var output = await _runProcess(
      responder: responder,
      context: context,
      workspacePath: workspacePath,
    );
    var decoded = _tryDecodeJson(output.stdout);
    if (decoded == null && _canRepairJsonOutput(responder, output.stdout)) {
      final repairContext = _buildContext(
        project: project,
        thread: thread,
        prompt: _buildJsonRepairPrompt(prompt, output.stdout),
        workspacePath: workspacePath,
      );
      final repairOutput = await _runProcess(
        responder: responder,
        context: repairContext,
        workspacePath: workspacePath,
      );
      final repairDecoded = _tryDecodeJson(repairOutput.stdout);
      if (repairDecoded != null) {
        output = repairOutput;
        decoded = repairDecoded;
      }
    }

    if (decoded == null) {
      throw CliResponderOutputFormatException(
        responderId: responder.id,
        command: responder.command,
        arguments: output.arguments,
        error: _decodeFormatException(output.stdout),
        rawStdout: output.stdout,
        rawStderr: output.stderr,
      );
    }
    return ResponderResult.fromJson(
      decoded,
      responderId: responder.id,
      rawStdout: output.stdout,
      rawStderr: output.stderr,
    );
  }

  Map<String, String> _buildContext({
    required ProjectConfig project,
    required IssueThread thread,
    required String prompt,
    required String workspacePath,
  }) {
    return <String, String>{
      'prompt': prompt,
      'repo': project.repo,
      'project_key': project.key,
      'project_path': project.path,
      'workspace_path': workspacePath,
      'issue_number': thread.issue.number.toString(),
      'thread_json': encodePrettyJson(thread.toJson()),
    };
  }

  Future<_RawResponderOutput> _runProcess({
    required CliResponderConfig responder,
    required Map<String, String> context,
    required String workspacePath,
  }) async {
    final stdinPayload = renderTemplate(responder.stdinTemplate, context);
    final arguments = responder.args
        .map((argument) => renderTemplate(argument, context))
        .toList(growable: false);
    final process = await startExternalCommand(
      responder.command,
      arguments,
      workingDirectory: workspacePath,
      environment: <String, String>{
        ...responder.env,
        'CWS_PROJECT_KEY': context['project_key'] ?? '',
        'CWS_REPO': context['repo'] ?? '',
        'CWS_PROJECT_PATH': context['project_path'] ?? '',
        'CWS_WORKSPACE_PATH': workspacePath,
        'CWS_ISSUE_NUMBER': context['issue_number'] ?? '',
      },
    );

    process.stdin.write(stdinPayload);
    await process.stdin.close();

    const outputDecoder = Utf8Decoder(allowMalformed: true);
    final stdoutFuture = process.stdout.transform(outputDecoder).join();
    final stderrFuture = process.stderr.transform(outputDecoder).join();

    late final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(responder.timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw TimeoutException(
        'Responder "${responder.id}" timed out after ${responder.timeout}.',
      );
    }

    final stdoutText = await stdoutFuture;
    final stderrText = await stderrFuture;
    if (exitCode != 0) {
      throw CliResponderExecutionException(
        responderId: responder.id,
        command: responder.command,
        arguments: arguments,
        exitCode: exitCode,
        rawStdout: stdoutText,
        rawStderr: stderrText,
      );
    }

    return _RawResponderOutput(
      arguments: arguments,
      stdout: stdoutText,
      stderr: stderrText,
    );
  }

  Map<String, dynamic>? _tryDecodeJson(String stdout) {
    try {
      return _decodeJson(stdout);
    } on FormatException {
      return null;
    }
  }

  FormatException _decodeFormatException(String stdout) {
    try {
      _decodeJson(stdout);
      return const FormatException('Responder output was not valid JSON.');
    } on FormatException catch (error) {
      return error;
    }
  }

  bool _canRepairJsonOutput(CliResponderConfig responder, String stdout) {
    if (stdout.trim().isEmpty) {
      return false;
    }
    final command = responder.command.toLowerCase();
    final id = responder.id.toLowerCase();
    return id.contains('copilot') || command.contains('copilot');
  }

  String _buildJsonRepairPrompt(String originalPrompt, String invalidOutput) {
    return '''
The previous responder output was invalid because it was not a JSON object.

Invalid output:
$invalidOutput

Your task is to repair the response for the original request below. Do not
acknowledge this message, do not use tools, do not inspect files, and do not
include Markdown fences or prose.

Return exactly one JSON object matching this schema:
{
  "decision": "reply" | "no_reply",
  "mode": "planning" | "bug_verification",
  "markdown": "markdown response, omitted for no_reply",
  "summary": "short internal summary"
}

Original request:
$originalPrompt
''';
  }

  Map<String, dynamic> _decodeJson(String stdout) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Responder returned empty stdout.');
    }

    try {
      return (jsonDecode(trimmed) as Map).cast<String, dynamic>();
    } on FormatException {
      final eventJson = _decodeJsonlEvents(trimmed);
      if (eventJson != null) {
        return eventJson;
      }

      final first = trimmed.indexOf('{');
      final last = trimmed.lastIndexOf('}');
      if (first == -1 || last <= first) {
        rethrow;
      }
      final snippet = trimmed.substring(first, last + 1);
      return (jsonDecode(snippet) as Map).cast<String, dynamic>();
    }
  }

  Map<String, dynamic>? _decodeJsonlEvents(String stdout) {
    Map<String, dynamic>? lastEvent;
    String? lastAssistantMessageContent;
    for (final line in const LineSplitter().convert(stdout)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) {
        continue;
      }

      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          continue;
        }
        lastEvent = decoded.cast<String, dynamic>();
        final copilotMessageContent = _readCopilotAssistantMessageContent(
          lastEvent,
        );
        if (copilotMessageContent != null) {
          lastAssistantMessageContent = copilotMessageContent;
          final decodedContent = _decodeJsonObjectFromText(
            copilotMessageContent,
          );
          if (decodedContent != null) {
            return decodedContent;
          }
        }

        final item = lastEvent['item'];
        if (item is Map &&
            item['type']?.toString() == 'agent_message' &&
            item['text'] is String) {
          final text = (item['text'] as String).trim();
          final decodedText = _decodeJsonObjectFromText(text);
          if (decodedText != null) {
            return decodedText;
          }
        }
      } on FormatException {
        continue;
      }
    }

    if (lastEvent case {'text': final String text}) {
      final trimmed = text.trim();
      if (trimmed.startsWith('{')) {
        return (jsonDecode(trimmed) as Map).cast<String, dynamic>();
      }
    }
    if (lastAssistantMessageContent != null) {
      return _decodeJsonObjectFromText(lastAssistantMessageContent);
    }

    return null;
  }

  String? _readCopilotAssistantMessageContent(Map<String, dynamic> event) {
    if (event['type'] != 'assistant.message') {
      return null;
    }
    final data = event['data'];
    if (data is! Map) {
      return null;
    }
    final content = data['content'];
    return content is String ? content : null;
  }

  Map<String, dynamic>? _decodeJsonObjectFromText(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }
    try {
      return (jsonDecode(trimmed) as Map).cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }
}

class _RawResponderOutput {
  _RawResponderOutput({
    required this.arguments,
    required this.stdout,
    required this.stderr,
  });

  final List<String> arguments;
  final String stdout;
  final String stderr;
}

class CliResponderExecutionException implements Exception {
  CliResponderExecutionException({
    required this.responderId,
    required this.command,
    required this.arguments,
    required this.exitCode,
    required this.rawStdout,
    required this.rawStderr,
  });

  final String responderId;
  final String command;
  final List<String> arguments;
  final int exitCode;
  final String rawStdout;
  final String rawStderr;

  @override
  String toString() {
    final details = rawStderr.isEmpty ? rawStdout : rawStderr;
    return 'CliResponderExecutionException(responderId: $responderId, '
        'command: $command, exitCode: $exitCode, details: $details)';
  }
}

class CliResponderOutputFormatException implements Exception {
  CliResponderOutputFormatException({
    required this.responderId,
    required this.command,
    required this.arguments,
    required this.error,
    required this.rawStdout,
    required this.rawStderr,
  });

  final String responderId;
  final String command;
  final List<String> arguments;
  final FormatException error;
  final String rawStdout;
  final String rawStderr;

  @override
  String toString() {
    return 'CliResponderOutputFormatException(responderId: $responderId, '
        'command: $command, details: $error)';
  }
}

class ResponderResult {
  ResponderResult({
    required this.responderId,
    required this.decision,
    required this.mode,
    required this.markdown,
    required this.summary,
    required this.rawStdout,
    required this.rawStderr,
  });

  final String responderId;
  final String decision;
  final String mode;
  final String markdown;
  final String summary;
  final String rawStdout;
  final String rawStderr;

  bool get shouldReply => decision == 'reply';

  factory ResponderResult.fromJson(
    Map<String, dynamic> json, {
    required String responderId,
    required String rawStdout,
    required String rawStderr,
  }) {
    final decision = json['decision']?.toString() ?? 'no_reply';
    final mode = json['mode']?.toString() ?? 'planning';
    final markdown = json['markdown']?.toString() ?? '';
    final summary = json['summary']?.toString() ?? '';
    if (decision != 'reply' && decision != 'no_reply') {
      throw FormatException('Invalid decision "$decision".');
    }
    return ResponderResult(
      responderId: responderId,
      decision: decision,
      mode: mode,
      markdown: markdown,
      summary: summary,
      rawStdout: rawStdout,
      rawStderr: rawStderr,
    );
  }
}
