import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:code_work_spawner/src/core/cli_responder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: CLI responder execution
  ///
  ///   As a user configuring external responder CLIs
  ///   I want responder arguments to receive the generated issue prompt
  ///   So that prompt-based tools such as Copilot CLI are invoked with valid arguments
  /// ```
  group('CliResponderRunner.run', () {
    /// ```gherkin
    /// Scenario: Render prompt placeholders in responder arguments
    ///   Given a responder command whose arguments contain prompt and repo placeholders
    ///   When the CLI responder runner starts the external command
    ///   Then the launched command receives rendered argument values
    ///   And the responder output is decoded as a normal response
    /// ```
    test('Render prompt placeholders in responder arguments', () async {
      // Given a responder command whose arguments contain prompt and repo placeholders.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-cli-responder-',
      );
      final scriptFile = File(p.join(sandbox.path, 'responder.dart'));
      final argCaptureFile = File(p.join(sandbox.path, 'args.json'));
      await scriptFile.writeAsString('''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  File(Platform.environment['ARG_CAPTURE']!).writeAsStringSync(jsonEncode(args));
  stdout.write(jsonEncode({
    'decision': 'no_reply',
    'mode': 'planning',
    'summary': 'captured rendered args',
  }));
}
''');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: prompt-cli
        command: ${jsonEncode(Platform.resolvedExecutable)}
        args:
          - ${jsonEncode(scriptFile.path)}
          - --prompt
          - "{{prompt}}"
          - --repo
          - "{{repo}}"
        env:
          ARG_CAPTURE: ${jsonEncode(argCaptureFile.path)}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${jsonEncode(sandbox.path)}
''');
      final config = await AppConfig.load(configFile.path);
      final project = config.projects['sample']!;
      final thread = IssueThread(
        issue: GitHubIssueSummary(
          trackerProject: 'owner/sample',
          repoSlug: project.repoSlug,
          number: 7,
          title: 'Prompt argument handling',
          body: 'The prompt flag needs a value.',
          state: 'open',
          url: 'https://example.test/issues/7',
          updatedAt: DateTime.utc(2026, 4, 14),
          userLogin: 'reporter',
          labels: const [],
        ),
        comments: const [],
      );

      // When the CLI responder runner starts the external command.
      final result = await CliResponderRunner().run(
        responder: project.issueAssistant.responders.single,
        project: project,
        thread: thread,
        prompt: 'Respond to owner/sample issue #7',
        workspacePath: sandbox.path,
      );

      // Then the launched command receives rendered argument values.
      final capturedArgs =
          (jsonDecode(await argCaptureFile.readAsString()) as List)
              .cast<String>();
      expect(capturedArgs, [
        '--prompt',
        'Respond to owner/sample issue #7',
        '--repo',
        'owner/sample',
      ]);

      // And the responder output is decoded as a normal response.
      expect(result.decision, 'no_reply');
      expect(result.summary, 'captured rendered args');
    });

    /// ```gherkin
    /// Scenario: Render Copilot responder arguments for silent JSON output
    ///   Given a Copilot-style responder command with a prompt placeholder and silent output flag
    ///   When the CLI responder runner starts the external command
    ///   Then the launched command receives the prompt before permission and mode flags
    ///   And the launched command keeps custom instructions enabled
    ///   And the launched command avoids JSONL output mode
    /// ```
    test('Render Copilot responder arguments for silent JSON output', () async {
      // Given a Copilot-style responder command with a prompt placeholder and silent output flag.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-copilot-args-',
      );
      final scriptFile = File(p.join(sandbox.path, 'responder.dart'));
      final argCaptureFile = File(p.join(sandbox.path, 'args.json'));
      final stdinCaptureFile = File(p.join(sandbox.path, 'stdin.txt'));
      await scriptFile.writeAsString('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  File(Platform.environment['ARG_CAPTURE']!).writeAsStringSync(jsonEncode(args));
  File(Platform.environment['STDIN_CAPTURE']!).writeAsStringSync(
    await utf8.decoder.bind(stdin).join(),
  );
  stdout.write(jsonEncode({
    'decision': 'no_reply',
    'mode': 'planning',
    'summary': 'captured copilot args',
  }));
}
''');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: copilot-cli
        command: ${jsonEncode(Platform.resolvedExecutable)}
        args:
          - ${jsonEncode(scriptFile.path)}
          - "-p"
          - ""
          - "--allow-all"
          - "--autopilot"
          - "--silent"
        env:
          ARG_CAPTURE: ${jsonEncode(argCaptureFile.path)}
          STDIN_CAPTURE: ${jsonEncode(stdinCaptureFile.path)}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${jsonEncode(sandbox.path)}
''');
      final config = await AppConfig.load(configFile.path);
      final project = config.projects['sample']!;
      final thread = IssueThread(
        issue: GitHubIssueSummary(
          trackerProject: 'owner/sample',
          repoSlug: project.repoSlug,
          number: 9,
          title: 'Copilot silent output',
          body: 'The responder needs parseable stdout.',
          state: 'open',
          url: 'https://example.test/issues/9',
          updatedAt: DateTime.utc(2026, 4, 14),
          userLogin: 'reporter',
          labels: const [],
        ),
        comments: const [],
      );

      // When the CLI responder runner starts the external command.
      final result = await CliResponderRunner().run(
        responder: project.issueAssistant.responders.single,
        project: project,
        thread: thread,
        prompt: 'Return JSON only',
        workspacePath: sandbox.path,
      );

      // Then the launched command receives an empty prompt argument before permission and mode flags.
      final capturedArgs =
          (jsonDecode(await argCaptureFile.readAsString()) as List)
              .cast<String>();
      expect(capturedArgs, [
        '-p',
        '',
        '--allow-all',
        '--autopilot',
        '--silent',
      ]);

      // And the launched command keeps custom instructions enabled.
      expect(capturedArgs, isNot(contains('--no-custom-instructions')));

      // And the launched command avoids JSONL output mode.
      expect(capturedArgs, isNot(contains('--output-format')));
      expect(await stdinCaptureFile.readAsString(), 'Return JSON only');
      expect(result.summary, 'captured copilot args');
    });

    /// ```gherkin
    /// Scenario: Repair invalid Copilot text output once
    ///   Given a Copilot-style responder command that first returns an acknowledgement instead of JSON
    ///   And the same responder can return strict JSON when given a repair prompt
    ///   When the CLI responder runner decodes the responder output
    ///   Then it retries the Copilot responder once with the repair prompt
    ///   And it returns the repaired JSON response
    /// ```
    test('Repair invalid Copilot text output once', () async {
      // Given a Copilot-style responder command that first returns an acknowledgement instead of JSON.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-copilot-repair-',
      );
      final scriptFile = File(p.join(sandbox.path, 'responder.dart'));
      final promptCaptureFile = File(p.join(sandbox.path, 'prompts.json'));
      await scriptFile.writeAsString('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final prompt = await utf8.decoder.bind(stdin).join();
  final capture = File(Platform.environment['PROMPT_CAPTURE']!);
  final prompts = capture.existsSync()
      ? (jsonDecode(capture.readAsStringSync()) as List)
      : <Object?>[];
  prompts.add(prompt);
  capture.writeAsStringSync(jsonEncode(prompts));
  if (prompts.length == 1) {
    stdout.write('Understood.');
    return;
  }
  stdout.write(jsonEncode({
    'decision': 'no_reply',
    'mode': 'planning',
    'summary': 'repaired invalid copilot output',
  }));
}
''');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: copilot-cli
        command: ${jsonEncode(Platform.resolvedExecutable)}
        args:
          - ${jsonEncode(scriptFile.path)}
          - "-p"
          - ""
          - "--allow-all"
          - "--autopilot"
          - "--silent"
        env:
          PROMPT_CAPTURE: ${jsonEncode(promptCaptureFile.path)}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${jsonEncode(sandbox.path)}
''');
      final config = await AppConfig.load(configFile.path);
      final project = config.projects['sample']!;
      final thread = IssueThread(
        issue: GitHubIssueSummary(
          trackerProject: 'owner/sample',
          repoSlug: project.repoSlug,
          number: 10,
          title: 'Copilot acknowledgement repair',
          body: 'The responder returned Understood.',
          state: 'open',
          url: 'https://example.test/issues/10',
          updatedAt: DateTime.utc(2026, 4, 14),
          userLogin: 'reporter',
          labels: const [],
        ),
        comments: const [],
      );

      // And the same responder can return strict JSON when given a repair prompt.

      // When the CLI responder runner decodes the responder output.
      final result = await CliResponderRunner().run(
        responder: project.issueAssistant.responders.single,
        project: project,
        thread: thread,
        prompt: 'Classify the issue thread',
        workspacePath: sandbox.path,
      );

      // Then it retries the Copilot responder once with the repair prompt.
      final capturedPrompts =
          (jsonDecode(await promptCaptureFile.readAsString()) as List)
              .cast<String>();
      expect(capturedPrompts, hasLength(2));
      expect(capturedPrompts.last, contains('Invalid output:'));
      expect(capturedPrompts.last, contains('Understood.'));

      // And it returns the repaired JSON response.
      expect(result.decision, 'no_reply');
      expect(result.summary, 'repaired invalid copilot output');
    });

    /// ```gherkin
    /// Scenario: Tolerate malformed responder diagnostics
    ///   Given a responder command that writes malformed UTF-8 bytes to stderr
    ///   And the responder writes valid JSON to stdout
    ///   When the CLI responder runner reads the process output
    ///   Then it still decodes the JSON response
    /// ```
    test('Tolerate malformed responder diagnostics', () async {
      // Given a responder command that writes malformed UTF-8 bytes to stderr.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-malformed-stderr-',
      );
      final scriptFile = File(p.join(sandbox.path, 'responder.dart'));
      await scriptFile.writeAsString('''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  stderr.add([0xA1]);
  stdout.write(jsonEncode({
    'decision': 'no_reply',
    'mode': 'planning',
    'summary': 'ignored malformed stderr',
  }));
}
''');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: malformed-diagnostics
        command: ${jsonEncode(Platform.resolvedExecutable)}
        args:
          - ${jsonEncode(scriptFile.path)}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${jsonEncode(sandbox.path)}
''');
      final config = await AppConfig.load(configFile.path);
      final project = config.projects['sample']!;
      final thread = IssueThread(
        issue: GitHubIssueSummary(
          trackerProject: 'owner/sample',
          repoSlug: project.repoSlug,
          number: 11,
          title: 'Malformed diagnostics',
          body: 'The responder writes non-UTF-8 diagnostics.',
          state: 'open',
          url: 'https://example.test/issues/11',
          updatedAt: DateTime.utc(2026, 4, 14),
          userLogin: 'reporter',
          labels: const [],
        ),
        comments: const [],
      );

      // And the responder writes valid JSON to stdout.

      // When the CLI responder runner reads the process output.
      final result = await CliResponderRunner().run(
        responder: project.issueAssistant.responders.single,
        project: project,
        thread: thread,
        prompt: 'Return JSON only',
        workspacePath: sandbox.path,
      );

      // Then it still decodes the JSON response.
      expect(result.decision, 'no_reply');
      expect(result.summary, 'ignored malformed stderr');
    });

    /// ```gherkin
    /// Scenario: Decode Copilot CLI JSONL assistant messages
    ///   Given a responder command that emits Copilot CLI JSONL events
    ///   When the CLI responder runner reads the assistant.message event
    ///   Then it decodes the responder JSON from the event data content
    /// ```
    test('Decode Copilot CLI JSONL assistant messages', () async {
      // Given a responder command that emits Copilot CLI JSONL events.
      final sandbox = await Directory.systemTemp.createTemp(
        'cws-copilot-jsonl-',
      );
      final scriptFile = File(p.join(sandbox.path, 'responder.dart'));
      await scriptFile.writeAsString('''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  stdout.writeln(jsonEncode({
    'type': 'session.mcp_servers_loaded',
    'data': {'servers': []},
  }));
  stdout.writeln(jsonEncode({
    'type': 'assistant.message',
    'data': {
      'content': jsonEncode({
        'decision': 'reply',
        'mode': 'planning',
        'markdown': 'Use the existing boundary.',
        'summary': 'decoded copilot jsonl',
      }),
    },
  }));
  stdout.writeln(jsonEncode({
    'type': 'result',
    'exitCode': 0,
  }));
}
''');
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    responders:
      - id: copilot-cli
        command: ${jsonEncode(Platform.resolvedExecutable)}
        args:
          - ${jsonEncode(scriptFile.path)}
        timeout: 1m
projects:
  sample:
    repo: owner/sample
    path: ${jsonEncode(sandbox.path)}
''');
      final config = await AppConfig.load(configFile.path);
      final project = config.projects['sample']!;
      final thread = IssueThread(
        issue: GitHubIssueSummary(
          trackerProject: 'owner/sample',
          repoSlug: project.repoSlug,
          number: 8,
          title: 'Copilot JSONL handling',
          body: 'Copilot emits assistant.message events.',
          state: 'open',
          url: 'https://example.test/issues/8',
          updatedAt: DateTime.utc(2026, 4, 14),
          userLogin: 'reporter',
          labels: const [],
        ),
        comments: const [],
      );

      // When the CLI responder runner reads the assistant.message event.
      final result = await CliResponderRunner().run(
        responder: project.issueAssistant.responders.single,
        project: project,
        thread: thread,
        prompt: 'Respond with JSON',
        workspacePath: sandbox.path,
      );

      // Then it decodes the responder JSON from the event data content.
      expect(result.decision, 'reply');
      expect(result.mode, 'planning');
      expect(result.markdown, 'Use the existing boundary.');
      expect(result.summary, 'decoded copilot jsonl');
    });
  });
}
