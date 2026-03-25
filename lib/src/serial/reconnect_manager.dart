/// Reconnection Manager
///
/// Handles automatic reconnection when connection is lost.

import 'dart:async';

import 'serial_connection.dart';
import '../exceptions/gs805_exception.dart';

/// Reconnection strategy
enum ReconnectStrategy {
  /// Don't reconnect automatically
  never,

  /// Reconnect immediately on disconnect
  immediate,

  /// Reconnect with exponential backoff
  exponentialBackoff,

  /// Reconnect with fixed interval
  fixedInterval,
}

/// Reconnection configuration
class ReconnectConfig {
  /// Reconnection strategy
  final ReconnectStrategy strategy;

  /// Maximum number of reconnection attempts (0 = infinite)
  final int maxAttempts;

  /// Initial delay before first reconnection attempt
  final Duration initialDelay;

  /// Maximum delay between reconnection attempts
  final Duration maxDelay;

  /// Delay multiplier for exponential backoff
  final double backoffMultiplier;

  /// Whether to reconnect on connection errors
  final bool reconnectOnError;

  /// Create reconnection configuration
  const ReconnectConfig({
    this.strategy = ReconnectStrategy.exponentialBackoff,
    this.maxAttempts = 5,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.reconnectOnError = true,
  });

  /// No reconnection
  static const ReconnectConfig never = ReconnectConfig(
    strategy: ReconnectStrategy.never,
    maxAttempts: 0,
  );

  /// Reconnect immediately
  static const ReconnectConfig immediate = ReconnectConfig(
    strategy: ReconnectStrategy.immediate,
    maxAttempts: 5,
    initialDelay: Duration.zero,
  );

  /// Reconnect with exponential backoff (default)
  static const ReconnectConfig exponentialBackoff = ReconnectConfig(
    strategy: ReconnectStrategy.exponentialBackoff,
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
  );

  /// Reconnect with fixed interval
  static const ReconnectConfig fixedInterval = ReconnectConfig(
    strategy: ReconnectStrategy.fixedInterval,
    maxAttempts: 10,
    initialDelay: Duration(seconds: 2),
  );
}

/// Reconnection state
enum ReconnectState {
  /// Not reconnecting
  idle,

  /// Waiting before next reconnection attempt
  waiting,

  /// Currently attempting to reconnect
  connecting,

  /// Reconnection succeeded
  connected,

  /// Reconnection failed (max attempts reached)
  failed,
}

/// Reconnection event
class ReconnectEvent {
  /// Current reconnection state
  final ReconnectState state;

  /// Current attempt number (0-based)
  final int attempt;

  /// Total number of attempts allowed (0 = infinite)
  final int maxAttempts;

  /// Delay until next attempt (null if not waiting)
  final Duration? nextAttemptDelay;

  /// Error that caused the reconnection (if any)
  final Object? error;

  /// Create reconnection event
  const ReconnectEvent({
    required this.state,
    required this.attempt,
    required this.maxAttempts,
    this.nextAttemptDelay,
    this.error,
  });

  @override
  String toString() {
    final parts = ['ReconnectEvent(state: $state, attempt: $attempt'];
    if (maxAttempts > 0) {
      parts.add('/$maxAttempts');
    }
    if (nextAttemptDelay != null) {
      parts.add(', nextAttempt: ${nextAttemptDelay!.inMilliseconds}ms');
    }
    if (error != null) {
      parts.add(', error: $error');
    }
    return '${parts.join('')})';
  }
}

/// Reconnection manager
class ReconnectManager {
  final SerialConnection _connection;
  final ReconnectConfig _config;

  SerialDevice? _lastDevice;
  SerialConfig? _lastConfig;
  Timer? _reconnectTimer;
  int _attemptCount = 0;
  ReconnectState _state = ReconnectState.idle;

  final StreamController<ReconnectEvent> _eventController =
      StreamController<ReconnectEvent>.broadcast();

  /// Create reconnection manager
  ReconnectManager(
    this._connection, {
    ReconnectConfig config = ReconnectConfig.exponentialBackoff,
  }) : _config = config;

  /// Start monitoring connection and reconnecting when needed
  void startMonitoring() {
    _connection.connectionStateStream.listen((isConnected) {
      if (!isConnected && _lastDevice != null) {
        // Connection lost, start reconnection
        _startReconnection();
      } else if (isConnected) {
        // Connection restored
        _stopReconnection();
      }
    });
  }

  /// Manually trigger reconnection
  Future<void> reconnect() async {
    if (_lastDevice == null) {
      throw GS805Exception('No previous device to reconnect to');
    }

    _stopReconnection();
    _attemptCount = 0;
    await _attemptReconnection();
  }

  /// Start reconnection process
  void _startReconnection() {
    if (_config.strategy == ReconnectStrategy.never) {
      return;
    }

    if (_state == ReconnectState.waiting ||
        _state == ReconnectState.connecting) {
      // Already reconnecting
      return;
    }

    _attemptCount = 0;
    _scheduleReconnection(Duration.zero);
  }

  /// Stop reconnection process
  void _stopReconnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attemptCount = 0;
    _state = ReconnectState.idle;
  }

  /// Schedule next reconnection attempt
  void _scheduleReconnection(Duration delay) {
    if (_config.maxAttempts > 0 && _attemptCount >= _config.maxAttempts) {
      // Max attempts reached
      _state = ReconnectState.failed;
      _eventController.add(ReconnectEvent(
        state: ReconnectState.failed,
        attempt: _attemptCount,
        maxAttempts: _config.maxAttempts,
      ));
      return;
    }

    _state = ReconnectState.waiting;
    _eventController.add(ReconnectEvent(
      state: ReconnectState.waiting,
      attempt: _attemptCount,
      maxAttempts: _config.maxAttempts,
      nextAttemptDelay: delay,
    ));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => _attemptReconnection());
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnection() async {
    if (_lastDevice == null) {
      return;
    }

    _state = ReconnectState.connecting;
    _eventController.add(ReconnectEvent(
      state: ReconnectState.connecting,
      attempt: _attemptCount,
      maxAttempts: _config.maxAttempts,
    ));

    try {
      await _connection.connect(_lastDevice!, _lastConfig);

      // Success
      _state = ReconnectState.connected;
      _eventController.add(ReconnectEvent(
        state: ReconnectState.connected,
        attempt: _attemptCount,
        maxAttempts: _config.maxAttempts,
      ));
      _stopReconnection();
    } catch (e) {
      // Failed, schedule next attempt
      _attemptCount++;

      final nextDelay = _calculateNextDelay();
      _scheduleReconnection(nextDelay);
    }
  }

  /// Calculate delay for next reconnection attempt
  Duration _calculateNextDelay() {
    switch (_config.strategy) {
      case ReconnectStrategy.never:
        return Duration.zero;

      case ReconnectStrategy.immediate:
        return Duration.zero;

      case ReconnectStrategy.fixedInterval:
        return _config.initialDelay;

      case ReconnectStrategy.exponentialBackoff:
        final delay = _config.initialDelay.inMilliseconds *
            (1 << _attemptCount.clamp(0, 10)); // Cap at 2^10 to prevent overflow
        return Duration(
          milliseconds: delay.clamp(
            _config.initialDelay.inMilliseconds,
            _config.maxDelay.inMilliseconds,
          ),
        );
    }
  }

  /// Save connection details for reconnection
  void saveConnection(SerialDevice device, SerialConfig? config) {
    _lastDevice = device;
    _lastConfig = config;
  }

  /// Clear saved connection details
  void clearConnection() {
    _lastDevice = null;
    _lastConfig = null;
    _stopReconnection();
  }

  /// Stream of reconnection events
  Stream<ReconnectEvent> get eventStream => _eventController.stream;

  /// Current reconnection state
  ReconnectState get state => _state;

  /// Current attempt count
  int get attemptCount => _attemptCount;

  /// Whether currently reconnecting
  bool get isReconnecting =>
      _state == ReconnectState.waiting || _state == ReconnectState.connecting;

  /// Dispose resources
  Future<void> dispose() async {
    _stopReconnection();
    await _eventController.close();
  }
}
