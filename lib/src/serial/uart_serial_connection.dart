import 'dart:async';

import 'package:flutter/services.dart';

import 'serial_connection.dart';
import '../exceptions/gs805_exception.dart';

/// UART serial connection for embedded Android devices.
///
/// Uses platform channels to communicate with native Kotlin/JNI code
/// that opens and configures hardware UART ports via termios.
///
/// Example:
/// ```dart
/// final uart = UartSerialConnection();
/// final devices = await uart.listDevices();
/// await uart.connect(devices.first, SerialConfig.gs805);
///
/// uart.inputStream.listen((data) {
///   print('Received: $data');
/// });
///
/// await uart.write(Uint8List.fromList([0x02, 0x30, 0x03]));
/// ```
class UartSerialConnection implements SerialConnection {
  static const _methodChannel = MethodChannel('gs805serial/uart');
  static const _eventChannel = EventChannel('gs805serial/uart_input');

  SerialDevice? _device;
  SerialConfig? _config;

  final StreamController<Uint8List> _inputController =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;

  /// Create a UART serial connection.
  UartSerialConnection();

  @override
  Future<List<SerialDevice>> listDevices() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('listDevices');
      if (result == null) return [];

      return result.map((device) {
        final map = Map<String, dynamic>.from(device as Map);
        return SerialDevice(
          id: map['id'] as String,
          name: map['name'] as String,
          metadata: {
            'path': map['path'],
            'readable': map['readable'],
            'writable': map['writable'],
            'type': 'uart',
          },
        );
      }).toList();
    } on PlatformException catch (e) {
      throw SerialPortException(
        'Failed to list UART devices: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  Future<void> connect(SerialDevice device, [SerialConfig? config]) async {
    if (isConnected) {
      throw ConnectionException('Already connected to a device');
    }

    _config = config ?? SerialConfig.gs805;

    try {
      await _methodChannel.invokeMethod<bool>('connect', {
        'path': device.id,
        'baudRate': _config!.baudRate,
        'dataBits': _config!.dataBits,
        'stopBits': _config!.stopBits,
        'parity': _config!.parity,
      });

      _device = device;

      // Listen to the EventChannel for incoming serial data
      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen(
        (dynamic data) {
          if (data is Uint8List) {
            _inputController.add(data);
          } else if (data is List) {
            _inputController.add(Uint8List.fromList(data.cast<int>()));
          }
        },
        onError: (dynamic error) {
          _inputController.addError(
            SerialPortException(
              'Error reading from UART port',
              portName: device.id,
              cause: error,
            ),
          );
        },
        onDone: () {
          // EventChannel stream closed - port may have been disconnected
          if (_device != null) {
            _handleUnexpectedDisconnect();
          }
        },
      );

      _connectionStateController.add(true);
    } on PlatformException catch (e) {
      _device = null;
      _config = null;
      throw ConnectionException(
        'Failed to connect to ${device.name}: ${e.message}',
        portName: device.id,
        cause: e,
      );
    } catch (e) {
      _device = null;
      _config = null;
      if (e is GS805Exception) rethrow;
      throw ConnectionException(
        'Failed to connect to ${device.name}',
        portName: device.id,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) return;

    final device = _device;

    try {
      await _eventSubscription?.cancel();
      _eventSubscription = null;

      await _methodChannel.invokeMethod<bool>('disconnect');

      _device = null;
      _config = null;

      _connectionStateController.add(false);
    } on PlatformException catch (e) {
      throw SerialPortException(
        'Error disconnecting from device',
        portName: device?.id,
        cause: e,
      );
    }
  }

  @override
  bool get isConnected => _device != null;

  @override
  SerialDevice? get connectedDevice => _device;

  @override
  SerialConfig? get currentConfig => _config;

  @override
  Future<int> write(Uint8List data) async {
    if (!isConnected) {
      throw NotConnectedException('Cannot write: not connected to device');
    }

    try {
      final bytesWritten = await _methodChannel.invokeMethod<int>('write', {
        'data': data,
      });
      return bytesWritten ?? data.length;
    } on PlatformException catch (e) {
      throw SerialPortException(
        'Error writing to UART port',
        portName: _device?.id,
        cause: e,
      );
    }
  }

  @override
  Stream<Uint8List> get inputStream => _inputController.stream;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Future<void> dispose() async {
    await disconnect();
    await _inputController.close();
    await _connectionStateController.close();
  }

  /// Handle unexpected disconnection (e.g. device removed).
  void _handleUnexpectedDisconnect() {
    _device = null;
    _config = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _connectionStateController.add(false);
  }
}
