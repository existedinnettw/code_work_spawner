import 'dart:async';
import 'dart:io';

import 'package:code_work_spawner/src/core/process_launcher.dart';
import 'package:mocktail/mocktail.dart';

typedef FakeCommandHandler =
    Future<ProcessResult> Function(List<String> arguments, {Duration? timeout});

typedef FakeStartedCommandHandler =
    Future<StartedExternalCommand> Function(List<String> arguments);

final Map<String, FakeCommandHandler> fakeCommandHandlers = {};
final Map<String, FakeStartedCommandHandler> fakeStartedCommandHandlers = {};

class MockExternalCommandExecutor extends Mock
    implements ExternalCommandExecutor {}

ExternalCommandExecutor fakeExternalCommandExecutor() {
  _registerMocktailFallbackValues();
  final executor = MockExternalCommandExecutor();
  when(
    () => executor.run(
      any(),
      any<List<String>>(),
      workingDirectory: any(named: 'workingDirectory'),
      environment: any(named: 'environment'),
      includeParentEnvironment: any(named: 'includeParentEnvironment'),
      timeout: any(named: 'timeout'),
    ),
  ).thenAnswer((invocation) {
    final command = invocation.positionalArguments[0] as String;
    final arguments = invocation.positionalArguments[1] as List<String>;
    final timeout = invocation.namedArguments[#timeout] as Duration?;
    final handler = fakeCommandHandlers[command];
    if (handler == null) {
      throw StateError('No fake command registered for $command.');
    }
    return handler(arguments, timeout: timeout);
  });
  when(
    () => executor.start(
      any(),
      any<List<String>>(),
      workingDirectory: any(named: 'workingDirectory'),
      environment: any(named: 'environment'),
      includeParentEnvironment: any(named: 'includeParentEnvironment'),
      runInShell: any(named: 'runInShell'),
      mode: any(named: 'mode'),
    ),
  ).thenAnswer((invocation) {
    final command = invocation.positionalArguments[0] as String;
    final arguments = invocation.positionalArguments[1] as List<String>;
    final handler = fakeStartedCommandHandlers[command];
    if (handler == null) {
      throw StateError('No fake started command registered for $command.');
    }
    return handler(arguments);
  });
  return executor;
}

class FakeStartedExternalCommand implements StartedExternalCommand {
  FakeStartedExternalCommand({
    this.exitOnSigterm = true,
    this.exitOnSigkill = true,
    this.sigkillExitCode = 137,
  });

  final bool exitOnSigterm;
  final bool exitOnSigkill;
  final int sigkillExitCode;
  final StreamController<List<int>> _stdoutController = StreamController();
  final StreamController<List<int>> _stderrController = StreamController();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void addStdout(String text) {
    if (!_stdoutController.isClosed) {
      _stdoutController.add(systemEncoding.encode(text));
    }
  }

  void addStderr(String text) {
    if (!_stderrController.isClosed) {
      _stderrController.add(systemEncoding.encode(text));
    }
  }

  void complete([int exitCode = 0]) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(exitCode);
    }
    _stdoutController.close();
    _stderrController.close();
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (signal == ProcessSignal.sigkill) {
      if (exitOnSigkill) {
        complete(sigkillExitCode);
      }
      return true;
    }
    if (signal == ProcessSignal.sigterm && exitOnSigterm) {
      complete();
      return true;
    }
    return true;
  }
}

bool _fallbackValuesRegistered = false;

void _registerMocktailFallbackValues() {
  if (_fallbackValuesRegistered) {
    return;
  }
  _fallbackValuesRegistered = true;
  registerFallbackValue(<String>[]);
  registerFallbackValue(<String, String>{});
  registerFallbackValue(Duration.zero);
  registerFallbackValue(ProcessStartMode.normal);
}

Future<void> makeScriptExecutable(File script) async {
  if (Platform.isWindows) {
    return;
  }

  final result = await Process.run('chmod', ['+x', script.path]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'chmod',
      ['+x', script.path],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
