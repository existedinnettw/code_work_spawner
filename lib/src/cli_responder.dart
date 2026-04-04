import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'github_client.dart';

class CliResponderRunner {
  Future<ResponderResult> run({
    required CliResponderConfig responder,
    required ProjectConfig project,
    required IssueThread thread,
    required String prompt,
    required bool forceReply,
    required String workspacePath,
  }) async {
    final context = <String, String>{
      'prompt': prompt,
      'repo': project.repo,
      'project_key': project.key,
      'project_path': project.path,
      'workspace_path': workspacePath,
      'issue_number': thread.issue.number.toString(),
      'thread_json': encodePrettyJson(thread.toJson()),
      'force_reply': forceReply.toString(),
    };

    final stdinPayload = renderTemplate(responder.stdinTemplate, context);
    final process = await Process.start(
      responder.command,
      responder.args,
      workingDirectory: workspacePath,
      environment: <String, String>{
        ...Platform.environment,
        ...responder.env,
        'CWS_PROJECT_KEY': project.key,
        'CWS_REPO': project.repo,
        'CWS_PROJECT_PATH': project.path,
        'CWS_WORKSPACE_PATH': workspacePath,
        'CWS_ISSUE_NUMBER': thread.issue.number.toString(),
        'CWS_FORCE_REPLY': forceReply.toString(),
      },
    );

    process.stdin.write(stdinPayload);
    await process.stdin.close();

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

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
      throw ProcessException(
        responder.command,
        responder.args,
        stderrText.isEmpty ? stdoutText : stderrText,
        exitCode,
      );
    }

    final decoded = _decodeJson(stdoutText);
    return ResponderResult.fromJson(
      decoded,
      responderId: responder.id,
      rawStdout: stdoutText,
      rawStderr: stderrText,
    );
  }

  Map<String, dynamic> _decodeJson(String stdout) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Responder returned empty stdout.');
    }

    try {
      return (jsonDecode(trimmed) as Map).cast<String, dynamic>();
    } on FormatException {
      final first = trimmed.indexOf('{');
      final last = trimmed.lastIndexOf('}');
      if (first == -1 || last <= first) {
        rethrow;
      }
      final snippet = trimmed.substring(first, last + 1);
      return (jsonDecode(snippet) as Map).cast<String, dynamic>();
    }
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
