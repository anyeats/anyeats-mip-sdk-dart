/// Machine Status Models
///
/// This file contains models for machine status and state.

import '../protocol/gs805_constants.dart';

/// Machine status enumeration
enum MachineStatus {
  /// Device is ready and idle
  ready(StatusCodes.success, 'Ready'),

  /// Device is busy processing a command
  busy(StatusCodes.busy, 'Busy'),

  /// Device has an error
  error(StatusCodes.error, 'Error'),

  /// Parameter error occurred
  parameterError(StatusCodes.parameterError, 'Parameter Error'),

  /// Insufficient balance
  insufficientBalance(StatusCodes.insufficientBalance, 'Insufficient Balance'),

  /// Configuration restricted
  configRestricted(StatusCodes.configRestricted, 'Configuration Restricted'),

  /// Data or recipe not found
  dataNotFound(StatusCodes.dataNotFound, 'Data Not Found'),

  /// Execution conditions not met
  conditionsNotMet(StatusCodes.conditionsNotMet, 'Conditions Not Met'),

  /// Device or function not found
  deviceNotFound(StatusCodes.deviceNotFound, 'Device Not Found'),

  /// Unknown status
  unknown(-1, 'Unknown');

  /// Status code from protocol
  final int code;

  /// Human-readable status message
  final String message;

  const MachineStatus(this.code, this.message);

  /// Get machine status from status code
  static MachineStatus fromCode(int code) {
    try {
      return MachineStatus.values.firstWhere((s) => s.code == code);
    } catch (e) {
      return MachineStatus.unknown;
    }
  }

  /// Whether the status indicates the machine is ready
  bool get isReady => this == MachineStatus.ready;

  /// Whether the status indicates an error
  bool get isError => code >= StatusCodes.error && code < 0x7F;

  @override
  String toString() => message;
}

/// Machine balance information
class MachineBalance {
  /// Current balance in token value (0-99)
  final int balance;

  /// Timestamp when balance was retrieved
  final DateTime timestamp;

  /// Create machine balance information
  MachineBalance({
    required this.balance,
    DateTime? timestamp,
  })  : timestamp = timestamp ?? DateTime.now() {
    if (balance < 0 || balance > PriceLimits.maxBalance) {
      throw ArgumentError(
        'Invalid balance: $balance (must be 0-${PriceLimits.maxBalance})',
      );
    }
  }

  /// Whether balance is sufficient for a given price
  bool isSufficient(int price) => balance >= price;

  /// Whether balance is empty
  bool get isEmpty => balance == 0;

  /// Whether balance is full
  bool get isFull => balance >= PriceLimits.maxBalance;

  @override
  String toString() => '$balance tokens';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MachineBalance &&
          runtimeType == other.runtimeType &&
          balance == other.balance;

  @override
  int get hashCode => balance.hashCode;
}

/// Changer status information (for coin/change dispenser)
class ChangerStatus {
  /// Whether changer is currently dispensing change
  final bool isDispensing;

  /// Whether shaft sensor has a fault
  final bool hasShaftSensorFault;

  /// Whether prism sensor has a fault
  final bool hasPrismSensorFault;

  /// Whether changer has insufficient coins
  final bool hasInsufficientCoins;

  /// Whether motor has a fault
  final bool hasMotorFault;

  /// Create changer status from status byte
  ChangerStatus.fromByte(int statusByte)
      : isDispensing = (statusByte & 0x10) != 0,
        hasShaftSensorFault = (statusByte & 0x08) != 0,
        hasPrismSensorFault = (statusByte & 0x04) != 0,
        hasInsufficientCoins = (statusByte & 0x02) != 0,
        hasMotorFault = (statusByte & 0x01) != 0;

  /// Whether changer has any faults
  bool get hasFaults =>
      hasShaftSensorFault ||
      hasPrismSensorFault ||
      hasInsufficientCoins ||
      hasMotorFault;

  /// Get list of active faults
  List<String> get activeFaults {
    final faults = <String>[];
    if (hasShaftSensorFault) faults.add('Shaft sensor fault');
    if (hasPrismSensorFault) faults.add('Prism sensor fault');
    if (hasInsufficientCoins) faults.add('Insufficient coins');
    if (hasMotorFault) faults.add('Motor fault');
    return faults;
  }

  @override
  String toString() {
    if (isDispensing) return 'Dispensing change';
    if (hasFaults) return 'Faults: ${activeFaults.join(', ')}';
    return 'Ready';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangerStatus &&
          runtimeType == other.runtimeType &&
          isDispensing == other.isDispensing &&
          hasShaftSensorFault == other.hasShaftSensorFault &&
          hasPrismSensorFault == other.hasPrismSensorFault &&
          hasInsufficientCoins == other.hasInsufficientCoins &&
          hasMotorFault == other.hasMotorFault;

  @override
  int get hashCode =>
      isDispensing.hashCode ^
      hasShaftSensorFault.hashCode ^
      hasPrismSensorFault.hashCode ^
      hasInsufficientCoins.hashCode ^
      hasMotorFault.hashCode;
}

/// Complete machine state information
class MachineState {
  /// Current machine status
  final MachineStatus status;

  /// Current balance (null if not queried)
  final MachineBalance? balance;

  /// Hot drink temperature settings (null if not set)
  final int? hotTempUpper;
  final int? hotTempLower;

  /// Cold drink temperature settings (null if not set)
  final int? coldTempUpper;
  final int? coldTempLower;

  /// Cup drop mode (null if not set)
  final int? cupDropMode;

  /// Timestamp when state was retrieved
  final DateTime timestamp;

  /// Create machine state
  MachineState({
    required this.status,
    this.balance,
    this.hotTempUpper,
    this.hotTempLower,
    this.coldTempUpper,
    this.coldTempLower,
    this.cupDropMode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a copy with updated values
  MachineState copyWith({
    MachineStatus? status,
    MachineBalance? balance,
    int? hotTempUpper,
    int? hotTempLower,
    int? coldTempUpper,
    int? coldTempLower,
    int? cupDropMode,
  }) {
    return MachineState(
      status: status ?? this.status,
      balance: balance ?? this.balance,
      hotTempUpper: hotTempUpper ?? this.hotTempUpper,
      hotTempLower: hotTempLower ?? this.hotTempLower,
      coldTempUpper: coldTempUpper ?? this.coldTempUpper,
      coldTempLower: coldTempLower ?? this.coldTempLower,
      cupDropMode: cupDropMode ?? this.cupDropMode,
    );
  }

  @override
  String toString() {
    final parts = <String>['Status: $status'];
    if (balance != null) parts.add('Balance: $balance');
    if (hotTempUpper != null && hotTempLower != null) {
      parts.add('Hot: $hotTempLower-${hotTempUpper}°C');
    }
    if (coldTempUpper != null && coldTempLower != null) {
      parts.add('Cold: $coldTempLower-${coldTempUpper}°C');
    }
    return parts.join(', ');
  }
}
