/// Error Code Models
///
/// This file contains models for error codes and machine events.

import '../protocol/gs805_constants.dart';

/// Machine error information
class MachineError {
  /// Raw error code byte
  final int errorCode;

  /// Timestamp when error was detected
  final DateTime timestamp;

  /// Create machine error from error code
  MachineError({
    required this.errorCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Whether this is first heating after power on
  bool get isFirstHeating =>
      (errorCode & ErrorCodeBits.firstHeating) != 0;

  /// Whether lid is missing
  bool get hasNoLid =>
      (errorCode & ErrorCodeBits.noLid) != 0;

  /// Whether there is a track fault
  bool get hasTrackFault =>
      (errorCode & ErrorCodeBits.trackFault) != 0;

  /// Whether there is a sensor fault
  bool get hasSensorFault =>
      (errorCode & ErrorCodeBits.sensorFault) != 0;

  /// Whether both water and cup are missing
  bool get hasNoWaterNoCup =>
      (errorCode & ErrorCodeBits.noWaterNoCup) != 0;

  /// Whether cup is missing
  bool get hasNoCup =>
      (errorCode & ErrorCodeBits.noCup) != 0;

  /// Whether water is missing
  bool get hasNoWater =>
      (errorCode & ErrorCodeBits.noWater) != 0;

  /// Whether there are any errors (excluding first heating)
  bool get hasErrors => (errorCode & ~ErrorCodeBits.firstHeating) != 0;

  /// Get list of active errors
  List<String> get activeErrors =>
      ErrorCodeBits.getActiveErrors(errorCode);

  /// Whether the error prevents drink making
  bool get preventsDrinkMaking =>
      hasNoWater || hasNoCup || hasNoWaterNoCup || hasSensorFault || hasTrackFault;

  @override
  String toString() {
    if (!hasErrors) {
      return isFirstHeating ? 'First heating' : 'No errors';
    }
    return activeErrors.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MachineError &&
          runtimeType == other.runtimeType &&
          errorCode == other.errorCode;

  @override
  int get hashCode => errorCode.hashCode;
}

/// Machine event type
enum MachineEventType {
  /// Cup drop successful (0x05)
  cupDropSuccess(ActiveReportCodes.cupDropSuccess, 'Cup Drop Success'),

  /// Drink making complete (0x10)
  drinkComplete(ActiveReportCodes.drinkComplete, 'Drink Complete'),

  /// Ice drop complete (0x06) - JK86 series only
  iceDropComplete(ActiveReportCodes.iceDropComplete, 'Ice Drop Complete'),

  /// Foreign object on track / Capping failed / Front door module offline (0x20)
  /// JK82 model only
  trackObstacle(ActiveReportCodes.trackObstacle, 'Track Obstacle'),

  /// Unknown event
  unknown(-1, 'Unknown Event');

  /// Event code from protocol
  final int code;

  /// Human-readable event description
  final String description;

  const MachineEventType(this.code, this.description);

  /// Get event type from code
  static MachineEventType fromCode(int code) {
    try {
      return MachineEventType.values.firstWhere((e) => e.code == code);
    } catch (e) {
      return MachineEventType.unknown;
    }
  }

  @override
  String toString() => description;
}

/// Machine event (active report from control board)
class MachineEvent {
  /// Event type
  final MachineEventType type;

  /// Raw event code
  final int eventCode;

  /// Timestamp when event occurred
  final DateTime timestamp;

  /// Additional event data (if any)
  final List<int>? additionalData;

  /// Create machine event
  MachineEvent({
    required this.type,
    required this.eventCode,
    DateTime? timestamp,
    this.additionalData,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create machine event from event code
  factory MachineEvent.fromCode(
    int eventCode, {
    List<int>? additionalData,
  }) {
    return MachineEvent(
      type: MachineEventType.fromCode(eventCode),
      eventCode: eventCode,
      additionalData: additionalData,
    );
  }

  /// Whether this is a success event
  bool get isSuccess =>
      type == MachineEventType.cupDropSuccess ||
      type == MachineEventType.drinkComplete ||
      type == MachineEventType.iceDropComplete;

  /// Whether this is an error event
  bool get isError => type == MachineEventType.trackObstacle;

  @override
  String toString() {
    final parts = <String>[type.description];
    if (additionalData != null && additionalData!.isNotEmpty) {
      parts.add('data: ${additionalData!.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    }
    return parts.join(' - ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MachineEvent &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          eventCode == other.eventCode;

  @override
  int get hashCode => type.hashCode ^ eventCode.hashCode;
}

/// Detailed error information with recovery suggestions
class ErrorInfo {
  /// Machine error
  final MachineError error;

  /// Whether this error requires user intervention
  final bool requiresUserIntervention;

  /// Suggested recovery actions
  final List<String> recoveryActions;

  /// Error severity level
  final ErrorSeverity severity;

  /// Create error information
  ErrorInfo({
    required this.error,
    required this.requiresUserIntervention,
    required this.recoveryActions,
    required this.severity,
  });

  /// Create error info from error code
  factory ErrorInfo.fromError(MachineError error) {
    final actions = <String>[];
    var requiresIntervention = false;
    var severity = ErrorSeverity.info;

    if (error.hasNoWater) {
      actions.add('Refill water tank');
      requiresIntervention = true;
      severity = ErrorSeverity.error;
    }

    if (error.hasNoCup) {
      actions.add('Refill cup dispenser');
      requiresIntervention = true;
      severity = ErrorSeverity.error;
    }

    if (error.hasNoLid) {
      actions.add('Close machine lid');
      requiresIntervention = true;
      severity = ErrorSeverity.warning;
    }

    if (error.hasSensorFault) {
      actions.add('Check NTC sensor');
      requiresIntervention = true;
      severity = ErrorSeverity.error;
    }

    if (error.hasTrackFault) {
      actions.add('Check cup track mechanism');
      requiresIntervention = true;
      severity = ErrorSeverity.error;
    }

    if (error.isFirstHeating && !error.hasErrors) {
      actions.add('Wait for initial heating to complete');
      severity = ErrorSeverity.info;
    }

    if (actions.isEmpty) {
      actions.add('No action required');
    }

    return ErrorInfo(
      error: error,
      requiresUserIntervention: requiresIntervention,
      recoveryActions: actions,
      severity: severity,
    );
  }

  @override
  String toString() {
    return 'Error: ${error.toString()}\n'
        'Severity: $severity\n'
        'Actions: ${recoveryActions.join(', ')}';
  }
}

/// Error severity level
enum ErrorSeverity {
  /// Informational message
  info('Info'),

  /// Warning - operation may be affected
  warning('Warning'),

  /// Error - operation cannot proceed
  error('Error'),

  /// Critical - machine malfunction
  critical('Critical');

  final String label;

  const ErrorSeverity(this.label);

  @override
  String toString() => label;
}
