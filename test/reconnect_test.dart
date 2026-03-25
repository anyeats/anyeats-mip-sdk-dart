import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/src/serial/reconnect_manager.dart';

void main() {
  group('ReconnectConfig', () {
    test('creates never reconnect config', () {
      const config = ReconnectConfig.never;
      expect(config.strategy, equals(ReconnectStrategy.never));
      expect(config.maxAttempts, equals(0));
    });

    test('creates immediate reconnect config', () {
      const config = ReconnectConfig.immediate;
      expect(config.strategy, equals(ReconnectStrategy.immediate));
      expect(config.initialDelay, equals(Duration.zero));
    });

    test('creates exponential backoff config', () {
      const config = ReconnectConfig.exponentialBackoff;
      expect(config.strategy, equals(ReconnectStrategy.exponentialBackoff));
      expect(config.maxAttempts, equals(5));
      expect(config.backoffMultiplier, equals(2.0));
    });

    test('creates fixed interval config', () {
      const config = ReconnectConfig.fixedInterval;
      expect(config.strategy, equals(ReconnectStrategy.fixedInterval));
      expect(config.initialDelay, equals(Duration(seconds: 2)));
    });

    test('creates custom config', () {
      const config = ReconnectConfig(
        strategy: ReconnectStrategy.exponentialBackoff,
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 10),
        backoffMultiplier: 1.5,
      );

      expect(config.strategy, equals(ReconnectStrategy.exponentialBackoff));
      expect(config.maxAttempts, equals(3));
      expect(config.initialDelay, equals(Duration(milliseconds: 100)));
      expect(config.maxDelay, equals(Duration(seconds: 10)));
      expect(config.backoffMultiplier, equals(1.5));
    });
  });

  group('ReconnectEvent', () {
    test('creates event with all fields', () {
      const event = ReconnectEvent(
        state: ReconnectState.connecting,
        attempt: 2,
        maxAttempts: 5,
        nextAttemptDelay: Duration(seconds: 1),
        error: 'Connection failed',
      );

      expect(event.state, equals(ReconnectState.connecting));
      expect(event.attempt, equals(2));
      expect(event.maxAttempts, equals(5));
      expect(event.nextAttemptDelay, equals(Duration(seconds: 1)));
      expect(event.error, equals('Connection failed'));
    });

    test('toString includes all information', () {
      const event = ReconnectEvent(
        state: ReconnectState.waiting,
        attempt: 1,
        maxAttempts: 3,
        nextAttemptDelay: Duration(milliseconds: 500),
      );

      final str = event.toString();
      expect(str, contains('waiting'));
      expect(str, contains('attempt: 1'));
      expect(str, contains('/3'));
      expect(str, contains('500ms'));
    });
  });

  group('ReconnectStrategy', () {
    test('has all expected strategies', () {
      expect(ReconnectStrategy.values, contains(ReconnectStrategy.never));
      expect(ReconnectStrategy.values, contains(ReconnectStrategy.immediate));
      expect(
          ReconnectStrategy.values, contains(ReconnectStrategy.exponentialBackoff));
      expect(
          ReconnectStrategy.values, contains(ReconnectStrategy.fixedInterval));
    });
  });

  group('ReconnectState', () {
    test('has all expected states', () {
      expect(ReconnectState.values, contains(ReconnectState.idle));
      expect(ReconnectState.values, contains(ReconnectState.waiting));
      expect(ReconnectState.values, contains(ReconnectState.connecting));
      expect(ReconnectState.values, contains(ReconnectState.connected));
      expect(ReconnectState.values, contains(ReconnectState.failed));
    });
  });
}
