/// Message Parser
///
/// This file contains the message parser that assembles complete messages
/// from incoming byte streams.

import 'dart:async';
import 'dart:typed_data';

import '../protocol/gs805_protocol.dart';
import '../protocol/gs805_message.dart';

/// Message parser that assembles complete messages from byte streams
class MessageParser {
  final BytesBuilder _buffer = BytesBuilder();
  final StreamController<ResponseMessage> _messageController =
      StreamController<ResponseMessage>.broadcast();

  /// Whether the parser is currently active
  bool _isActive = true;

  /// Create a message parser
  MessageParser();

  /// Add incoming bytes to the parser
  ///
  /// The parser will attempt to extract complete messages and emit them
  /// through the [messageStream]
  void addBytes(Uint8List bytes) {
    if (!_isActive) {
      return;
    }

    // Add new bytes to buffer
    _buffer.add(bytes);

    // Try to extract messages
    _extractMessages();
  }

  /// Extract complete messages from buffer
  void _extractMessages() {
    while (true) {
      final bufferBytes = _buffer.toBytes();

      // Need at least 5 bytes for a minimal message
      if (bufferBytes.length < 5) {
        break;
      }

      // Try to extract a message
      final result = GS805Protocol.extractMessage(
        bufferBytes,
        isResponse: true,
      );

      if (result.message != null) {
        // Successfully extracted a message
        final response = ResponseMessage.fromBytes(result.message!);
        if (response != null) {
          _messageController.add(response);
        }

        // Remove consumed bytes from buffer
        if (result.consumed > 0) {
          _removeFromBuffer(result.consumed);
        }
      } else if (result.consumed > 0) {
        // Invalid data was consumed (bad checksum, etc.)
        // Remove it and try again
        _removeFromBuffer(result.consumed);
      } else {
        // Incomplete message or no message found
        // Keep the buffer and wait for more data
        break;
      }
    }
  }

  /// Remove bytes from the beginning of the buffer
  void _removeFromBuffer(int count) {
    final bufferBytes = _buffer.toBytes();
    if (count >= bufferBytes.length) {
      _buffer.clear();
    } else {
      final remaining = bufferBytes.sublist(count);
      _buffer.clear();
      _buffer.add(remaining);
    }
  }

  /// Stream of parsed messages
  Stream<ResponseMessage> get messageStream => _messageController.stream;

  /// Get current buffer size (for debugging)
  int get bufferSize => _buffer.length;

  /// Clear the internal buffer
  void clearBuffer() {
    _buffer.clear();
  }

  /// Close the parser and release resources
  Future<void> close() async {
    _isActive = false;
    _buffer.clear();
    await _messageController.close();
  }
}

/// Message stream transformer that converts byte stream to message stream
class MessageStreamTransformer
    extends StreamTransformerBase<Uint8List, ResponseMessage> {
  @override
  Stream<ResponseMessage> bind(Stream<Uint8List> stream) {
    final parser = MessageParser();
    final controller = StreamController<ResponseMessage>(
      onCancel: () => parser.close(),
    );

    // Forward parsed messages to controller
    parser.messageStream.listen(
      (message) => controller.add(message),
      onError: (error) => controller.addError(error),
    );

    // Feed bytes to parser
    stream.listen(
      (bytes) => parser.addBytes(bytes),
      onError: (error) => controller.addError(error),
      onDone: () {
        parser.close().then((_) => controller.close());
      },
    );

    return controller.stream;
  }
}

/// Extension on Stream<Uint8List> to easily parse messages
extension MessageStreamExt on Stream<Uint8List> {
  /// Parse incoming bytes into ResponseMessage objects
  Stream<ResponseMessage> parseMessages() {
    return transform(MessageStreamTransformer());
  }
}
