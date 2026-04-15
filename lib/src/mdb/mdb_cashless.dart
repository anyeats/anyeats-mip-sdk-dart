/// MDB Cashless Card Reader Manager
///
/// Manages communication with MDB cashless reader via MDB-RS232 bridge.
/// The bridge communicates over a separate serial port from the GS805 machine.
///
/// Communication rules:
/// - PC → bridge: HEX data
/// - bridge → PC: ASCII data (hex string)
/// - POLL is handled automatically by the bridge
/// - Device events are sent automatically with device ID as first byte

import 'dart:async';
import 'dart:typed_data';

import '../serial/serial_connection.dart';
import '../serial/usb_serial_connection.dart';
import 'mdb_constants.dart';
import 'mdb_models.dart';

/// High-level MDB Cashless card reader controller
class MdbCashless {
  SerialConnection? _connection;
  final SerialConnection _serialImpl;

  CashlessState _state = CashlessState.inactive;
  ReaderConfig? _readerConfig;
  VendRequest? _pendingVend;

  StreamSubscription? _inputSubscription;
  StreamSubscription? _connectionSubscription;

  final StreamController<CashlessEvent> _eventController =
      StreamController<CashlessEvent>.broadcast();

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  bool _isConnected = false;
  SerialDevice? _connectedDevice;

  /// Buffer for incoming ASCII data
  final StringBuffer _receiveBuffer = StringBuffer();

  /// Create MDB Cashless controller
  ///
  /// [connection] - Serial connection implementation (defaults to USB)
  MdbCashless({SerialConnection? connection})
      : _serialImpl = connection ?? UsbSerialConnection();

  // ========== Connection Management ==========

  /// List available serial devices
  Future<List<SerialDevice>> listDevices() async {
    return await _serialImpl.listDevices();
  }

  /// Connect to MDB-RS232 bridge device
  Future<void> connect(SerialDevice device) async {
    final config = SerialConfig(
      baudRate: MdbConfig.baudRate,
      dataBits: MdbConfig.dataBits,
      stopBits: MdbConfig.stopBits,
      parity: MdbConfig.parity,
    );

    await _serialImpl.connect(device, config);
    _connection = _serialImpl;
    _connectedDevice = device;
    _isConnected = true;

    // Listen for incoming data
    _inputSubscription = _serialImpl.inputStream.listen(
      _onDataReceived,
      onError: (error) {
        _emitEvent(CashlessEventType.error, data: {'error': error.toString()});
      },
    );

    // Monitor connection state
    _connectionSubscription = _serialImpl.connectionStateStream.listen(
      (connected) {
        _isConnected = connected;
        _connectionStateController.add(connected);
        if (!connected) {
          _state = CashlessState.inactive;
          _emitEvent(CashlessEventType.stateChanged);
        }
      },
    );

    _connectionStateController.add(true);
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Disconnect from MDB-RS232 bridge
  Future<void> disconnect() async {
    await _inputSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _inputSubscription = null;
    _connectionSubscription = null;

    await _connection?.disconnect();
    _connection = null;
    _connectedDevice = null;
    _isConnected = false;
    _state = CashlessState.inactive;
    _pendingVend = null;
    _receiveBuffer.clear();

    _connectionStateController.add(false);
  }

  /// Whether connected to MDB-RS232 bridge
  bool get isConnected => _isConnected;

  /// Connected device
  SerialDevice? get connectedDevice => _connectedDevice;

  /// Current cashless state
  CashlessState get state => _state;

  /// Reader config (after setup)
  ReaderConfig? get readerConfig => _readerConfig;

  /// Pending vend request
  VendRequest? get pendingVend => _pendingVend;

  // ========== Event Streams ==========

  /// Stream of cashless events
  Stream<CashlessEvent> get eventStream => _eventController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream =>
      _connectionStateController.stream;

  // ========== Cashless Commands ==========

  /// Initialize card reader (Config + Set Max/Min Price)
  ///
  /// Call this once after connecting to the bridge.
  /// [maxPrice] - Maximum accepted price (default: 0xFFFF = no limit)
  /// [minPrice] - Minimum accepted price (default: 0x0000)
  Future<void> setup({int maxPrice = 0xFFFF, int minPrice = 0x0000}) async {
    _ensureConnected();

    // Config: 110001000000
    await _sendHex([0x11, 0x00, 0x01, 0x00, 0x00, 0x00]);

    // Wait for config response
    await Future.delayed(const Duration(milliseconds: 500));

    // Set max/min price: 1101{MAX_H}{MAX_L}{MIN_H}{MIN_L}
    await _sendHex([
      0x11,
      0x01,
      (maxPrice >> 8) & 0xFF,
      maxPrice & 0xFF,
      (minPrice >> 8) & 0xFF,
      minPrice & 0xFF,
    ]);

    _state = CashlessState.disabled;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Initialize card reader using manufacturer's Level 2/3 sequence
  ///
  /// Full initialization flow from manufacturer documentation:
  /// 1. Config Level 2 + Level 3
  /// 2. Set Max/Min Price
  /// 3. Expansion Request ID (with VMC identification)
  /// 4. Expansion Enable
  /// 5. Reader Enable
  ///
  /// This is an alternative to [setup] which uses Level 1 only.
  Future<void> setupV2({int maxPrice = 0xFFFF, int minPrice = 0x0000}) async {
    _ensureConnected();

    // 1. Config Level 2: 110002000002
    await _sendHex([0x11, 0x00, 0x02, 0x00, 0x00, 0x02]);
    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Config Level 3: 110003000000
    await _sendHex([0x11, 0x00, 0x03, 0x00, 0x00, 0x00]);
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. Set max/min price: 1101{MAX_H}{MAX_L}{MIN_H}{MIN_L}
    await _sendHex([
      0x11, 0x01,
      (maxPrice >> 8) & 0xFF, maxPrice & 0xFF,
      (minPrice >> 8) & 0xFF, minPrice & 0xFF,
    ]);
    await Future.delayed(const Duration(milliseconds: 300));

    // 4. Expansion Request ID (VMC manufacturer + serial + model + sw version + feature)
    // "NEC" + "000000000000" + "   " + "SOLISTA  " + 0x00 + 0x11
    await _sendHex([
      0x17, 0x00,
      0x4E, 0x45, 0x43, // "NEC"
      0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, // "000000000000"
      0x20, 0x20, 0x20, // "   "
      0x53, 0x4F, 0x4C, 0x49, 0x53, 0x54, 0x41, 0x20, 0x20, // "SOLISTA  "
      0x00, 0x11,
    ]);
    await Future.delayed(const Duration(milliseconds: 300));

    // 5. Expansion Enable: 170400000020
    await _sendHex([0x17, 0x04, 0x00, 0x00, 0x00, 0x20]);
    await Future.delayed(const Duration(milliseconds: 300));

    // 6. Reader Enable: 1401
    await _sendHex([0x14, 0x01]);

    _state = CashlessState.enabled;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Enable card reader (start accepting cards)
  Future<void> enable() async {
    _ensureConnected();
    await _sendHex([0x14, 0x01]);
    _state = CashlessState.enabled;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Disable card reader
  Future<void> disable() async {
    _ensureConnected();
    await _sendHex([0x14, 0x00]);
    _state = CashlessState.disabled;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Cancel current operation
  Future<void> cancel() async {
    _ensureConnected();
    await _sendHex([0x14, 0x02]);
  }

  /// Request vend (send price and item number to reader)
  ///
  /// Call this after receiving [CashlessEventType.cardDetected] event.
  /// [price] - Price in smallest currency unit
  /// [itemNumber] - Product/item number (default: 1)
  Future<void> requestVend({required int price, int itemNumber = 1}) async {
    _ensureConnected();

    // 상태 체크 제거: 일부 카드리더는 Enable 상태에서 바로 Request Vend 가능

    _pendingVend = VendRequest(price: price, itemNumber: itemNumber);

    // 13 00 {PRICE_H} {PRICE_L} {ITEM_H} {ITEM_L}
    await _sendHex([
      0x13,
      0x00,
      (price >> 8) & 0xFF,
      price & 0xFF,
      (itemNumber >> 8) & 0xFF,
      itemNumber & 0xFF,
    ]);

    _state = CashlessState.vendRequested;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Confirm vend success (product dispensed successfully)
  ///
  /// Call this after product is dispensed.
  /// [itemNumber] - Item number that was dispensed
  Future<void> vendSuccess({int itemNumber = 1}) async {
    _ensureConnected();

    // 13 02 {ITEM_H} {ITEM_L}
    await _sendHex([
      0x13,
      0x02,
      (itemNumber >> 8) & 0xFF,
      itemNumber & 0xFF,
    ]);

    _state = CashlessState.enabled;
    _pendingVend = null;
  }

  /// Cancel vend (product not dispensed)
  Future<void> vendCancel() async {
    _ensureConnected();
    await _sendHex([0x13, 0x01]);

    _state = CashlessState.enabled;
    _pendingVend = null;
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Report cash sale to reader
  ///
  /// [price] - Sale amount
  /// [itemNumber] - Item sold
  Future<void> cashSale({required int price, int itemNumber = 1}) async {
    _ensureConnected();
    // 13 05 {PRICE_H} {PRICE_L} {ITEM_H} {ITEM_L}
    await _sendHex([
      0x13,
      0x05,
      (price >> 8) & 0xFF,
      price & 0xFF,
      (itemNumber >> 8) & 0xFF,
      itemNumber & 0xFF,
    ]);
  }

  /// End session (complete the transaction cycle)
  Future<void> sessionComplete() async {
    _ensureConnected();
    await _sendHex([0x13, 0x04]);
    _state = CashlessState.enabled;
    _emitEvent(CashlessEventType.sessionCompleted);
    _emitEvent(CashlessEventType.stateChanged);
  }

  /// Request reader ID
  Future<void> requestId() async {
    _ensureConnected();
    await _sendHex([0x17, 0x00]);
  }

  // ========== Internal Methods ==========

  void _ensureConnected() {
    if (!_isConnected || _connection == null) {
      throw StateError('Not connected to MDB-RS232 bridge');
    }
  }

  /// Send raw HEX data to MDB-RS232 bridge (public)
  Future<void> sendRawHex(List<int> bytes) async {
    _ensureConnected();
    await _sendHex(bytes);
  }

  /// Send HEX data to MDB-RS232 bridge
  Future<void> _sendHex(List<int> bytes) async {
    final data = Uint8List.fromList(bytes);
    await _connection!.write(data);

    _emitEvent(CashlessEventType.commandSent, data: {
      'hex': _bytesToHex(data),
    });
  }

  /// Handle incoming data from MDB-RS232 bridge
  ///
  /// Bridge sends ASCII hex strings. Data from cashless reader
  /// has device ID as first byte (auto-added by bridge for activity data).
  /// Response to PC commands does NOT have device ID prefix.
  void _onDataReceived(Uint8List rawData) {
    // Bridge sends ASCII data - convert to string
    final asciiStr = String.fromCharCodes(rawData).trim();
    if (asciiStr.isEmpty) return;

    // Add to buffer for potential multi-packet data
    _receiveBuffer.write(asciiStr);
    final buffered = _receiveBuffer.toString();

    // Try to parse complete hex pairs
    final cleaned = buffered.replaceAll(' ', '').replaceAll('\r', '').replaceAll('\n', '');
    if (cleaned.length < 2) return;

    // Process pairs of hex characters
    final bytes = <int>[];
    for (int i = 0; i < cleaned.length - 1; i += 2) {
      final hexPair = cleaned.substring(i, i + 2);
      final value = int.tryParse(hexPair, radix: 16);
      if (value == null) {
        // Invalid hex, clear buffer and skip
        _receiveBuffer.clear();
        return;
      }
      bytes.add(value);
    }

    _receiveBuffer.clear();

    // Emit raw data event for debugging
    _emitEvent(CashlessEventType.rawData, data: {
      'hex': _bytesToHex(Uint8List.fromList(bytes)),
      'bytes': bytes,
    });

    _parseResponse(bytes);
  }

  /// Parse response bytes from the bridge
  void _parseResponse(List<int> bytes) {
    if (bytes.isEmpty) return;

    final firstByte = bytes[0];

    // Check if this is auto-reported activity data (has device ID prefix)
    if (MdbDeviceId.isCashless(firstByte) && bytes.length > 1) {
      // Cashless device activity - parse without device ID
      _parseCashlessData(bytes.sublist(1));
      return;
    }

    // Direct response (no device ID prefix) - response to our command
    _parseCashlessData(bytes);
  }

  /// Parse cashless-specific data
  void _parseCashlessData(List<int> bytes) {
    if (bytes.isEmpty) return;

    final responseCode = bytes[0];

    switch (responseCode) {
      case CashlessResponse.ack:
        _emitEvent(CashlessEventType.ackReceived);
        break;

      case CashlessResponse.configData:
        // Config response: 01 XX XX XX ...
        _readerConfig = ReaderConfig.fromBytes(bytes.sublist(1));
        _emitEvent(CashlessEventType.configReceived, data: {
          'config': _readerConfig.toString(),
        });
        break;

      case CashlessResponse.beginSession:
        // Begin session: 03 {FUNDS_H} {FUNDS_L}
        int? funds;
        if (bytes.length >= 3) {
          funds = (bytes[1] << 8) | bytes[2];
        }
        _state = CashlessState.sessionIdle;
        _emitEvent(CashlessEventType.cardDetected, data: {
          if (funds != null) 'funds': funds,
        });
        _emitEvent(CashlessEventType.stateChanged);
        break;

      case CashlessResponse.vendApproved:
        // Vend approved: 05 {AMOUNT_H} {AMOUNT_L}
        int? amount;
        if (bytes.length >= 3) {
          amount = (bytes[1] << 8) | bytes[2];
        }
        _state = CashlessState.vending;
        _emitEvent(CashlessEventType.vendApproved, data: {
          if (amount != null) 'amount': amount,
        });
        _emitEvent(CashlessEventType.stateChanged);
        break;

      case CashlessResponse.vendDenied:
        _state = CashlessState.sessionIdle;
        _pendingVend = null;
        _emitEvent(CashlessEventType.vendDenied);
        _emitEvent(CashlessEventType.stateChanged);
        break;

      case CashlessResponse.endSession:
      case CashlessResponse.sessionCancelRequest:
        _state = CashlessState.enabled;
        _pendingVend = null;
        _emitEvent(CashlessEventType.sessionCancelled);
        _emitEvent(CashlessEventType.stateChanged);
        break;

      case CashlessResponse.peripheralId:
        _emitEvent(CashlessEventType.readerIdReceived, data: {
          'id': _bytesToHex(Uint8List.fromList(bytes.sublist(1))),
        });
        break;

      default:
        // Unknown response, log as raw data
        break;
    }
  }

  void _emitEvent(CashlessEventType type, {Map<String, dynamic>? data}) {
    if (!_eventController.isClosed) {
      _eventController.add(CashlessEvent(
        type: type,
        state: _state,
        data: data,
      ));
    }
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
    await _connectionStateController.close();
  }
}
