/// Serial Connection Interface
///
/// This file defines the abstract interface for serial communication.
/// Different implementations (USB, Bluetooth, TCP) can implement this interface.

import 'dart:async';
import 'dart:typed_data';

/// Serial device information
class SerialDevice {
  /// Device identifier (port name, address, etc.)
  final String id;

  /// Device name or description
  final String name;

  /// Vendor ID (for USB devices)
  final int? vendorId;

  /// Product ID (for USB devices)
  final int? productId;

  /// Additional device information
  final Map<String, dynamic>? metadata;

  /// Create serial device info
  SerialDevice({
    required this.id,
    required this.name,
    this.vendorId,
    this.productId,
    this.metadata,
  });

  @override
  String toString() {
    final parts = <String>[name];
    if (vendorId != null && productId != null) {
      parts.add('VID:${vendorId!.toRadixString(16).padLeft(4, '0')}');
      parts.add('PID:${productId!.toRadixString(16).padLeft(4, '0')}');
    }
    return parts.join(' - ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Serial connection configuration
class SerialConfig {
  /// Baud rate (bits per second)
  final int baudRate;

  /// Number of data bits (5-8)
  final int dataBits;

  /// Number of stop bits (1 or 2)
  final int stopBits;

  /// Parity (0=none, 1=odd, 2=even)
  final int parity;

  /// Create serial configuration
  const SerialConfig({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0, // none
  });

  /// Default GS805 configuration (9600, 8N1)
  static const SerialConfig gs805 = SerialConfig(
    baudRate: 9600,
    dataBits: 8,
    stopBits: 1,
    parity: 0,
  );

  @override
  String toString() =>
      '${baudRate}bps, ${dataBits}${_parityChar}${stopBits}';

  String get _parityChar {
    switch (parity) {
      case 0:
        return 'N';
      case 1:
        return 'O';
      case 2:
        return 'E';
      default:
        return '?';
    }
  }
}

/// Abstract serial connection interface
///
/// Implementations must handle:
/// - Device discovery
/// - Connection management
/// - Data transmission
/// - Data reception (as stream)
abstract class SerialConnection {
  /// Get list of available serial devices
  Future<List<SerialDevice>> listDevices();

  /// Connect to a specific device
  ///
  /// [device] - Device to connect to
  /// [config] - Serial port configuration (default: GS805 config)
  Future<void> connect(SerialDevice device, [SerialConfig? config]);

  /// Disconnect from current device
  Future<void> disconnect();

  /// Check if currently connected
  bool get isConnected;

  /// Get currently connected device (null if not connected)
  SerialDevice? get connectedDevice;

  /// Get current configuration (null if not connected)
  SerialConfig? get currentConfig;

  /// Write data to serial port
  ///
  /// Returns number of bytes written
  Future<int> write(Uint8List data);

  /// Stream of received data
  ///
  /// Each element is a chunk of received bytes
  Stream<Uint8List> get inputStream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream;

  /// Close all resources
  Future<void> dispose();
}

/// Serial connection events
abstract class SerialConnectionEvent {}

/// Device connected event
class DeviceConnectedEvent extends SerialConnectionEvent {
  final SerialDevice device;
  DeviceConnectedEvent(this.device);
}

/// Device disconnected event
class DeviceDisconnectedEvent extends SerialConnectionEvent {
  final SerialDevice? device;
  final String? reason;
  DeviceDisconnectedEvent({this.device, this.reason});
}

/// Data received event (internal use)
class DataReceivedEvent extends SerialConnectionEvent {
  final Uint8List data;
  DataReceivedEvent(this.data);
}

/// Error event
class SerialErrorEvent extends SerialConnectionEvent {
  final String message;
  final Object? error;
  SerialErrorEvent(this.message, {this.error});
}
