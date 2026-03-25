import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/src/utils/command_queue.dart';
import 'package:gs805serial/src/protocol/gs805_message.dart';
import 'package:gs805serial/src/protocol/gs805_protocol.dart';

void main() {
  group('CommandQueue', () {
    late CommandQueue queue;
    late List<CommandMessage> executedCommands;
    late int commandDelay;

    setUp(() {
      executedCommands = [];
      commandDelay = 10; // 10ms delay per command

      queue = CommandQueue(
        sendFunction: (cmd) async {
          executedCommands.add(cmd);
          await Future.delayed(Duration(milliseconds: commandDelay));
          // Return a mock response
          return ResponseMessage(
            command: cmd.command,
            data: Uint8List.fromList([0x00]), // Status code: success
          );
        },
      );
    });

    tearDown(() {
      if (queue.status != QueueStatus.disposed) {
        queue.dispose();
      }
    });

    test('enqueues and executes commands sequentially', () async {
      final cmd1 = GS805Protocol.getMachineStatusCommand();
      final cmd2 = GS805Protocol.getBalanceCommand();
      final cmd3 = GS805Protocol.getErrorCodeCommand();

      // Enqueue all commands
      final future1 = queue.enqueue(cmd1);
      final future2 = queue.enqueue(cmd2);
      final future3 = queue.enqueue(cmd3);

      // Wait for all to complete
      await Future.wait([future1, future2, future3]);

      // Check they were executed in order
      expect(executedCommands.length, equals(3));
      expect(executedCommands[0].command, equals(cmd1.command));
      expect(executedCommands[1].command, equals(cmd2.command));
      expect(executedCommands[2].command, equals(cmd3.command));
    });

    test('returns response for each command', () async {
      final cmd = GS805Protocol.getMachineStatusCommand();
      final response = await queue.enqueue(cmd);

      expect(response, isNotNull);
      expect(response, isA<ResponseMessage>());
    });

    test('queue starts as idle', () {
      expect(queue.status, equals(QueueStatus.idle));
      expect(queue.isEmpty, isTrue);
      expect(queue.length, equals(0));
    });

    test('queue becomes processing when commands are added', () async {
      final cmd = GS805Protocol.getMachineStatusCommand();
      final future = queue.enqueue(cmd);

      // Queue should be processing now
      await Future.delayed(Duration(milliseconds: 1));
      expect(queue.isProcessing, isTrue);

      await future;
    });

    test('queue returns to idle when empty', () async {
      final cmd = GS805Protocol.getMachineStatusCommand();
      await queue.enqueue(cmd);

      expect(queue.status, equals(QueueStatus.idle));
      expect(queue.isEmpty, isTrue);
    });

    test('retries failed commands', () async {
      int attemptCount = 0;

      final failingQueue = CommandQueue(
        sendFunction: (cmd) async {
          attemptCount++;
          if (attemptCount < 3) {
            throw Exception('Simulated failure');
          }
          return ResponseMessage(
            command: cmd.command,
            data: Uint8List.fromList([0x00]),
          );
        },
      );

      final cmd = GS805Protocol.getMachineStatusCommand();
      await failingQueue.enqueue(cmd, maxRetries: 3);

      expect(attemptCount, equals(3));

      failingQueue.dispose();
    });

    test('fails after max retries', () async {
      final failingQueue = CommandQueue(
        sendFunction: (cmd) async {
          throw Exception('Always fails');
        },
      );

      final cmd = GS805Protocol.getMachineStatusCommand();

      try {
        await failingQueue.enqueue(cmd, maxRetries: 2);
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e, isA<Exception>());
      } finally {
        failingQueue.dispose();
      }
    });

    test('can be paused and resumed', () async {
      final cmd1 = GS805Protocol.getMachineStatusCommand();
      final cmd2 = GS805Protocol.getBalanceCommand();

      queue.enqueue(cmd1);
      queue.enqueue(cmd2);

      // Pause after first command starts
      await Future.delayed(Duration(milliseconds: 5));
      queue.pause();

      expect(queue.status, equals(QueueStatus.paused));
      expect(executedCommands.length, lessThan(2));

      // Resume
      queue.resume();
      await Future.delayed(Duration(milliseconds: 50));

      expect(executedCommands.length, equals(2));
    });

    test('can be cleared', () async {
      final cmd1 = GS805Protocol.getMachineStatusCommand();
      final cmd2 = GS805Protocol.getBalanceCommand();
      final cmd3 = GS805Protocol.getErrorCodeCommand();

      final future1 = queue.enqueue(cmd1);
      final future2 = queue.enqueue(cmd2);
      final future3 = queue.enqueue(cmd3);

      // Clear immediately
      queue.clear();

      expect(queue.isEmpty, isTrue);

      // Commands should fail
      expect(() => future2, throwsA(isA<CommandQueueException>()));
      expect(() => future3, throwsA(isA<CommandQueueException>()));

      // Wait for first command to complete (it was already executing)
      await future1;
    });

    test('emits queue events', () async {
      final events = <QueueEvent>[];
      final subscription = queue.eventStream.listen(events.add);

      final cmd = GS805Protocol.getMachineStatusCommand();
      await queue.enqueue(cmd);

      await Future.delayed(Duration.zero);

      // Should have: added, started, completed
      expect(events.length, greaterThanOrEqualTo(3));
      expect(events.any((e) => e.type == QueueEventType.commandAdded), isTrue);
      expect(
          events.any((e) => e.type == QueueEventType.commandStarted), isTrue);
      expect(events.any((e) => e.type == QueueEventType.commandCompleted),
          isTrue);

      await subscription.cancel();
    });

    test('tracks pending commands', () async {
      final cmd1 = GS805Protocol.getMachineStatusCommand();
      final cmd2 = GS805Protocol.getBalanceCommand();

      final future1 = queue.enqueue(cmd1);
      final future2 = queue.enqueue(cmd2);

      // Pause to keep commands in queue
      await Future.delayed(Duration(milliseconds: 1));
      queue.pause();

      final pending = queue.getPendingCommands();
      expect(pending.length, greaterThan(0));

      // Resume and wait for completion to avoid tearDown issues
      queue.resume();
      await Future.wait([future1, future2]);
    });

    test('throws when enqueuing to disposed queue', () {
      queue.dispose();

      expect(
        () => queue.enqueue(GS805Protocol.getMachineStatusCommand()),
        throwsStateError,
      );
    });
  });

  group('QueuedCommand', () {
    test('tracks attempt count', () {
      final cmd = QueuedCommand(
        id: 'test',
        command: GS805Protocol.getMachineStatusCommand(),
        maxRetries: 3,
      );

      expect(cmd.hasRetriesLeft, isTrue);
      expect(cmd.currentAttempt, equals(0));

      cmd.currentAttempt++;
      expect(cmd.hasRetriesLeft, isTrue);

      cmd.currentAttempt++;
      cmd.currentAttempt++;
      expect(cmd.hasRetriesLeft, isFalse);
    });

    test('toString includes relevant info', () {
      final cmd = QueuedCommand(
        id: 'test-123',
        command: GS805Protocol.getMachineStatusCommand(),
        maxRetries: 3,
      );

      final str = cmd.toString();
      expect(str, contains('test-123'));
      expect(str, contains('0/3'));
    });
  });

  group('QueueEvent', () {
    test('creates event with timestamp', () {
      final event = QueueEvent(
        type: QueueEventType.commandAdded,
        message: 'Test message',
      );

      expect(event.type, equals(QueueEventType.commandAdded));
      expect(event.message, equals('Test message'));
      expect(event.timestamp, isA<DateTime>());
    });

    test('toString includes type and message', () {
      final event = QueueEvent(
        type: QueueEventType.commandCompleted,
        message: 'Command finished',
      );

      final str = event.toString();
      expect(str, contains('commandCompleted'));
      expect(str, contains('Command finished'));
    });
  });
}
