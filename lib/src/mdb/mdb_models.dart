/// MDB Cashless Card Reader Models

import 'dart:typed_data';

/// Cashless reader state machine
enum CashlessState {
  /// Not initialized
  inactive('Inactive'),

  /// Config received, reader disabled
  disabled('Disabled'),

  /// Reader enabled, waiting for card
  enabled('Enabled'),

  /// Valid card detected, waiting for vend request
  sessionIdle('Session Idle'),

  /// Vend requested, waiting for approval
  vendRequested('Vend Requested'),

  /// Vend approved, dispensing
  vending('Vending'),

  /// Error state
  error('Error');

  final String displayName;
  const CashlessState(this.displayName);
}

/// Cashless event types
enum CashlessEventType {
  /// Reader state changed
  stateChanged,

  /// Valid card detected (begin session)
  cardDetected,

  /// Vend approved by reader
  vendApproved,

  /// Vend denied by reader
  vendDenied,

  /// Session cancelled by reader
  sessionCancelled,

  /// Session completed
  sessionCompleted,

  /// Config response received
  configReceived,

  /// Reader ID received
  readerIdReceived,

  /// Error occurred
  error,

  /// Raw data received (for debugging)
  rawData,

  /// Command sent (for logging)
  commandSent,

  /// ACK received
  ackReceived,
}

/// Event from cashless reader
class CashlessEvent {
  final CashlessEventType type;
  final CashlessState state;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  CashlessEvent({
    required this.type,
    required this.state,
    Map<String, dynamic>? data,
  })  : timestamp = DateTime.now(),
        data = data ?? {};

  /// Approved amount (for vendApproved events)
  int? get approvedAmount => data['amount'] as int?;

  /// Available funds on card (for cardDetected events)
  int? get availableFunds => data['funds'] as int?;

  /// Error message (for error events)
  String? get errorMessage => data['error'] as String?;

  /// Raw hex data (for rawData events)
  String? get rawHex => data['hex'] as String?;

  @override
  String toString() {
    final parts = <String>['CashlessEvent: ${type.name} (${state.displayName})'];
    if (data.isNotEmpty) parts.add('$data');
    return parts.join(' ');
  }
}

/// Vend request info
class VendRequest {
  /// Price in smallest unit
  final int price;

  /// Item/product number
  final int itemNumber;

  /// Timestamp
  final DateTime timestamp;

  VendRequest({
    required this.price,
    required this.itemNumber,
  }) : timestamp = DateTime.now();

  /// Encode as HEX bytes for MDB command: 13 00 {PRICE_H} {PRICE_L} {ITEM_H} {ITEM_L}
  Uint8List toBytes() {
    return Uint8List.fromList([
      0x13,
      0x00,
      (price >> 8) & 0xFF,
      price & 0xFF,
      (itemNumber >> 8) & 0xFF,
      itemNumber & 0xFF,
    ]);
  }

  @override
  String toString() => 'VendRequest(price: $price, item: $itemNumber)';
}

/// Reader config info (parsed from config response)
class ReaderConfig {
  final int featureLevel;
  final int countryCode;
  final int scaleFactor;
  final int decimalPlaces;
  final int maxResponseTime;
  final List<int> rawData;

  ReaderConfig({
    required this.featureLevel,
    required this.countryCode,
    required this.scaleFactor,
    required this.decimalPlaces,
    required this.maxResponseTime,
    required this.rawData,
  });

  /// Parse from received data bytes (after device ID)
  factory ReaderConfig.fromBytes(List<int> bytes) {
    return ReaderConfig(
      featureLevel: bytes.isNotEmpty ? bytes[0] : 0,
      countryCode: bytes.length > 2
          ? (bytes[1] << 8) | bytes[2]
          : 0,
      scaleFactor: bytes.length > 3 ? bytes[3] : 1,
      decimalPlaces: bytes.length > 4 ? bytes[4] : 2,
      maxResponseTime: bytes.length > 5 ? bytes[5] : 5,
      rawData: List.from(bytes),
    );
  }

  @override
  String toString() =>
      'ReaderConfig(level: $featureLevel, country: $countryCode, '
      'scale: $scaleFactor, decimals: $decimalPlaces)';
}
