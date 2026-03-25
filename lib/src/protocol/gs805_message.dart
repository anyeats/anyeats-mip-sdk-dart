/// GS805 Protocol Message Classes
///
/// This file contains message data structures for command and response messages.

import 'dart:typed_data';
import 'gs805_constants.dart';

/// Base class for all GS805 protocol messages
abstract class GS805Message {
  /// Message length (LEN field)
  int get length;

  /// Message data payload
  Uint8List get data;

  /// Convert message to byte array for transmission
  Uint8List toBytes();
}

/// Command message sent from host to GS805 machine
///
/// Format: FLAG1(2) + LEN(1) + COMND(1) + DATA(variable) + SUM(1)
class CommandMessage implements GS805Message {
  /// Command code (COMND field)
  final int command;

  /// Command data payload (DATA field)
  final Uint8List _data;

  /// Create a command message
  ///
  /// [command] - Command code (see [CommandCodes])
  /// [data] - Optional data payload (empty if not provided)
  CommandMessage({
    required this.command,
    Uint8List? data,
  }) : _data = data ?? Uint8List(0) {
    // Validate command code
    if (command < 0x01 || command > 0xFF) {
      throw ArgumentError('Invalid command code: 0x${command.toRadixString(16)}');
    }

    // Validate message length
    final totalLength = 2 + _data.length; // COMND + DATA + SUM
    if (totalLength < ProtocolFlags.minMessageLength ||
        totalLength > ProtocolFlags.maxMessageLength) {
      throw ArgumentError(
        'Message length out of range: $totalLength (must be ${ProtocolFlags.minMessageLength}-${ProtocolFlags.maxMessageLength})',
      );
    }
  }

  /// Create a command message with a single byte parameter
  factory CommandMessage.withByte(int command, int value) {
    return CommandMessage(
      command: command,
      data: Uint8List.fromList([value]),
    );
  }

  /// Create a command message with multiple byte parameters
  factory CommandMessage.withBytes(int command, List<int> values) {
    return CommandMessage(
      command: command,
      data: Uint8List.fromList(values),
    );
  }

  /// Create a command message with a 16-bit word (Big Endian)
  factory CommandMessage.withWord(int command, int value) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError('Word value out of range: $value');
    }
    return CommandMessage(
      command: command,
      data: Uint8List.fromList([
        (value >> 8) & 0xFF, // High byte
        value & 0xFF, // Low byte
      ]),
    );
  }

  /// Create a command message with a 32-bit double word (Big Endian)
  factory CommandMessage.withDWord(int command, int value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError('DWord value out of range: $value');
    }
    return CommandMessage(
      command: command,
      data: Uint8List.fromList([
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]),
    );
  }

  @override
  int get length => 2 + _data.length; // COMND + DATA + SUM

  @override
  Uint8List get data => Uint8List.fromList(_data);

  @override
  Uint8List toBytes() {
    // Calculate total message size
    final messageSize = 2 + 1 + 1 + _data.length + 1; // FLAG1 + LEN + COMND + DATA + SUM
    final buffer = Uint8List(messageSize);
    int offset = 0;

    // FLAG1 (2 bytes, Big Endian)
    buffer[offset++] = (ProtocolFlags.commandHeader >> 8) & 0xFF;
    buffer[offset++] = ProtocolFlags.commandHeader & 0xFF;

    // LEN (1 byte)
    buffer[offset++] = length;

    // COMND (1 byte)
    buffer[offset++] = command;

    // DATA (variable length)
    for (int i = 0; i < _data.length; i++) {
      buffer[offset++] = _data[i];
    }

    // SUM (1 byte) - checksum calculation
    int checksum = 0;
    // Sum FLAG1
    checksum += (ProtocolFlags.commandHeader >> 8) & 0xFF;
    checksum += ProtocolFlags.commandHeader & 0xFF;
    // Sum LEN
    checksum += length;
    // Sum COMND
    checksum += command;
    // Sum DATA
    for (int i = 0; i < _data.length; i++) {
      checksum += _data[i];
    }
    // Take lower 8 bits
    buffer[offset] = checksum & 0xFF;

    return buffer;
  }

  @override
  String toString() {
    final dataHex = _data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return 'CommandMessage(command: 0x${command.toRadixString(16)}, data: [$dataHex])';
  }
}

/// Response message received from GS805 machine
///
/// Format: FLAG2(2) + LEN(1) + RCOMND(1) + DATA(variable) + SUM(1)
class ResponseMessage implements GS805Message {
  /// Response command code (RCOMND field)
  final int command;

  /// Response data payload (DATA field)
  final Uint8List _data;

  /// Raw message bytes (for debugging)
  final Uint8List? rawBytes;

  /// Create a response message
  ///
  /// [command] - Response command code
  /// [data] - Response data payload
  /// [rawBytes] - Optional raw message bytes for debugging
  ResponseMessage({
    required this.command,
    required Uint8List data,
    this.rawBytes,
  }) : _data = data;

  /// Parse a response message from byte array
  ///
  /// Returns null if the message is invalid
  static ResponseMessage? fromBytes(Uint8List bytes) {
    try {
      // Minimum message size: FLAG2(2) + LEN(1) + RCOMND(1) + SUM(1) = 5 bytes
      if (bytes.length < 5) {
        return null;
      }

      int offset = 0;

      // Check FLAG2
      final flag = (bytes[offset++] << 8) | bytes[offset++];
      if (flag != ProtocolFlags.responseHeader) {
        return null;
      }

      // Read LEN
      final len = bytes[offset++];

      // Validate message length
      // len includes RCOMND + DATA + SUM
      if (bytes.length < 3 + len) {
        // FLAG2(2) + LEN(1) + len
        return null;
      }

      // Read RCOMND
      final rcomnd = bytes[offset++];

      // Read DATA
      final dataLength = len - 2; // len includes RCOMND(1) + SUM(1)
      final data = Uint8List(dataLength);
      for (int i = 0; i < dataLength; i++) {
        data[i] = bytes[offset++];
      }

      // Read and verify SUM
      final receivedChecksum = bytes[offset];

      // Calculate expected checksum
      int expectedChecksum = 0;
      // Sum FLAG2
      expectedChecksum += (ProtocolFlags.responseHeader >> 8) & 0xFF;
      expectedChecksum += ProtocolFlags.responseHeader & 0xFF;
      // Sum LEN
      expectedChecksum += len;
      // Sum RCOMND
      expectedChecksum += rcomnd;
      // Sum DATA
      for (int i = 0; i < dataLength; i++) {
        expectedChecksum += data[i];
      }
      expectedChecksum &= 0xFF;

      // Verify checksum
      if (receivedChecksum != expectedChecksum) {
        // Checksum mismatch - invalid message
        return null;
      }

      return ResponseMessage(
        command: rcomnd,
        data: data,
        rawBytes: bytes,
      );
    } catch (e) {
      // Parsing error
      return null;
    }
  }

  @override
  int get length => 2 + _data.length; // RCOMND + DATA + SUM

  @override
  Uint8List get data => Uint8List.fromList(_data);

  /// Check if this is an active report (STA = 0x7F)
  bool get isActiveReport {
    return _data.isNotEmpty && _data[0] == StatusCodes.activeReport;
  }

  /// Get status code from response (first byte of DATA)
  ///
  /// Returns null if DATA is empty
  int? get statusCode {
    return _data.isNotEmpty ? _data[0] : null;
  }

  /// Check if response indicates success
  bool get isSuccess {
    final status = statusCode;
    return status != null && StatusCodes.isSuccess(status);
  }

  /// Check if response indicates error
  bool get isError {
    final status = statusCode;
    return status != null && StatusCodes.isError(status);
  }

  /// Get status message
  String get statusMessage {
    final status = statusCode;
    return status != null ? StatusCodes.getMessage(status) : 'No status';
  }

  /// Get data as single byte (excluding status code)
  int? getDataByte([int index = 0]) {
    final dataIndex = index + 1; // Skip status code
    return dataIndex < _data.length ? _data[dataIndex] : null;
  }

  /// Get data as 16-bit word (Big Endian, excluding status code)
  int? getDataWord([int index = 0]) {
    final startIndex = index + 1; // Skip status code
    if (startIndex + 1 < _data.length) {
      return (_data[startIndex] << 8) | _data[startIndex + 1];
    }
    return null;
  }

  /// Get data as 32-bit double word (Big Endian, excluding status code)
  int? getDataDWord([int index = 0]) {
    final startIndex = index + 1; // Skip status code
    if (startIndex + 3 < _data.length) {
      return (_data[startIndex] << 24) |
          (_data[startIndex + 1] << 16) |
          (_data[startIndex + 2] << 8) |
          _data[startIndex + 3];
    }
    return null;
  }

  @override
  Uint8List toBytes() {
    // Calculate total message size
    final messageSize = 2 + 1 + 1 + _data.length + 1; // FLAG2 + LEN + RCOMND + DATA + SUM
    final buffer = Uint8List(messageSize);
    int offset = 0;

    // FLAG2 (2 bytes, Big Endian)
    buffer[offset++] = (ProtocolFlags.responseHeader >> 8) & 0xFF;
    buffer[offset++] = ProtocolFlags.responseHeader & 0xFF;

    // LEN (1 byte)
    buffer[offset++] = length;

    // RCOMND (1 byte)
    buffer[offset++] = command;

    // DATA (variable length)
    for (int i = 0; i < _data.length; i++) {
      buffer[offset++] = _data[i];
    }

    // SUM (1 byte)
    int checksum = 0;
    checksum += (ProtocolFlags.responseHeader >> 8) & 0xFF;
    checksum += ProtocolFlags.responseHeader & 0xFF;
    checksum += length;
    checksum += command;
    for (int i = 0; i < _data.length; i++) {
      checksum += _data[i];
    }
    buffer[offset] = checksum & 0xFF;

    return buffer;
  }

  @override
  String toString() {
    final dataHex = _data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return 'ResponseMessage(command: 0x${command.toRadixString(16)}, status: ${statusCode != null ? '0x${statusCode!.toRadixString(16)}' : 'none'}, data: [$dataHex])';
  }
}
