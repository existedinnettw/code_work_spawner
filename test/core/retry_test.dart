import 'dart:async';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_support.dart';

void registerIssueAssistantAppRunRetryTests() {
  /// ```gherkin
  /// Feature: Continuous issue polling
  ///
  ///   As a maintainer running the long-lived poller
  ///   I want transient tracker network failures to be logged without stopping the process
  ///   So that the assistant can recover automatically when connectivity returns
  /// ```
  group('IssueAssistantApp.run', () {
    /// ```gherkin
    /// Scenario: Continue polling after a transient GitHub search failure
    ///   Given a temporary project checkout that can be used as the local repo path
    ///   And a gh script that fails the first search request and succeeds afterwards
    ///   And an orchestrator-style config with a short poll interval
    ///   When the long-running app starts and enough time passes for a retry
    ///   Then the app logs the failed poll without stopping entirely
    ///   And it performs another search request after the transient failure
    /// ```
    test('Continue polling after a transient GitHub search failure', () async {
      // Given a temporary project checkout that can be used as the local repo path.
      final sandbox = await Directory.systemTemp.createTemp('cws-run-retry-');
      final repoDir = await Directory(p.join(sandbox.path, 'repo')).create();
      await initGitRepo(repoDir);

      // And a gh script that fails the first search request and succeeds afterwards.
      final ghScript = File(p.join(sandbox.path, 'gh'));
      final ghLog = File(p.join(sandbox.path, 'gh-log.jsonl'));
      final failureState = File(p.join(sandbox.path, 'search.failed.once'));
      await writeFlakySearchGhScript(
        ghScript: ghScript,
        failureStateFile: failureState,
        issueListResponse: [
          {
            'number': 81,
            'title': 'Recovered issue polling',
            'body': 'Retry should succeed.',
            'state': 'open',
            'html_url': 'https://example.test/issues/81',
            'updated_at': '2026-04-05T13:45:00Z',
            'user': {'login': 'reporter'},
            'labels': const [],
          },
        ],
        commentResponses: {
          81: [
            {
              'id': 810,
              'body': 'connectivity recovered',
              'html_url': 'https://example.test/issues/81#issuecomment-810',
              'created_at': '2026-04-05T13:45:00Z',
              'updated_at': '2026-04-05T13:45:00Z',
              'user': {'login': 'reporter'},
            },
          ],
        },
        ghLog: ghLog,
      );

      // And an orchestrator-style config with a short poll interval.
      final configFile = File(p.join(sandbox.path, 'CWS_conf.yaml'));
      await configFile.writeAsString('''
defaults:
  issueAssistant:
    enabled: true
projects:
  sample:
    issueTracker:
      eventSource:
        pollInterval: 1s
    repo: owner/sample
    path: ${repoDir.path}
''');
      final app = await IssueAssistantApp.open(
        config: await AppConfig.load(configFile.path),
        databasePath: p.join(sandbox.path, 'state.sqlite3'),
        ghCommand: ghScript.path,
        responderRunner: fakeResponderRunner(),
        commandExecutor: fakeExternalCommandExecutor(),
      );
      final logMessages = <String>[];
      void captureLog(AppLogRecord record) {
        logMessages.add(record.message);
      }

      AppLogger.addListener(captureLog);

      // When the long-running app starts and enough time passes for a retry.
      final runFuture = app.run();
      for (var attempt = 0; attempt < 200; attempt += 1) {
        final logLines = await ghLog.exists()
            ? await ghLog.readAsLines()
            : const <String>[];
        final retrySearchCount = logLines
            .where(
              (line) =>
                  line ==
                  'api -X GET search/issues -f q=repo:owner/sample is:issue state:open -f sort=updated -f order=asc -f per_page=100 -f page=1',
            )
            .length;
        final sawRetryLog = logMessages.any(
          (message) => message.contains('will_retry=true'),
        );
        if (retrySearchCount >= 2 && sawRetryLog) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await app.close();
      await runFuture;
      AppLogger.removeListener(captureLog);

      // Then the app logs the failed poll without stopping entirely.
      expect(
        logMessages.any(
          (message) =>
              message.contains('poll tick source=startup') &&
              message.contains('error=ProcessException'),
        ),
        isTrue,
      );
      expect(
        logMessages.any((message) => message.contains('will_retry=true')),
        isTrue,
      );

      // And it performs another search request after the transient failure.
      final logLines = await ghLog.readAsLines();
      expect(
        logLines
            .where(
              (line) =>
                  line ==
                  'api -X GET search/issues -f q=repo:owner/sample is:issue state:open -f sort=updated -f order=asc -f per_page=100 -f page=1',
            )
            .length,
        greaterThanOrEqualTo(2),
      );
    });
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  registerIssueAssistantAppRunRetryTests();
}
