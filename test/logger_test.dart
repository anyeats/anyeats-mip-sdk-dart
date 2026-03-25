import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/src/utils/gs805_logger.dart';

void main() {
  group('GS805Logger', () {
    late GS805Logger logger;

    setUp(() {
      logger = GS805Logger();
      logger.setLevel(LogLevel.debug);
      logger.clearHistory();
      logger.printToConsole = false; // Disable console output in tests
    });

    test('logs at different levels', () {
      logger.debug('Test', 'Debug message');
      logger.info('Test', 'Info message');
      logger.warning('Test', 'Warning message');
      logger.error('Test', 'Error message');

      expect(logger.history.length, equals(4));
      expect(logger.history[0].level, equals(LogLevel.debug));
      expect(logger.history[1].level, equals(LogLevel.info));
      expect(logger.history[2].level, equals(LogLevel.warning));
      expect(logger.history[3].level, equals(LogLevel.error));
    });

    test('respects log level filtering', () {
      logger.setLevel(LogLevel.warning);

      logger.debug('Test', 'Debug message');
      logger.info('Test', 'Info message');
      logger.warning('Test', 'Warning message');
      logger.error('Test', 'Error message');

      expect(logger.history.length, equals(2));
      expect(logger.history[0].level, equals(LogLevel.warning));
      expect(logger.history[1].level, equals(LogLevel.error));
    });

    test('maintains history limit', () {
      logger.setMaxHistorySize(5);

      for (int i = 0; i < 10; i++) {
        logger.info('Test', 'Message $i');
      }

      expect(logger.history.length, equals(5));
      expect(logger.history.first.message, contains('Message 5'));
      expect(logger.history.last.message, contains('Message 9'));
    });

    test('clears history', () {
      logger.info('Test', 'Message 1');
      logger.info('Test', 'Message 2');

      expect(logger.history.length, equals(2));

      logger.clearHistory();

      expect(logger.history.length, equals(0));
    });

    test('filters logs by level', () {
      logger.debug('Test', 'Debug');
      logger.info('Test', 'Info');
      logger.warning('Test', 'Warning');
      logger.error('Test', 'Error');

      final errors = logger.getByLevel(LogLevel.error);
      expect(errors.length, equals(1));
      expect(errors.first.message, equals('Error'));
    });

    test('filters logs by source', () {
      logger.info('Connection', 'Connected');
      logger.info('Protocol', 'Message sent');
      logger.info('Connection', 'Disconnected');

      final connectionLogs = logger.getBySource('Connection');
      expect(connectionLogs.length, equals(2));
    });

    test('exports logs', () {
      logger.info('Test', 'Message 1');
      logger.error('Test', 'Error 1');
      logger.info('Test', 'Message 2');

      final export = logger.exportLogs();
      expect(export, contains('Message 1'));
      expect(export, contains('Error 1'));
      expect(export, contains('Message 2'));
    });

    test('exports logs with filters', () {
      logger.info('Test', 'Info message');
      logger.error('Test', 'Error message');

      final errorExport = logger.exportLogs(minLevel: LogLevel.error);
      expect(errorExport, contains('Error message'));
      expect(errorExport, isNot(contains('Info message')));
    });

    test('emits log entries to stream', () async {
      final logs = <LogEntry>[];
      final subscription = logger.stream.listen(logs.add);

      logger.info('Test', 'Message 1');
      logger.info('Test', 'Message 2');

      await Future.delayed(Duration.zero); // Let stream emit

      expect(logs.length, equals(2));
      expect(logs[0].message, equals('Message 1'));
      expect(logs[1].message, equals('Message 2'));

      await subscription.cancel();
    });

    test('log entry toString includes error and stack trace', () {
      final error = Exception('Test error');
      final stackTrace = StackTrace.current;

      logger.error('Test', 'Error occurred',
          error: error, stackTrace: stackTrace);

      final entry = logger.history.last;
      final str = entry.toString();

      expect(str, contains('Error occurred'));
      expect(str, contains('Test error'));
      expect(str, contains('Stack trace'));
    });
  });

  group('LogLevel', () {
    test('has correct ordering', () {
      expect(LogLevel.debug.level, lessThan(LogLevel.info.level));
      expect(LogLevel.info.level, lessThan(LogLevel.warning.level));
      expect(LogLevel.warning.level, lessThan(LogLevel.error.level));
      expect(LogLevel.error.level, lessThan(LogLevel.none.level));
    });

    test('has correct names', () {
      expect(LogLevel.debug.name, equals('DEBUG'));
      expect(LogLevel.info.name, equals('INFO'));
      expect(LogLevel.warning.name, equals('WARN'));
      expect(LogLevel.error.name, equals('ERROR'));
      expect(LogLevel.none.name, equals('NONE'));
    });
  });
}
