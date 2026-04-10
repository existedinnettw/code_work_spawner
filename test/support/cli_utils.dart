import 'dart:convert';
import 'dart:io';

import '../../bin/code_work_spawner.dart' as cli_entry;

/// Result of a [runCli] invocation.
typedef CliResult = ({int exitCode, String stdout, String stderr});

/// Runs the CLI [main] in-process, capturing stdout, stderr, and [exitCode].
///
/// Uses [IOOverrides.runZoned] so every `dart:io` write inside the CLI lands
/// in the capturing sinks rather than the real terminal.  The global
/// [exitCode] is reset to 0 both before and after the call so that
/// individual tests do not pollute each other.
Future<CliResult> runCli(List<String> args) async {
  final out = _CapturingStdout();
  final err = _CapturingStdout();
  exitCode = 0;
  try {
    await IOOverrides.runZoned<Future<void>>(
      () => cli_entry.main(args),
      stdout: () => out,
      stderr: () => err,
    );
  } catch (_) {
    // Errors surface through exitCode / captured stderr, not as exceptions.
  }
  final result = (exitCode: exitCode, stdout: out.text, stderr: err.text);
  exitCode = 0;
  return result;
}

/// A [Stdout] implementation that captures all written text into a buffer.
class _CapturingStdout implements Stdout {
  final StringBuffer _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  Encoding encoding = utf8;

  @override
  bool get hasTerminal => false;

  @override
  int get terminalColumns => throw UnsupportedError('no terminal');

  @override
  int get terminalLines => throw UnsupportedError('no terminal');

  @override
  bool get supportsAnsiEscapes => false;

  @override
  IOSink get nonBlocking => this;

  @override
  String lineTerminator = '\n';

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future<void> flush() => Future.value();

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();
}
