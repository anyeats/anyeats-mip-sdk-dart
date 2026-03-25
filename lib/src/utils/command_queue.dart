/// Command Queue Management
///
/// Manages sequential execution of commands with retry logic.

import 'dart:async';
import 'dart:collection';
import 'package:gs805serial/src/protocol/gs805_message.dart';
import 'package:gs805serial/src/exceptions/gs805_exception.dart';

/// Command queue item
class QueuedCommand {
  /// Unique command ID
  final String id;

  /// Command message
  final CommandMessage command;

  /// Retry count
  final int maxRetries;

  /// Current attempt number
  int currentAttempt;

  /// Timeout duration
  final Duration timeout;

  /// Completion completer
  final Completer<ResponseMessage> completer;

  /// Timestamp when added
  final DateTime addedAt;

  /// Timestamp when started
  DateTime? startedAt;

  /// Timestamp when completed
  DateTime? completedAt;

  /// Last error (if any)
  Object? lastError;

  /// Create queued command
  QueuedCommand({
    required this.id,
    required this.command,
    this.maxRetries = 3,
    this.currentAttempt = 0,
    this.timeout = const Duration(milliseconds: 100),
  })  : completer = Completer<ResponseMessage>(),
        addedAt = DateTime.now();

  /// Whether command has more retries available
  bool get hasRetriesLeft => currentAttempt < maxRetries;

  /// Duration since added
  Duration get waitingTime =>
      startedAt?.difference(addedAt) ?? DateTime.now().difference(addedAt);

  /// Duration since started
  Duration? get executionTime => startedAt != null
      ? (completedAt ?? DateTime.now()).difference(startedAt!)
      : null;

  @override
  String toString() {
    return 'QueuedCommand(id: $id, command: 0x${command.command.toRadixString(16)}, '
        'attempt: $currentAttempt/$maxRetries, waiting: ${waitingTime.inMilliseconds}ms)';
  }
}

/// Command queue status
enum QueueStatus {
  /// Queue is idle
  idle,

  /// Queue is processing commands
  processing,

  /// Queue is paused
  paused,

  /// Queue is disposed
  disposed,
}

/// Command queue event
class QueueEvent {
  /// Event type
  final QueueEventType type;

  /// Related command
  final QueuedCommand? command;

  /// Event message
  final String message;

  /// Timestamp
  final DateTime timestamp;

  /// Create queue event
  QueueEvent({
    required this.type,
    this.command,
    required this.message,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return '${type.name}: $message';
  }
}

/// Queue event types
enum QueueEventType {
  /// Command added to queue
  commandAdded,

  /// Command started execution
  commandStarted,

  /// Command completed successfully
  commandCompleted,

  /// Command failed
  commandFailed,

  /// Command retrying
  commandRetrying,

  /// Queue started
  queueStarted,

  /// Queue paused
  queuePaused,

  /// Queue resumed
  queueResumed,

  /// Queue cleared
  queueCleared,
}

/// Command Queue Manager
///
/// Manages sequential execution of commands with automatic retry logic.
///
/// Example:
/// ```dart
/// final queue = CommandQueue(
///   sendFunction: (cmd) => serialManager.sendCommand(cmd),
/// );
///
/// // Add commands
/// final response = await queue.enqueue(command);
///
/// // Monitor queue
/// queue.eventStream.listen((event) {
///   print('Queue event: $event');
/// });
/// ```
class CommandQueue {
  /// Function to send commands
  final Future<ResponseMessage> Function(CommandMessage) _sendFunction;

  /// Command queue
  final Queue<QueuedCommand> _queue = Queue<QueuedCommand>();

  /// Current queue status
  QueueStatus _status = QueueStatus.idle;

  /// Event stream controller
  final StreamController<QueueEvent> _eventController =
      StreamController<QueueEvent>.broadcast();

  /// Currently executing command
  QueuedCommand? _currentCommand;

  /// Command counter for IDs
  int _commandCounter = 0;

  /// Whether to automatically retry failed commands
  bool autoRetry = true;

  /// Default maximum retries
  int defaultMaxRetries = 3;

  /// Default command timeout
  Duration defaultTimeout = const Duration(milliseconds: 100);

  /// Create command queue
  CommandQueue({
    required Future<ResponseMessage> Function(CommandMessage) sendFunction,
  }) : _sendFunction = sendFunction;

  /// Get current queue status
  QueueStatus get status => _status;

  /// Get queue length
  int get length => _queue.length;

  /// Get whether queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Get whether queue is processing
  bool get isProcessing => _status == QueueStatus.processing;

  /// Get current command
  QueuedCommand? get currentCommand => _currentCommand;

  /// Stream of queue events
  Stream<QueueEvent> get eventStream => _eventController.stream;

  /// Enqueue a command
  ///
  /// Returns a Future that completes when the command is executed.
  Future<ResponseMessage> enqueue(
    CommandMessage command, {
    int? maxRetries,
    Duration? timeout,
  }) {
    if (_status == QueueStatus.disposed) {
      throw StateError('Command queue is disposed');
    }

    final queuedCommand = QueuedCommand(
      id: 'cmd_${_commandCounter++}',
      command: command,
      maxRetries: maxRetries ?? defaultMaxRetries,
      timeout: timeout ?? defaultTimeout,
    );

    _queue.add(queuedCommand);

    _emitEvent(QueueEvent(
      type: QueueEventType.commandAdded,
      command: queuedCommand,
      message: 'Command added to queue (position: ${_queue.length})',
    ));

    // Start processing if idle
    if (_status == QueueStatus.idle) {
      _processQueue();
    }

    return queuedCommand.completer.future;
  }

  /// Process queue
  Future<void> _processQueue() async {
    if (_status == QueueStatus.processing || _status == QueueStatus.disposed) {
      return;
    }

    _status = QueueStatus.processing;
    _emitEvent(QueueEvent(
      type: QueueEventType.queueStarted,
      message: 'Queue processing started',
    ));

    while (_queue.isNotEmpty && _status == QueueStatus.processing) {
      final command = _queue.removeFirst();
      await _executeCommand(command);
    }

    if (_status == QueueStatus.processing) {
      _status = QueueStatus.idle;
    }
  }

  /// Execute a single command
  Future<void> _executeCommand(QueuedCommand queuedCommand) async {
    _currentCommand = queuedCommand;
    queuedCommand.startedAt = DateTime.now();

    _emitEvent(QueueEvent(
      type: QueueEventType.commandStarted,
      command: queuedCommand,
      message: 'Executing command (attempt ${queuedCommand.currentAttempt + 1}/${queuedCommand.maxRetries})',
    ));

    try {
      // Execute with timeout
      final response = await _sendFunction(queuedCommand.command)
          .timeout(queuedCommand.timeout);

      queuedCommand.completedAt = DateTime.now();
      queuedCommand.completer.complete(response);

      _emitEvent(QueueEvent(
        type: QueueEventType.commandCompleted,
        command: queuedCommand,
        message: 'Command completed successfully in ${queuedCommand.executionTime?.inMilliseconds}ms',
      ));
    } catch (error, stackTrace) {
      queuedCommand.lastError = error;
      queuedCommand.currentAttempt++;

      // Check if we should retry
      if (autoRetry && queuedCommand.hasRetriesLeft) {
        _emitEvent(QueueEvent(
          type: QueueEventType.commandRetrying,
          command: queuedCommand,
          message: 'Command failed, retrying (${queuedCommand.currentAttempt}/${queuedCommand.maxRetries})',
        ));

        // Re-queue for retry
        _queue.addFirst(queuedCommand);
      } else {
        // No more retries, fail the command
        queuedCommand.completedAt = DateTime.now();
        queuedCommand.completer.completeError(error, stackTrace);

        _emitEvent(QueueEvent(
          type: QueueEventType.commandFailed,
          command: queuedCommand,
          message: 'Command failed after ${queuedCommand.currentAttempt} attempts: $error',
        ));
      }
    } finally {
      _currentCommand = null;
    }
  }

  /// Pause queue processing
  void pause() {
    if (_status == QueueStatus.processing) {
      _status = QueueStatus.paused;
      _emitEvent(QueueEvent(
        type: QueueEventType.queuePaused,
        message: 'Queue processing paused',
      ));
    }
  }

  /// Resume queue processing
  void resume() {
    if (_status == QueueStatus.paused) {
      _status = QueueStatus.idle;
      _emitEvent(QueueEvent(
        type: QueueEventType.queueResumed,
        message: 'Queue processing resumed',
      ));
      _processQueue();
    }
  }

  /// Clear all pending commands
  void clear() {
    final count = _queue.length;

    // Fail all pending commands
    while (_queue.isNotEmpty) {
      final command = _queue.removeFirst();
      command.completer.completeError(
        CommandQueueException('Command cancelled - queue cleared'),
      );
    }

    _emitEvent(QueueEvent(
      type: QueueEventType.queueCleared,
      message: 'Queue cleared ($count commands cancelled)',
    ));
  }

  /// Get pending commands
  List<QueuedCommand> getPendingCommands() {
    return _queue.toList();
  }

  /// Emit queue event
  void _emitEvent(QueueEvent event) {
    _eventController.add(event);
  }

  /// Dispose queue
  void dispose() {
    _status = QueueStatus.disposed;
    clear();
    _eventController.close();
  }
}

/// Command queue exception
class CommandQueueException extends GS805Exception {
  /// Create exception
  CommandQueueException(super.message);
}
