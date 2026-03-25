/// Serial Manager
///
/// High-level serial communication manager that combines connection management
/// with message parsing.

import 'dart:async';
import 'dart:typed_data';

import 'serial_connection.dart';
import 'message_parser.dart';
import 'reconnect_manager.dart';
import '../protocol/gs805_message.dart';
import '../protocol/gs805_protocol.dart';
import '../exceptions/gs805_exception.dart';

/// Serial communication manager with message parsing
class SerialManager {
  final SerialConnection _connection;
  MessageParser? _parser;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<bool>? _connectionStateSubscription;
  ReconnectManager? _reconnectManager;

  final StreamController<ResponseMessage> _messageController =
      StreamController<ResponseMessage>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<ReconnectEvent> _reconnectEventController =
      StreamController<ReconnectEvent>.broadcast();

  /// Create a serial manager
  ///
  /// [connection] - Serial connection implementation
  /// [reconnectConfig] - Optional reconnection configuration
  SerialManager(
    this._connection, {
    ReconnectConfig? reconnectConfig,
  }) {
    if (reconnectConfig != null &&
        reconnectConfig.strategy != ReconnectStrategy.never) {
      _reconnectManager = ReconnectManager(_connection, config: reconnectConfig);
      _reconnectManager!.startMonitoring();

      // Forward reconnection events
      _reconnectManager!.eventStream.listen((event) {
        _reconnectEventController.add(event);

        // Reconnect message parser when connection is restored
        if (event.state == ReconnectState.connected) {
          _setupMessageParser();
        }
      });
    }
  }

  /// Get list of available devices
  Future<List<SerialDevice>> listDevices() => _connection.listDevices();

  /// Connect to a device
  Future<void> connect(SerialDevice device, [SerialConfig? config]) async {
    if (isConnected) {
      throw ConnectionException('Already connected to a device');
    }

    await _connection.connect(device, config);

    // Save connection details for reconnection
    _reconnectManager?.saveConnection(device, config);

    // Set up message parser
    _setupMessageParser();

    // Monitor connection state
    _connectionStateSubscription =
        _connection.connectionStateStream.listen((isConnected) {
      _connectionStateController.add(isConnected);
      if (!isConnected) {
        _cleanup();
      }
    });

    _connectionStateController.add(true);
  }

  /// Set up message parser
  void _setupMessageParser() {
    _parser = MessageParser();
    _inputSubscription = _connection.inputStream.listen(
      (bytes) {
        _parser?.addBytes(bytes);
      },
      onError: (error) {
        _messageController.addError(error);
      },
    );

    // Forward parsed messages
    _parser!.messageStream.listen(
      (message) => _messageController.add(message),
      onError: (error) => _messageController.addError(error),
    );
  }

  /// Disconnect from device
  ///
  /// [clearReconnection] - If true, clear reconnection settings
  Future<void> disconnect({bool clearReconnection = true}) async {
    await _cleanup();
    await _connection.disconnect();

    if (clearReconnection) {
      _reconnectManager?.clearConnection();
    }

    _connectionStateController.add(false);
  }

  /// Clean up resources
  Future<void> _cleanup() async {
    await _inputSubscription?.cancel();
    _inputSubscription = null;

    await _parser?.close();
    _parser = null;

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
  }

  /// Send a command and wait for response
  ///
  /// [command] - Command message to send
  /// [timeout] - Response timeout duration
  /// [retries] - Number of retry attempts
  Future<ResponseMessage> sendCommand(
    CommandMessage command, {
    Duration timeout = const Duration(milliseconds: 100),
    int retries = 2,
  }) async {
    if (!isConnected) {
      throw NotConnectedException('Cannot send command: not connected');
    }

    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        // Send command
        final bytes = command.toBytes();
        await _connection.write(bytes);

        // Wait for response
        final response = await messageStream
            .firstWhere(
              (msg) => msg.command == command.command,
              orElse: () => throw TimeoutException(
                'No response received',
                timeoutMs: timeout.inMilliseconds,
                retryCount: attempt,
              ),
            )
            .timeout(timeout);

        // Check for errors in response
        if (response.isError) {
          throw MachineErrorException.fromStatus(
            response.statusCode!,
            context: 'Command 0x${command.command.toRadixString(16)}',
          );
        }

        return response;
      } on TimeoutException {
        if (attempt >= retries) {
          rethrow;
        }
        // Retry
        continue;
      }
    }

    throw TimeoutException(
      'Command failed after $retries retries',
      timeoutMs: timeout.inMilliseconds,
      retryCount: retries,
    );
  }

  /// Write raw bytes to serial port
  Future<int> write(Uint8List data) => _connection.write(data);

  /// Stream of parsed response messages
  Stream<ResponseMessage> get messageStream => _messageController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Stream of reconnection events
  Stream<ReconnectEvent> get reconnectEventStream =>
      _reconnectEventController.stream;

  /// Check if currently connected
  bool get isConnected => _connection.isConnected;

  /// Check if currently reconnecting
  bool get isReconnecting => _reconnectManager?.isReconnecting ?? false;

  /// Get current reconnection state
  ReconnectState get reconnectState =>
      _reconnectManager?.state ?? ReconnectState.idle;

  /// Get current reconnection attempt count
  int get reconnectAttemptCount => _reconnectManager?.attemptCount ?? 0;

  /// Manually trigger reconnection
  Future<void> reconnect() async {
    if (_reconnectManager == null) {
      throw GS805Exception('Reconnection is not enabled');
    }
    await _reconnectManager!.reconnect();
  }

  /// Get currently connected device
  SerialDevice? get connectedDevice => _connection.connectedDevice;

  /// Get current configuration
  SerialConfig? get currentConfig => _connection.currentConfig;

  /// Get current buffer size (for debugging)
  int get bufferSize => _parser?.bufferSize ?? 0;

  /// Clear message buffer
  void clearBuffer() {
    _parser?.clearBuffer();
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await _cleanup();
    await _reconnectManager?.dispose();
    await _messageController.close();
    await _connectionStateController.close();
    await _reconnectEventController.close();
    await _connection.dispose();
  }
}

/// Helper methods for creating SerialManager instances
extension SerialManagerFactory on SerialManager {
  /// Create a SerialManager with USB connection
  static SerialManager usb(SerialConnection connection) {
    return SerialManager(connection);
  }
}
