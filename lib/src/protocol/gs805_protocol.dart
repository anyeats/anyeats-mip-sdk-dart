/// GS805 Protocol Utilities
///
/// This file contains protocol encoding/decoding utilities and helper functions.

import 'dart:typed_data';
import 'gs805_constants.dart';
import 'gs805_message.dart';
import '../models/recipe_step.dart';

/// Protocol utility class for GS805 serial communication
class GS805Protocol {
  /// Calculate 8-bit checksum for message bytes
  ///
  /// The checksum is the lower 8 bits of the sum of all bytes
  static int calculateChecksum(Uint8List bytes) {
    int sum = 0;
    for (int byte in bytes) {
      sum += byte;
    }
    return sum & 0xFF;
  }

  /// Verify checksum of a complete message
  ///
  /// Returns true if checksum is valid
  static bool verifyChecksum(Uint8List message) {
    if (message.length < 5) {
      return false;
    }

    // Calculate checksum for all bytes except the last one (SUM field)
    final checksumBytes = message.sublist(0, message.length - 1);
    final calculatedChecksum = calculateChecksum(checksumBytes);

    // Compare with received checksum (last byte)
    final receivedChecksum = message[message.length - 1];

    return calculatedChecksum == receivedChecksum;
  }

  /// Convert 16-bit integer to Big Endian byte array
  static Uint8List int16ToBigEndian(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError('Value out of range for 16-bit integer: $value');
    }
    return Uint8List.fromList([
      (value >> 8) & 0xFF, // High byte
      value & 0xFF, // Low byte
    ]);
  }

  /// Convert Big Endian byte array to 16-bit integer
  static int bigEndianToInt16(Uint8List bytes, [int offset = 0]) {
    if (offset + 1 >= bytes.length) {
      throw ArgumentError('Not enough bytes for 16-bit integer');
    }
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  /// Convert 32-bit integer to Big Endian byte array
  static Uint8List int32ToBigEndian(int value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError('Value out of range for 32-bit integer: $value');
    }
    return Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Convert Big Endian byte array to 32-bit integer
  static int bigEndianToInt32(Uint8List bytes, [int offset = 0]) {
    if (offset + 3 >= bytes.length) {
      throw ArgumentError('Not enough bytes for 32-bit integer');
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Find message start position in byte stream
  ///
  /// Searches for FLAG1 (0xAA55) or FLAG2 (0xA55A) header
  /// Returns the offset of the header, or -1 if not found
  static int findMessageStart(Uint8List bytes, {bool isResponse = false}) {
    if (bytes.length < 2) {
      return -1;
    }

    final targetFlag =
        isResponse ? ProtocolFlags.responseHeader : ProtocolFlags.commandHeader;

    for (int i = 0; i < bytes.length - 1; i++) {
      final flag = (bytes[i] << 8) | bytes[i + 1];
      if (flag == targetFlag) {
        return i;
      }
    }

    return -1;
  }

  /// Extract complete message from byte stream
  ///
  /// Returns the message bytes if a complete message is found, null otherwise
  /// Also returns the number of bytes consumed from the stream
  static ({Uint8List? message, int consumed}) extractMessage(
    Uint8List bytes, {
    bool isResponse = false,
  }) {
    // Find message start
    final startOffset = findMessageStart(bytes, isResponse: isResponse);
    if (startOffset == -1) {
      // No header found, consume all bytes
      return (message: null, consumed: bytes.length);
    }

    // Check if we have enough bytes for header + LEN
    if (startOffset + 3 > bytes.length) {
      // Not enough data yet, don't consume anything
      return (message: null, consumed: 0);
    }

    // Read LEN field
    final len = bytes[startOffset + 2];

    // Calculate total message length
    // FLAG(2) + LEN(1) + len
    final totalLength = 3 + len;

    // Check if we have the complete message
    if (startOffset + totalLength > bytes.length) {
      // Incomplete message, don't consume anything
      return (message: null, consumed: 0);
    }

    // Extract complete message
    final message = bytes.sublist(startOffset, startOffset + totalLength);

    // Verify checksum
    if (!verifyChecksum(message)) {
      // Invalid checksum, skip this message and continue searching
      return (message: null, consumed: startOffset + totalLength);
    }

    // Return message and consumed bytes
    return (message: message, consumed: startOffset + totalLength);
  }

  /// Create a command to make a drink
  static CommandMessage makeDrinkCommand(int drinkNumber,
      {bool useLocalBalance = false}) {
    if (!DrinkNumbers.isValid(drinkNumber)) {
      throw ArgumentError('Invalid drink number: 0x${drinkNumber.toRadixString(16)}');
    }

    return CommandMessage(
      command: CommandCodes.makeDrink,
      data: Uint8List.fromList([
        drinkNumber,
        useLocalBalance
            ? MakeDrinkParams.useLocalBalance
            : MakeDrinkParams.directCommand,
      ]),
    );
  }

  /// Create a command to set hot drink temperature
  static CommandMessage setHotTemperatureCommand(int high, int low) {
    if (!TemperatureLimits.isValidHotTemp(high, low)) {
      throw ArgumentError(
          'Invalid hot temperature range: high=$high, low=$low');
    }

    return CommandMessage(
      command: CommandCodes.setHotTemperature,
      data: Uint8List.fromList([high, low]),
    );
  }

  /// Create a command to set cold drink temperature
  static CommandMessage setColdTemperatureCommand(int high, int low) {
    if (!TemperatureLimits.isValidColdTemp(high, low)) {
      throw ArgumentError(
          'Invalid cold temperature range: high=$high, low=$low');
    }

    return CommandMessage(
      command: CommandCodes.setColdTemperature,
      data: Uint8List.fromList([high, low]),
    );
  }

  /// Create a command to get sales count
  static CommandMessage getSalesCountCommand(int drinkNumber) {
    if (!DrinkNumbers.isValid(drinkNumber)) {
      throw ArgumentError('Invalid drink number: 0x${drinkNumber.toRadixString(16)}');
    }

    return CommandMessage.withByte(CommandCodes.getSalesCount, drinkNumber);
  }

  /// Create a command to set cup drop mode
  static CommandMessage setCupDropModeCommand(int mode) {
    if (mode != CupDropMode.automatic && mode != CupDropMode.manual) {
      throw ArgumentError('Invalid cup drop mode: $mode');
    }

    return CommandMessage.withByte(CommandCodes.setCupDropMode, mode);
  }

  /// Create a command to test cup drop
  static CommandMessage testCupDropCommand() {
    return CommandMessage(command: CommandCodes.testCupDrop);
  }

  /// Create a command for auto inspection
  static CommandMessage autoInspectionCommand() {
    return CommandMessage(command: CommandCodes.autoInspection);
  }

  /// Create a command to clean all pipes
  static CommandMessage cleanAllPipesCommand() {
    return CommandMessage(command: CommandCodes.cleanAllPipes);
  }

  /// Create a command to get machine status
  static CommandMessage getMachineStatusCommand() {
    return CommandMessage(command: CommandCodes.getMachineStatus);
  }

  /// Create a command to get error code
  static CommandMessage getErrorCodeCommand() {
    return CommandMessage(command: CommandCodes.getErrorCode);
  }

  /// Create a command to set drink price
  static CommandMessage setDrinkPriceCommand(int drinkNumber, int price) {
    if (!DrinkNumbers.isValid(drinkNumber)) {
      throw ArgumentError('Invalid drink number: 0x${drinkNumber.toRadixString(16)}');
    }
    if (!PriceLimits.isValid(price)) {
      throw ArgumentError('Invalid price: $price (must be ${PriceLimits.min}-${PriceLimits.max})');
    }

    return CommandMessage(
      command: CommandCodes.setDrinkPrice,
      data: Uint8List.fromList([drinkNumber, price]),
    );
  }

  /// Create a command to get balance
  static CommandMessage getBalanceCommand() {
    return CommandMessage(command: CommandCodes.getBalance);
  }

  /// Create a command to return change
  static CommandMessage returnChangeCommand() {
    return CommandMessage(command: CommandCodes.returnChange);
  }

  /// Create a command to clean specific pipe
  static CommandMessage cleanSpecificPipeCommand(int pipeNumber) {
    if (pipeNumber < 0 || pipeNumber > 255) {
      throw ArgumentError('Invalid pipe number: $pipeNumber');
    }

    return CommandMessage.withByte(CommandCodes.cleanSpecificPipe, pipeNumber);
  }

  /// Create a command to set drink recipe process (0x1D)
  /// [drinkNumber] - Drink number (0x01-0x07 hot, 0x11-0x17 cold)
  /// [steps] - List of recipe steps (max 32)
  static CommandMessage setDrinkRecipeProcessCommand(int drinkNumber, List<RecipeStep> steps) {
    if (!DrinkNumbers.isValid(drinkNumber)) {
      throw ArgumentError('Invalid drink number: 0x${drinkNumber.toRadixString(16)}');
    }
    if (steps.isEmpty || steps.length > 32) {
      throw ArgumentError('Steps must be 1-32, got ${steps.length}');
    }

    final data = <int>[drinkNumber];
    for (final step in steps) {
      data.addAll(step.toBytes());
    }

    return CommandMessage(
      command: CommandCodes.setDrinkRecipeProcess,
      data: Uint8List.fromList(data),
    );
  }

  /// Create a command for unit function test (0x1A)
  ///
  /// [testCmd] - Test command type (01-06)
  /// [data1] - Test-specific parameter 1
  /// [data2] - Test-specific parameter 2
  /// [data3] - Test-specific parameter 3
  static CommandMessage unitFunctionTestCommand(
    int testCmd,
    int data1,
    int data2,
    int data3,
  ) {
    if (testCmd < 0x01 || testCmd > 0x06) {
      throw ArgumentError('Invalid test command: 0x${testCmd.toRadixString(16)} (must be 0x01-0x06)');
    }

    return CommandMessage(
      command: CommandCodes.unitFunctionTest,
      data: Uint8List.fromList([testCmd, data1, data2, data3]),
    );
  }

  /// Create a command for electronic lock control (0x1B)
  ///
  /// [lockNumber] - Lock device number (default 0x01)
  /// [operation] - 0x00=unlock, 0x01=lock, 0x02=query status
  static CommandMessage electronicLockCommand(int lockNumber, int operation) {
    if (operation < 0x00 || operation > 0x02) {
      throw ArgumentError('Invalid lock operation: 0x${operation.toRadixString(16)} (must be 0x00-0x02)');
    }

    return CommandMessage(
      command: CommandCodes.electronicLock,
      data: Uint8List.fromList([lockNumber, operation]),
    );
  }

  /// Create a command for water refill (0x1C)
  ///
  /// Fixed DATA = 0x1D as per protocol specification.
  static CommandMessage waterRefillCommand() {
    return CommandMessage.withByte(CommandCodes.waterRefill, 0x1D);
  }

  /// Create a command for main controller status query (0x1E)
  ///
  /// Fixed DATA = 0x1F as per protocol specification.
  static CommandMessage getControllerStatusCommand() {
    return CommandMessage.withByte(CommandCodes.getControllerStatus, 0x1F);
  }

  /// Create a command for drink preparation status query (0x1F)
  ///
  /// Fixed DATA = 0x20 as per protocol specification.
  static CommandMessage getDrinkStatusCommand() {
    return CommandMessage.withByte(CommandCodes.getDrinkStatus, 0x20);
  }

  /// Create a command for object exception info query (0x22)
  ///
  /// [objectNumber] - Object number (16-bit, 0x0000-0x000B)
  static CommandMessage getObjectExceptionCommand(int objectNumber) {
    if (objectNumber < 0x0000 || objectNumber > 0x000B) {
      throw ArgumentError('Invalid object number: 0x${objectNumber.toRadixString(16)} (must be 0x0000-0x000B)');
    }

    return CommandMessage(
      command: CommandCodes.getObjectException,
      data: Uint8List.fromList([
        0x00,
        (objectNumber >> 8) & 0xFF,
        objectNumber & 0xFF,
      ]),
    );
  }

  /// Create a command for force stop (0x23)
  ///
  /// [targetCommand] - 0x01=stop drink process, 0x24=stop cup delivery
  static CommandMessage forceStopCommand(int targetCommand) {
    if (targetCommand != 0x01 && targetCommand != 0x24) {
      throw ArgumentError('Invalid force stop target: 0x${targetCommand.toRadixString(16)} (must be 0x01 or 0x24)');
    }

    return CommandMessage.withByte(CommandCodes.forceStop, targetCommand);
  }

  /// Create a command for cup delivery (0x24)
  ///
  /// [waitTime] - Wait time in seconds (0x01-0xFF)
  static CommandMessage cupDeliveryCommand(int waitTime) {
    if (waitTime < 0x01 || waitTime > 0xFF) {
      throw ArgumentError('Invalid wait time: $waitTime (must be 1-255)');
    }

    return CommandMessage(
      command: CommandCodes.cupDelivery,
      data: Uint8List.fromList([0x00, waitTime]),
    );
  }

  /// Create a command for immediate single channel execution (0x25)
  /// [channel] - Channel number (0-based)
  /// [waterType] - Hot(0) or Cold(1)
  /// [materialDuration] - Material dispensing time in 0.1s units (0-999)
  /// [waterAmount] - Water amount in 0.1mL units (0-999)
  /// [materialSpeed] - Material speed 0-100%
  /// [mixSpeed] - Mixing speed 0-100%
  /// [subChannel] - Sub channel (-1 to 127)
  /// [subMaterialDuration] - Sub material time (0-999)
  /// [subMaterialSpeed] - Sub material speed 0-100%
  /// [endWaitTime] - End wait time in seconds (0-255)
  /// [removeParamLimits] - If true, removes default parameter range limits
  static CommandMessage executeChannelCommand({
    required int channel,
    int waterType = 0,
    int materialDuration = 0,
    int waterAmount = 0,
    int materialSpeed = 50,
    int mixSpeed = 0,
    int subChannel = -1,
    int subMaterialDuration = 0,
    int subMaterialSpeed = 0,
    int endWaitTime = 0,
    bool removeParamLimits = false,
  }) {
    return CommandMessage(
      command: CommandCodes.executeChannel,
      data: Uint8List.fromList([
        channel & 0xFF,
        waterType & 0xFF,
        (materialDuration >> 8) & 0xFF, materialDuration & 0xFF,
        (waterAmount >> 8) & 0xFF, waterAmount & 0xFF,
        materialSpeed & 0xFF,
        mixSpeed & 0xFF,
        subChannel & 0xFF,
        (subMaterialDuration >> 8) & 0xFF, subMaterialDuration & 0xFF,
        subMaterialSpeed & 0xFF,
        endWaitTime & 0xFF,
        removeParamLimits ? 0x01 : 0x00,
      ]),
    );
  }

  /// Format byte array as hex string for debugging
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// Parse hex string to byte array
  ///
  /// Example: "AA 55 04 01 02 AB" -> [0xAA, 0x55, 0x04, 0x01, 0x02, 0xAB]
  static Uint8List hexToBytes(String hex) {
    // Remove spaces and convert to uppercase
    final cleaned = hex.replaceAll(' ', '').toUpperCase();

    // Check if valid hex string
    if (cleaned.length % 2 != 0) {
      throw ArgumentError('Invalid hex string length');
    }

    final bytes = <int>[];
    for (int i = 0; i < cleaned.length; i += 2) {
      final byteStr = cleaned.substring(i, i + 2);
      final byte = int.tryParse(byteStr, radix: 16);
      if (byte == null) {
        throw ArgumentError('Invalid hex string: $hex');
      }
      bytes.add(byte);
    }

    return Uint8List.fromList(bytes);
  }
}
