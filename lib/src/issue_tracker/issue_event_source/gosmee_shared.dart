import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_logger.dart';
import '../../core/process_launcher.dart';

class GosmeeShared {
  static const Duration processShutdownTimeout = Duration(seconds: 2);

  static Future<String> createChannelUrl({
    required ExternalCommandExecutor commandExecutor,
    required String gosmeeCommand,
    required String localUrl,
    required String sourceLabel,
    required void Function(String message) log,
    required void Function(String message) logDebug,
  }) async {
    final result = await commandExecutor.run(gosmeeCommand, [
      '--output',
      'json',
      'client',
      '--new-url',
      localUrl,
    ]);
    logDebug(
      '$sourceLabel channel_command_result local_url=$localUrl '
      'exit_code=${result.exitCode} stdout=${_summarizeText(result.stdout.toString())} '
      'stderr=${_summarizeText(result.stderr.toString())}',
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        gosmeeCommand,
        ['--output', 'json', 'client', '--new-url', localUrl],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    final stdoutText = result.stdout.toString().trim();
    if (stdoutText.isEmpty) {
      throw const FormatException('gosmee did not print a public URL.');
    }
    log(
      '$sourceLabel channel_raw_output local_url=$localUrl stdout=$stdoutText',
    );

    try {
      final decoded = jsonDecode(stdoutText);
      if (decoded is Map<String, dynamic>) {
        final url = decoded['url']?.toString().trim();
        if (url == null || url.isEmpty) {
          throw const FormatException(
            'gosmee JSON output did not contain a valid public URL.',
          );
        }
        return url;
      }
      if (decoded is String) {
        final url = decoded.trim();
        if (url.isEmpty) {
          throw const FormatException('gosmee did not print a public URL.');
        }
        return url;
      }
    } on FormatException {
      if (Uri.tryParse(stdoutText)?.hasScheme ?? false) {
        return stdoutText;
      }
    }

    throw const FormatException('gosmee did not print a valid public URL.');
  }

  static Future<void> terminateProcesses({
    required List<StartedExternalCommand> processes,
    required String sourceLabel,
    required void Function(String message) logError,
  }) async {
    for (final process in processes) {
      process.kill();
    }
    for (final process in processes) {
      await _awaitProcessExit(
        process: process,
        sourceLabel: sourceLabel,
        logError: logError,
      );
    }
  }

  static void pipeProcessLogs({
    required AppLogger logger,
    required String sourceLabel,
    required String projectKey,
    required Stream<List<int>> stream,
    required String level,
  }) {
    utf8.decoder.bind(stream).transform(const LineSplitter()).listen((line) {
      final message = '$sourceLabel project=$projectKey $level=$line';
      if (level == 'stderr') {
        logger.error(message);
      } else {
        logger.info(message);
      }
    });
  }

  static Future<void> _awaitProcessExit({
    required StartedExternalCommand process,
    required String sourceLabel,
    required void Function(String message) logError,
  }) async {
    try {
      await process.exitCode.timeout(processShutdownTimeout);
      return;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      return;
    }

    try {
      await process.exitCode.timeout(processShutdownTimeout);
    } on TimeoutException {
      logError(
        '$sourceLabel process did not exit after sigkill '
        'timeout_ms=${processShutdownTimeout.inMilliseconds}',
      );
    } catch (_) {}
  }

  static String _summarizeText(String value) {
    final singleLine = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= 240) {
      return singleLine.isEmpty ? '(empty)' : singleLine;
    }
    return '${singleLine.substring(0, 240)}...';
  }
}
