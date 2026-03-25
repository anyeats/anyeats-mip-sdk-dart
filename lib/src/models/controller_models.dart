/// Controller Models for GS805 R-series commands
///
/// This file contains models for controller status, drink preparation status,
/// object exception info, and electronic lock status.

/// Overall machine status from controller status query (0x1E)
enum OverallMachineStatus {
  /// Machine is idle
  idle(0, 'Idle'),

  /// Machine is busy
  busy(1, 'Busy'),

  /// Machine has an exception
  exception(2, 'Exception'),

  /// Machine has a failure
  failure(3, 'Failure');

  /// Status code value
  final int code;

  /// Human-readable description
  final String description;

  const OverallMachineStatus(this.code, this.description);

  /// Get status from code
  static OverallMachineStatus fromCode(int code) {
    try {
      return OverallMachineStatus.values.firstWhere((s) => s.code == code);
    } catch (e) {
      return OverallMachineStatus.idle;
    }
  }

  @override
  String toString() => description;
}

/// Execution result for lock and drink operations
enum ExecutionResult {
  /// Not executed
  notExecuted(0, 'Not Executed'),

  /// In progress / Executing
  inProgress(1, 'In Progress'),

  /// Completed successfully
  success(2, 'Success'),

  /// Failed
  failed(3, 'Failed');

  /// Result code value
  final int code;

  /// Human-readable description
  final String description;

  const ExecutionResult(this.code, this.description);

  /// Get result from code
  static ExecutionResult fromCode(int code) {
    try {
      return ExecutionResult.values.firstWhere((r) => r.code == code);
    } catch (e) {
      return ExecutionResult.notExecuted;
    }
  }

  @override
  String toString() => description;
}

/// Lock operation types
enum LockOperation {
  /// Unlock the door
  unlock(0x00, 'Unlock'),

  /// Lock the door
  lock(0x01, 'Lock'),

  /// Query lock status
  query(0x02, 'Query');

  /// Operation code
  final int code;

  /// Human-readable description
  final String description;

  const LockOperation(this.code, this.description);

  @override
  String toString() => description;
}

/// Force stop target commands
enum ForceStopTarget {
  /// Stop drink making process
  drinkProcess(0x01, 'Stop Drink Process'),

  /// Stop cup delivery
  cupDelivery(0x24, 'Stop Cup Delivery');

  /// Command code
  final int code;

  /// Human-readable description
  final String description;

  const ForceStopTarget(this.code, this.description);

  @override
  String toString() => description;
}

/// Unit test command types
enum UnitTestCommand {
  /// Dispensing test
  dispensing(0x01, 'Dispensing Test'),

  /// Coordinate test
  coordinate(0x02, 'Coordinate Test'),

  /// Front door test
  frontDoor(0x03, 'Front Door Test'),

  /// Ice module test
  iceModule(0x04, 'Ice Module Test'),

  /// IO control test (R series only)
  ioControl(0x05, 'IO Control Test'),

  /// Combined test
  combined(0x06, 'Combined Test');

  /// Command code
  final int code;

  /// Human-readable description
  final String description;

  const UnitTestCommand(this.code, this.description);

  @override
  String toString() => description;
}

/// Object types for exception info query (0x22)
enum ObjectType {
  /// Pump
  pump(0x0000, 'Pump'),

  /// Water tank
  waterTank(0x0001, 'Water Tank'),

  /// Flow meter
  flowMeter(0x0002, 'Flow Meter'),

  /// Solenoid valve
  solenoid(0x0003, 'Solenoid'),

  /// Waste container
  waste(0x0004, 'Waste'),

  /// Hot water tank
  hotTank(0x0005, 'Hot Tank'),

  /// Cold water tank
  coldTank(0x0006, 'Cold Tank'),

  /// Ice module
  ice(0x0007, 'Ice'),

  /// Track mechanism
  track(0x0008, 'Track'),

  /// Front door module
  frontDoor(0x0009, 'Front Door'),

  /// Grinding module
  grinding(0x000A, 'Grinding'),

  /// Main board
  board(0x000B, 'Board');

  /// Object number code
  final int code;

  /// Human-readable description
  final String description;

  const ObjectType(this.code, this.description);

  /// Get object type from code
  static ObjectType? fromCode(int code) {
    try {
      return ObjectType.values.firstWhere((o) => o.code == code);
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() => description;
}

/// Drink failure cause codes (0x1F response)
enum DrinkFailureCause {
  /// No failure
  none(0, 'None'),

  /// EM01-EM26 failure codes
  em01(1, 'EM01'), em02(2, 'EM02'), em03(3, 'EM03'), em04(4, 'EM04'),
  em05(5, 'EM05'), em06(6, 'EM06'), em07(7, 'EM07'), em08(8, 'EM08'),
  em09(9, 'EM09'), em10(10, 'EM10'), em11(11, 'EM11'), em12(12, 'EM12'),
  em13(13, 'EM13'), em14(14, 'EM14'), em15(15, 'EM15'), em16(16, 'EM16'),
  em17(17, 'EM17'), em18(18, 'EM18'), em19(19, 'EM19'), em20(20, 'EM20'),
  em21(21, 'EM21'), em22(22, 'EM22'), em23(23, 'EM23'), em24(24, 'EM24'),
  em25(25, 'EM25'), em26(26, 'EM26');

  /// Failure code
  final int code;

  /// Human-readable description
  final String description;

  const DrinkFailureCause(this.code, this.description);

  /// Get failure cause from code
  static DrinkFailureCause fromCode(int code) {
    try {
      return DrinkFailureCause.values.firstWhere((f) => f.code == code);
    } catch (e) {
      return DrinkFailureCause.none;
    }
  }

  @override
  String toString() => description;
}

/// Main controller status (parsed from 0x1E ST_INFO 32-bit field)
class ControllerStatus {
  /// Raw 32-bit status info
  final int rawValue;

  /// Current drink number being made (0 = none)
  final int drinkNumber;

  /// Timestamp when status was retrieved
  final DateTime timestamp;

  /// Create controller status from raw 32-bit value and drink number
  ControllerStatus({
    required this.rawValue,
    required this.drinkNumber,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Parse controller status from response data bytes.
  ///
  /// [data] must contain at least 5 bytes: ST_INFO(4) + drinkNo(1)
  factory ControllerStatus.fromBytes(List<int> data) {
    if (data.length < 5) {
      throw ArgumentError('Controller status requires at least 5 bytes, got ${data.length}');
    }
    final rawValue = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    return ControllerStatus(
      rawValue: rawValue,
      drinkNumber: data[4],
    );
  }

  // --- Bit 0-1: Overall status ---

  /// Overall machine status
  OverallMachineStatus get overallStatus =>
      OverallMachineStatus.fromCode(rawValue & 0x03);

  // --- Module offline flags ---

  /// Front door module is offline
  bool get isFrontDoorOffline => (rawValue & (1 << 2)) != 0;

  /// Ice module is offline
  bool get isIceOffline => (rawValue & (1 << 3)) != 0;

  /// Grinding module is offline
  bool get isGrindingOffline => (rawValue & (1 << 4)) != 0;

  // --- Module fault flags ---

  /// Front door module has a fault
  bool get hasFrontDoorFault => (rawValue & (1 << 5)) != 0;

  /// Ice module has a fault
  bool get hasIceFault => (rawValue & (1 << 6)) != 0;

  /// Grinding module has a fault
  bool get hasGrindingFault => (rawValue & (1 << 7)) != 0;

  // --- Supply status ---

  /// No cup available
  bool get hasNoCup => (rawValue & (1 << 8)) != 0;

  /// No lid available
  bool get hasNoLid => (rawValue & (1 << 9)) != 0;

  /// Water tank level is low
  bool get isWaterTankLow => (rawValue & (1 << 10)) != 0;

  /// Waste tank is near full
  bool get isWasteTankWarning => (rawValue & (1 << 11)) != 0;

  // --- Operational status ---

  /// Machine is performing first heating after power on
  bool get isFirstHeating => (rawValue & (1 << 12)) != 0;

  /// Cup is on the holder
  bool get isCupOnHolder => (rawValue & (1 << 13)) != 0;

  /// Bean hopper is empty
  bool get isBeanHopperEmpty => (rawValue & (1 << 14)) != 0;

  /// Sensor abnormal
  bool get hasSensorAbnormal => (rawValue & (1 << 15)) != 0;

  // --- Tank water status (Bit 16-19) ---

  /// Tank 1 has no water
  bool get isTank1NoWater => (rawValue & (1 << 16)) != 0;

  /// Tank 2 has no water
  bool get isTank2NoWater => (rawValue & (1 << 17)) != 0;

  /// Tank 3 has no water
  bool get isTank3NoWater => (rawValue & (1 << 18)) != 0;

  /// Tank 4 has no water
  bool get isTank4NoWater => (rawValue & (1 << 19)) != 0;

  // --- Pump faults (Bit 20-23) ---

  /// Pump 1 has a fault
  bool get hasPump1Fault => (rawValue & (1 << 20)) != 0;

  /// Pump 2 has a fault
  bool get hasPump2Fault => (rawValue & (1 << 21)) != 0;

  /// Pump 3 has a fault
  bool get hasPump3Fault => (rawValue & (1 << 22)) != 0;

  /// Pump 4 has a fault
  bool get hasPump4Fault => (rawValue & (1 << 23)) != 0;

  // --- System faults (Bit 24-31) ---

  /// Booster pump has a fault
  bool get hasBoosterPumpFault => (rawValue & (1 << 24)) != 0;

  /// Hot tank heating timeout
  bool get hasHotTankTimeout => (rawValue & (1 << 25)) != 0;

  /// Cold tank cooling timeout
  bool get hasColdTankTimeout => (rawValue & (1 << 26)) != 0;

  /// Drain solenoid has a fault
  bool get hasDrainSolenoidFault => (rawValue & (1 << 27)) != 0;

  /// Cup dropper 1 has a fault
  bool get hasCupDropper1Fault => (rawValue & (1 << 28)) != 0;

  /// Cup dropper 2 has a fault
  bool get hasCupDropper2Fault => (rawValue & (1 << 29)) != 0;

  /// Track has an error
  bool get hasTrackError => (rawValue & (1 << 30)) != 0;

  /// Lock has a fault
  bool get hasLockFault => (rawValue & (1 << 31)) != 0;

  /// Whether the machine is idle
  bool get isIdle => overallStatus == OverallMachineStatus.idle;

  /// Whether the machine is busy
  bool get isBusy => overallStatus == OverallMachineStatus.busy;

  /// Whether the machine has any faults
  bool get hasAnyFault =>
      hasFrontDoorFault || hasIceFault || hasGrindingFault ||
      hasPump1Fault || hasPump2Fault || hasPump3Fault || hasPump4Fault ||
      hasBoosterPumpFault || hasHotTankTimeout || hasColdTankTimeout ||
      hasDrainSolenoidFault || hasCupDropper1Fault || hasCupDropper2Fault ||
      hasTrackError || hasLockFault || hasSensorAbnormal;

  /// Get list of active faults
  List<String> get activeFaults {
    final faults = <String>[];
    if (hasFrontDoorFault) faults.add('Front door fault');
    if (hasIceFault) faults.add('Ice fault');
    if (hasGrindingFault) faults.add('Grinding fault');
    if (hasSensorAbnormal) faults.add('Sensor abnormal');
    if (hasPump1Fault) faults.add('Pump 1 fault');
    if (hasPump2Fault) faults.add('Pump 2 fault');
    if (hasPump3Fault) faults.add('Pump 3 fault');
    if (hasPump4Fault) faults.add('Pump 4 fault');
    if (hasBoosterPumpFault) faults.add('Booster pump fault');
    if (hasHotTankTimeout) faults.add('Hot tank timeout');
    if (hasColdTankTimeout) faults.add('Cold tank timeout');
    if (hasDrainSolenoidFault) faults.add('Drain solenoid fault');
    if (hasCupDropper1Fault) faults.add('Cup dropper 1 fault');
    if (hasCupDropper2Fault) faults.add('Cup dropper 2 fault');
    if (hasTrackError) faults.add('Track error');
    if (hasLockFault) faults.add('Lock fault');
    return faults;
  }

  /// Get list of active warnings
  List<String> get activeWarnings {
    final warnings = <String>[];
    if (isFrontDoorOffline) warnings.add('Front door offline');
    if (isIceOffline) warnings.add('Ice offline');
    if (isGrindingOffline) warnings.add('Grinding offline');
    if (hasNoCup) warnings.add('No cup');
    if (hasNoLid) warnings.add('No lid');
    if (isWaterTankLow) warnings.add('Water tank low');
    if (isWasteTankWarning) warnings.add('Waste tank warning');
    if (isBeanHopperEmpty) warnings.add('Bean hopper empty');
    if (isTank1NoWater) warnings.add('Tank 1 no water');
    if (isTank2NoWater) warnings.add('Tank 2 no water');
    if (isTank3NoWater) warnings.add('Tank 3 no water');
    if (isTank4NoWater) warnings.add('Tank 4 no water');
    return warnings;
  }

  @override
  String toString() {
    final parts = <String>['Status: $overallStatus'];
    if (drinkNumber > 0) parts.add('Drink: $drinkNumber');
    if (activeFaults.isNotEmpty) parts.add('Faults: ${activeFaults.join(', ')}');
    if (activeWarnings.isNotEmpty) parts.add('Warnings: ${activeWarnings.join(', ')}');
    return parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControllerStatus &&
          runtimeType == other.runtimeType &&
          rawValue == other.rawValue &&
          drinkNumber == other.drinkNumber;

  @override
  int get hashCode => rawValue.hashCode ^ drinkNumber.hashCode;
}

/// Drink preparation status (parsed from 0x1F DK_INFO 32-bit field)
class DrinkPreparationStatus {
  /// Raw 32-bit drink info value
  final int rawValue;

  /// Timestamp when status was retrieved
  final DateTime timestamp;

  /// Create drink preparation status from raw 32-bit value
  DrinkPreparationStatus({
    required this.rawValue,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Parse drink preparation status from response data bytes.
  ///
  /// [data] must contain at least 4 bytes: DK_INFO(4)
  factory DrinkPreparationStatus.fromBytes(List<int> data) {
    if (data.length < 4) {
      throw ArgumentError('Drink status requires at least 4 bytes, got ${data.length}');
    }
    final rawValue = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    return DrinkPreparationStatus(rawValue: rawValue);
  }

  /// Drink number (Bit 0-4)
  int get drinkNumber => rawValue & 0x1F;

  /// Making type: false=local, true=command (Bit 5)
  bool get isCommandMade => (rawValue & (1 << 5)) != 0;

  /// Cup has been placed (Bit 6)
  bool get isCupPlaced => (rawValue & (1 << 6)) != 0;

  /// Waiting for cup retrieval (Bit 7)
  bool get isWaitingForRetrieval => (rawValue & (1 << 7)) != 0;

  /// Sync status (Bit 8)
  bool get isSynced => (rawValue & (1 << 8)) != 0;

  /// Process type: false=normal, true=abnormal (Bit 9)
  bool get isAbnormalProcess => (rawValue & (1 << 9)) != 0;

  /// Current step number (Bit 10-16)
  int get currentStep => (rawValue >> 10) & 0x7F;

  /// Total number of steps (Bit 17-23)
  int get totalSteps => (rawValue >> 17) & 0x7F;

  /// Failure cause code (Bit 24-29)
  DrinkFailureCause get failureCause =>
      DrinkFailureCause.fromCode((rawValue >> 24) & 0x3F);

  /// Execution result (Bit 30-31)
  ExecutionResult get result =>
      ExecutionResult.fromCode((rawValue >> 30) & 0x03);

  /// Whether drink is currently being made
  bool get isExecuting => result == ExecutionResult.inProgress;

  /// Whether drink making completed successfully
  bool get isSuccess => result == ExecutionResult.success;

  /// Whether drink making failed
  bool get isFailed => result == ExecutionResult.failed;

  /// Progress as a percentage (0.0 - 1.0)
  double get progress {
    if (totalSteps == 0) return 0.0;
    return currentStep / totalSteps;
  }

  @override
  String toString() {
    final parts = <String>['Result: $result'];
    if (drinkNumber > 0) parts.add('Drink: $drinkNumber');
    if (isExecuting) parts.add('Step: $currentStep/$totalSteps');
    if (isFailed) parts.add('Failure: $failureCause');
    return parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrinkPreparationStatus &&
          runtimeType == other.runtimeType &&
          rawValue == other.rawValue;

  @override
  int get hashCode => rawValue.hashCode;
}

/// Object exception information (parsed from 0x22 response)
class ObjectExceptionInfo {
  /// Response status code
  final int statusCode;

  /// Raw 32-bit status info
  final int stInfo;

  /// Raw 16-bit operation info
  final int opInfo;

  /// Object number
  final int objectNumber;

  /// Info code
  final int infoCode;

  /// Auto info byte
  final int autInfo;

  /// Timestamp when info was retrieved
  final DateTime timestamp;

  /// Create object exception info
  ObjectExceptionInfo({
    required this.statusCode,
    required this.stInfo,
    required this.opInfo,
    required this.objectNumber,
    required this.infoCode,
    required this.autInfo,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Parse object exception info from response data bytes.
  ///
  /// [data] must contain at least 12 bytes:
  /// STA(1) + ST_INFO(4) + OP_INFO(2) + OBJ_NO(2) + INFO_CODE(2) + AUT_INFO(1)
  factory ObjectExceptionInfo.fromBytes(List<int> data) {
    if (data.length < 12) {
      throw ArgumentError('Object exception info requires at least 12 bytes, got ${data.length}');
    }
    return ObjectExceptionInfo(
      statusCode: data[0],
      stInfo: (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4],
      opInfo: (data[5] << 8) | data[6],
      objectNumber: (data[7] << 8) | data[8],
      infoCode: (data[9] << 8) | data[10],
      autInfo: data[11],
    );
  }

  /// Get the object type from the object number
  ObjectType? get objectType => ObjectType.fromCode(objectNumber);

  /// Whether the status indicates success
  bool get isSuccess => statusCode == 0x00;

  @override
  String toString() {
    final objName = objectType?.description ?? 'Unknown(0x${objectNumber.toRadixString(16)})';
    return 'ObjectException($objName, stInfo: 0x${stInfo.toRadixString(16)}, '
        'opInfo: 0x${opInfo.toRadixString(16)}, infoCode: 0x${infoCode.toRadixString(16)})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectExceptionInfo &&
          runtimeType == other.runtimeType &&
          stInfo == other.stInfo &&
          opInfo == other.opInfo &&
          objectNumber == other.objectNumber &&
          infoCode == other.infoCode;

  @override
  int get hashCode =>
      stInfo.hashCode ^ opInfo.hashCode ^ objectNumber.hashCode ^ infoCode.hashCode;
}

/// Electronic lock status (parsed from 0x1B LOCK_S byte)
class LockStatus {
  /// Response status code
  final int statusCode;

  /// Raw lock status byte
  final int rawValue;

  /// Timestamp when status was retrieved
  final DateTime timestamp;

  /// Create lock status from raw byte
  LockStatus({
    required this.statusCode,
    required this.rawValue,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Execution result (Bit 6-7)
  ExecutionResult get executionResult =>
      ExecutionResult.fromCode((rawValue >> 6) & 0x03);

  /// Whether the lock is currently locked (Bit 0)
  bool get isLocked => (rawValue & 0x01) != 0;

  /// Whether the lock is currently unlocked
  bool get isUnlocked => !isLocked;

  /// Whether the status indicates success
  bool get isSuccess => statusCode == 0x00;

  @override
  String toString() {
    return 'Lock(${isLocked ? 'Locked' : 'Unlocked'}, result: $executionResult)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockStatus &&
          runtimeType == other.runtimeType &&
          statusCode == other.statusCode &&
          rawValue == other.rawValue;

  @override
  int get hashCode => statusCode.hashCode ^ rawValue.hashCode;
}
