/// GS805 Serial Logger
///
/// Provides logging functionality for debugging and monitoring.

import 'dart:async';
import 'dart:collection';

/// Log level enumeration
enum LogLevel {
  /// Verbose debug information
  debug(0, 'DEBUG'),

  /// General information
  info(1, 'INFO'),

  /// Warning messages
  warning(2, 'WARN'),

  /// Error messages
  error(3, 'ERROR'),

  /// No logging
  none(99, 'NONE');

  /// Numeric level
  final int level;

  /// Display name
  final String name;

  const LogLevel(this.level, this.name);
}

/// Log entry
class LogEntry {
  /// Timestamp
  final DateTime timestamp;

  /// Log level
  final LogLevel level;

  /// Source component
  final String source;

  /// Log message
  final String message;

  /// Optional error object
  final Object? error;

  /// Optional stack trace
  final StackTrace? stackTrace;

  /// Create log entry
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final time = timestamp.toString().substring(11, 23); // HH:mm:ss.mmm
    final parts = ['[$time] [${level.name}] [$source] $message'];

    if (error != null) {
      parts.add('Error: $error');
    }

    if (stackTrace != null) {
      parts.add('Stack trace:\n$stackTrace');
    }

    return parts.join('\n');
  }
}

/// GS805 Serial Logger
///
/// Provides structured logging with configurable levels and history.
///
/// Example:
/// ```dart
/// final logger = GS805Logger();
/// logger.setLevel(LogLevel.debug);
///
/// logger.info('Connection', 'Connected to device');
/// logger.error('Protocol', 'Invalid checksum', error: exception);
/// ```
class GS805Logger {
  static final GS805Logger _instance = GS805Logger._internal();

  /// Get singleton instance
  factory GS805Logger() => _instance;

  GS805Logger._internal();

  /// Current log level
  LogLevel _level = LogLevel.info;

  /// Maximum log history size
  int _maxHistorySize = 100;

  /// Log history
  final Queue<LogEntry> _history = Queue<LogEntry>();

  /// Log stream controller
  final StreamController<LogEntry> _streamController =
      StreamController<LogEntry>.broadcast();

  /// Whether to print logs to console
  bool printToConsole = true;

  /// Get current log level
  LogLevel get level => _level;

  /// Get log history
  List<LogEntry> get history => _history.toList();

  /// Stream of log entries
  Stream<LogEntry> get stream => _streamController.stream;

  /// Set log level
  void setLevel(LogLevel level) {
    _level = level;
  }

  /// Set maximum history size
  void setMaxHistorySize(int size) {
    _maxHistorySize = size;
    _trimHistory();
  }

  /// Log debug message
  void debug(String source, String message) {
    _log(LogLevel.debug, source, message);
  }

  /// Log info message
  void info(String source, String message) {
    _log(LogLevel.info, source, message);
  }

  /// Log warning message
  void warning(String source, String message, {Object? error}) {
    _log(LogLevel.warning, source, message, error: error);
  }

  /// Log error message
  void error(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      source,
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Internal log method
  void _log(
    LogLevel level,
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Check if this level should be logged
    if (level.level < _level.level) {
      return;
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to history
    _history.add(entry);
    _trimHistory();

    // Print to console
    if (printToConsole) {
      print(entry.toString());
    }

    // Emit to stream
    _streamController.add(entry);
  }

  /// Trim history to max size
  void _trimHistory() {
    while (_history.length > _maxHistorySize) {
      _history.removeFirst();
    }
  }

  /// Clear log history
  void clearHistory() {
    _history.clear();
  }

  /// Get logs by level
  List<LogEntry> getByLevel(LogLevel level) {
    return _history.where((entry) => entry.level == level).toList();
  }

  /// Get logs by source
  List<LogEntry> getBySource(String source) {
    return _history.where((entry) => entry.source == source).toList();
  }

  /// Get logs in time range
  List<LogEntry> getInRange(DateTime start, DateTime end) {
    return _history
        .where((entry) =>
            entry.timestamp.isAfter(start) && entry.timestamp.isBefore(end))
        .toList();
  }

  /// Export logs as string
  String exportLogs({
    LogLevel? minLevel,
    String? source,
    DateTime? since,
  }) {
    var logs = _history.toList();

    if (minLevel != null) {
      logs = logs.where((entry) => entry.level.level >= minLevel.level).toList();
    }

    if (source != null) {
      logs = logs.where((entry) => entry.source == source).toList();
    }

    if (since != null) {
      logs = logs.where((entry) => entry.timestamp.isAfter(since)).toList();
    }

    return logs.map((entry) => entry.toString()).join('\n\n');
  }

  /// Dispose logger
  void dispose() {
    _streamController.close();
  }
}
