import 'dart:convert';

import 'package:logger/logger.dart' as logger;

typedef AppLogListener = void Function(AppLogRecord record);

enum AppLogLevel { trace, debug, info, warning, error, fatal }

class AppLogRecord {
  const AppLogRecord({
    required this.loggerName,
    required this.level,
    required this.message,
    required this.time,
    this.error,
    this.stackTrace,
  });

  final String loggerName;
  final AppLogLevel level;
  final String message;
  final DateTime time;
  final Object? error;
  final StackTrace? stackTrace;
}

class AppLogger {
  AppLogger(this.name);

  static final Set<AppLogListener> _listeners = <AppLogListener>{};
  static logger.Logger? _backend;
  static AppLogLevel _minimumLevel = AppLogLevel.info;
  static bool _useColors = false;

  final String name;

  static AppLogLevel get minimumLevel => _minimumLevel;

  static AppLogLevel resolveMinimumLevel(
    Map<String, String> environment, {
    AppLogLevel fallback = AppLogLevel.info,
  }) {
    final configuredLevel =
        environment['CWS_LOG_LEVEL'] ?? environment['LOG_LEVEL'];
    return configuredLevel == null
        ? fallback
        : parseLevel(configuredLevel) ?? fallback;
  }

  static AppLogLevel? parseLevel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'trace':
        return AppLogLevel.trace;
      case 'debug':
        return AppLogLevel.debug;
      case 'info':
        return AppLogLevel.info;
      case 'warn':
      case 'warning':
        return AppLogLevel.warning;
      case 'error':
        return AppLogLevel.error;
      case 'fatal':
        return AppLogLevel.fatal;
    }
    return null;
  }

  static void configure({
    AppLogLevel minimumLevel = AppLogLevel.info,
    bool useColors = true,
  }) {
    _minimumLevel = minimumLevel;
    _useColors = useColors;
    _backend = _createBackend();
  }

  static void addListener(AppLogListener listener) {
    _listeners.add(listener);
  }

  static bool removeListener(AppLogListener listener) {
    return _listeners.remove(listener);
  }

  void trace(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.trace, message, error: error, stackTrace: stackTrace);
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  void fatal(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.fatal, message, error: error, stackTrace: stackTrace);
  }

  void severe(String message, {Object? error, StackTrace? stackTrace}) {
    error == null && stackTrace == null
        ? this.error(message)
        : this.error(message, error: error, stackTrace: stackTrace);
  }

  void _log(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = AppLogRecord(
      loggerName: name,
      level: level,
      message: message,
      time: DateTime.now(),
      error: error,
      stackTrace: stackTrace,
    );
    for (final listener in _listeners) {
      listener(record);
    }
    (_backend ??= _createBackend()).log(
      _mapLevel(level),
      record,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static logger.Logger _createBackend() {
    return logger.Logger(
      level: _mapLevel(_minimumLevel),
      filter: logger.ProductionFilter(),
      printer: _AppLogPrinter(useColors: _useColors),
    );
  }

  static logger.Level _mapLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.trace:
        return logger.Level.trace;
      case AppLogLevel.debug:
        return logger.Level.debug;
      case AppLogLevel.info:
        return logger.Level.info;
      case AppLogLevel.warning:
        return logger.Level.warning;
      case AppLogLevel.error:
        return logger.Level.error;
      case AppLogLevel.fatal:
        return logger.Level.fatal;
    }
  }
}

class _AppLogPrinter extends logger.LogPrinter {
  _AppLogPrinter({required bool useColors}) : _useColors = useColors;

  final bool _useColors;

  static final Map<AppLogLevel, logger.AnsiColor> _levelColors = {
    AppLogLevel.trace: logger.AnsiColor.fg(logger.AnsiColor.grey(0.5)),
    AppLogLevel.debug: const logger.AnsiColor.none(),
    AppLogLevel.info: const logger.AnsiColor.fg(39),
    AppLogLevel.warning: const logger.AnsiColor.fg(214),
    AppLogLevel.error: const logger.AnsiColor.fg(196),
    AppLogLevel.fatal: const logger.AnsiColor.fg(199),
  };

  @override
  List<String> log(logger.LogEvent event) {
    final record = event.message is AppLogRecord
        ? event.message as AppLogRecord
        : AppLogRecord(
            loggerName: 'app',
            level: AppLogLevel.info,
            message: event.message.toString(),
            time: event.time,
            error: event.error,
            stackTrace: event.stackTrace,
          );
    final prefix = '[${record.loggerName}] ${_labelFor(record.level)}: ';
    final lines = <String>[
      for (final line in const LineSplitter().convert(record.message))
        _applyColor(record.level, '$prefix$line'),
    ];
    if (record.message.isEmpty) {
      lines.add(_applyColor(record.level, prefix.trimRight()));
    }
    if (record.error != null) {
      lines.add(_applyColor(record.level, '$prefix${record.error}'));
    }
    if (record.stackTrace != null) {
      lines.addAll(
        const LineSplitter()
            .convert(record.stackTrace.toString())
            .map((line) => _applyColor(record.level, '$prefix$line')),
      );
    }
    return lines;
  }

  String _applyColor(AppLogLevel level, String text) {
    if (!_useColors) {
      return text;
    }
    return (_levelColors[level] ?? const logger.AnsiColor.none())(text);
  }

  String _labelFor(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.trace:
        return 'TRACE';
      case AppLogLevel.debug:
        return 'DEBUG';
      case AppLogLevel.info:
        return 'INFO';
      case AppLogLevel.warning:
        return 'WARN';
      case AppLogLevel.error:
        return 'ERROR';
      case AppLogLevel.fatal:
        return 'FATAL';
    }
  }
}
