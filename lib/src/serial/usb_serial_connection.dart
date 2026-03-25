/// USB Serial Connection Implementation
///
/// This file implements SerialConnection using the usb_serial package.

import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

import 'serial_connection.dart';
import '../exceptions/gs805_exception.dart';

/// USB Serial connection implementation
class UsbSerialConnection implements SerialConnection {
  UsbPort? _port;
  SerialDevice? _device;
  SerialConfig? _config;
  StreamSubscription<String>? _statusSubscription;
  Transaction<String>? _transaction;

  final StreamController<Uint8List> _inputController =
      StreamController<Uint8List>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  /// Create USB serial connection
  UsbSerialConnection();

  @override
  Future<List<SerialDevice>> listDevices() async {
    try {
      final devices = await UsbSerial.listDevices();
      return devices.map((device) {
        return SerialDevice(
          id: device.deviceId.toString(),
          name: device.productName ?? 'USB Serial Device',
          vendorId: device.vid,
          productId: device.pid,
          metadata: {
            'manufacturer': device.manufacturerName,
            'serial': device.serial,
          },
        );
      }).toList();
    } catch (e) {
      throw SerialPortException(
        'Failed to list USB devices',
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
      // Find the USB device
      final devices = await UsbSerial.listDevices();
      final usbDevice = devices.firstWhere(
        (d) => d.deviceId.toString() == device.id,
        orElse: () => throw ConnectionException(
          'Device not found: ${device.name}',
          portName: device.id,
        ),
      );

      // Create port
      _port = await usbDevice.create();
      if (_port == null) {
        throw ConnectionException(
          'Failed to create USB port for ${device.name}',
          portName: device.id,
        );
      }

      // Open port
      final openResult = await _port!.open();
      if (!openResult) {
        _port = null;
        throw ConnectionException(
          'Failed to open USB port for ${device.name}',
          portName: device.id,
        );
      }

      // Configure port
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        _config!.baudRate,
        _config!.dataBits,
        _config!.stopBits,
        _config!.parity,
      );

      _device = device;

      // Set up input stream
      _transaction = Transaction.stringTerminated(
        _port!.inputStream!,
        Uint8List.fromList([]), // No terminator - we'll handle raw bytes
      );

      _transaction!.stream.listen(
        (data) {
          // Convert string back to bytes
          // Note: usb_serial returns String, we need to handle this
          final bytes = Uint8List.fromList(data.codeUnits);
          _inputController.add(bytes);
        },
        onError: (error) {
          _inputController.addError(
            SerialPortException(
              'Error reading from USB port',
              portName: device.id,
              cause: error,
            ),
          );
        },
      );

      // Monitor connection status
      // Note: onStatusChange is not available in usb_serial 0.5.2
      // Connection state changes are handled via the inputStream errors
      // _statusSubscription = _port!.onStatusChange?.listen((status) {
      //   // Handle status changes if needed
      // });

      _connectionStateController.add(true);
    } catch (e) {
      _port = null;
      _device = null;
      _config = null;
      if (e is GS805Exception) {
        rethrow;
      }
      throw ConnectionException(
        'Failed to connect to ${device.name}',
        portName: device.id,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) {
      return;
    }

    final device = _device;

    try {
      await _statusSubscription?.cancel();
      _statusSubscription = null;

      _transaction?.dispose();
      _transaction = null;

      await _port?.close();
      _port = null;

      _device = null;
      _config = null;

      _connectionStateController.add(false);
    } catch (e) {
      throw SerialPortException(
        'Error disconnecting from device',
        portName: device?.id,
        cause: e,
      );
    }
  }

  @override
  bool get isConnected => _port != null && _device != null;

  @override
  SerialDevice? get connectedDevice => _device;

  @override
  SerialConfig? get currentConfig => _config;

  @override
  Future<int> write(Uint8List data) async {
    if (!isConnected || _port == null) {
      throw NotConnectedException('Cannot write: not connected to device');
    }

    try {
      await _port!.write(data);
      return data.length;
    } catch (e) {
      throw SerialPortException(
        'Error writing to USB port',
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
}

/// Helper extension for better raw byte handling
extension UsbSerialConnectionExt on UsbSerialConnection {
  /// Create connection with automatic device selection
  ///
  /// Connects to the first available USB serial device
  static Future<UsbSerialConnection> connectToFirstDevice([
    SerialConfig? config,
  ]) async {
    final connection = UsbSerialConnection();
    final devices = await connection.listDevices();

    if (devices.isEmpty) {
      throw ConnectionException('No USB serial devices found');
    }

    await connection.connect(devices.first, config);
    return connection;
  }

  /// Create connection with device filter
  ///
  /// Connects to first device matching the filter predicate
  static Future<UsbSerialConnection> connectWithFilter(
    bool Function(SerialDevice) filter, [
    SerialConfig? config,
  ]) async {
    final connection = UsbSerialConnection();
    final devices = await connection.listDevices();

    final device = devices.where(filter).firstOrNull;
    if (device == null) {
      throw ConnectionException('No matching USB serial device found');
    }

    await connection.connect(device, config);
    return connection;
  }

  /// Create connection by vendor/product ID
  static Future<UsbSerialConnection> connectByVidPid(
    int vendorId,
    int productId, [
    SerialConfig? config,
  ]) async {
    return connectWithFilter(
      (device) =>
          device.vendorId == vendorId && device.productId == productId,
      config,
    );
  }
}

extension _ListFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
