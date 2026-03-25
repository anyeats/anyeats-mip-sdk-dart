/// GS805 Exception Classes
///
/// This file contains custom exception classes for GS805 serial communication.

import '../protocol/gs805_constants.dart';

/// Base exception class for all GS805-related errors
class GS805Exception implements Exception {
  /// Error message
  final String message;

  /// Optional error code
  final int? code;

  /// Original exception that caused this error (if any)
  final Object? cause;

  /// Stack trace of the original error (if any)
  final StackTrace? stackTrace;

  /// Create a GS805 exception
  GS805Exception(
    this.message, {
    this.code,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    final parts = <String>['GS805Exception: $message'];
    if (code != null) {
      parts.add('(code: 0x${code!.toRadixString(16)})');
    }
    if (cause != null) {
      parts.add('Caused by: $cause');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when communication with the machine fails
class CommunicationException extends GS805Exception {
  CommunicationException(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() => 'CommunicationException: $message';
}

/// Exception thrown when a command times out
class TimeoutException extends CommunicationException {
  /// Timeout duration in milliseconds
  final int timeoutMs;

  /// Number of retry attempts made
  final int retryCount;

  TimeoutException(
    super.message, {
    required this.timeoutMs,
    this.retryCount = 0,
  });

  @override
  String toString() =>
      'TimeoutException: $message (timeout: ${timeoutMs}ms, retries: $retryCount)';
}

/// Exception thrown when the machine returns an error status
class MachineErrorException extends GS805Exception {
  /// Status code from the machine
  final int statusCode;

  /// Human-readable status message
  final String statusMessage;

  MachineErrorException({
    required this.statusCode,
    String? message,
  })  : statusMessage = StatusCodes.getMessage(statusCode),
        super(
          message ?? StatusCodes.getMessage(statusCode),
          code: statusCode,
        );

  /// Create from status code
  factory MachineErrorException.fromStatus(int statusCode, {String? context}) {
    final message = context != null
        ? '$context: ${StatusCodes.getMessage(statusCode)}'
        : StatusCodes.getMessage(statusCode);
    return MachineErrorException(
      statusCode: statusCode,
      message: message,
    );
  }

  @override
  String toString() =>
      'MachineErrorException: $statusMessage (0x${statusCode.toRadixString(16)})';
}

/// Exception thrown when the machine is busy
class MachineBusyException extends MachineErrorException {
  MachineBusyException({String? message})
      : super(
          statusCode: StatusCodes.busy,
          message: message ?? 'Machine is busy',
        );

  @override
  String toString() => 'MachineBusyException: $message';
}

/// Exception thrown when a parameter is invalid
class ParameterException extends MachineErrorException {
  /// Parameter name that caused the error
  final String? parameterName;

  /// Invalid parameter value
  final dynamic parameterValue;

  ParameterException({
    String? message,
    this.parameterName,
    this.parameterValue,
  }) : super(
          statusCode: StatusCodes.parameterError,
          message: message ?? 'Invalid parameter',
        );

  @override
  String toString() {
    final parts = <String>['ParameterException: $message'];
    if (parameterName != null) {
      parts.add('($parameterName = $parameterValue)');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when balance is insufficient
class InsufficientBalanceException extends MachineErrorException {
  /// Required amount
  final int? requiredAmount;

  /// Available balance
  final int? availableBalance;

  InsufficientBalanceException({
    String? message,
    this.requiredAmount,
    this.availableBalance,
  }) : super(
          statusCode: StatusCodes.insufficientBalance,
          message: message ?? 'Insufficient balance',
        );

  @override
  String toString() {
    final parts = <String>['InsufficientBalanceException: $message'];
    if (requiredAmount != null && availableBalance != null) {
      parts.add('(required: $requiredAmount, available: $availableBalance)');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when a serial port operation fails
class SerialPortException extends CommunicationException {
  /// Port name that failed
  final String? portName;

  SerialPortException(
    super.message, {
    this.portName,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final parts = <String>['SerialPortException: $message'];
    if (portName != null) {
      parts.add('(port: $portName)');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when a message cannot be parsed
class MessageParseException extends GS805Exception {
  /// Raw message bytes that failed to parse
  final List<int>? rawBytes;

  MessageParseException(
    super.message, {
    this.rawBytes,
  });

  @override
  String toString() {
    final parts = <String>['MessageParseException: $message'];
    if (rawBytes != null) {
      final hex = rawBytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      parts.add('(bytes: $hex)');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when the machine is not connected
class NotConnectedException extends GS805Exception {
  NotConnectedException([String? message])
      : super(message ?? 'Not connected to machine');

  @override
  String toString() => 'NotConnectedException: $message';
}

/// Exception thrown when a connection attempt fails
class ConnectionException extends GS805Exception {
  /// Port name that failed to connect
  final String? portName;

  ConnectionException(
    super.message, {
    this.portName,
    super.cause,
  });

  @override
  String toString() {
    final parts = <String>['ConnectionException: $message'];
    if (portName != null) {
      parts.add('(port: $portName)');
    }
    return parts.join(' ');
  }
}

/// Exception thrown when an operation is cancelled
class OperationCancelledException extends GS805Exception {
  OperationCancelledException([String? message])
      : super(message ?? 'Operation was cancelled');

  @override
  String toString() => 'OperationCancelledException: $message';
}
