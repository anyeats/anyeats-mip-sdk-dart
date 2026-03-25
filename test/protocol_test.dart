import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/src/protocol/gs805_constants.dart';
import 'package:gs805serial/src/protocol/gs805_message.dart';
import 'package:gs805serial/src/protocol/gs805_protocol.dart';

void main() {
  group('GS805Protocol - Checksum', () {
    test('calculates checksum correctly', () {
      final bytes = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B]);
      final checksum = GS805Protocol.calculateChecksum(bytes);
      // 0xAA + 0x55 + 0x02 + 0x0B = 0x10C -> 0x0C
      expect(checksum, equals(0x0C));
    });

    test('verifies valid checksum', () {
      // AA 55 02 0B 0C (query machine status command)
      final message = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B, 0x0C]);
      expect(GS805Protocol.verifyChecksum(message), isTrue);
    });

    test('rejects invalid checksum', () {
      // AA 55 02 0B 0D (wrong checksum)
      final message = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B, 0x0D]);
      expect(GS805Protocol.verifyChecksum(message), isFalse);
    });
  });

  group('GS805Protocol - Big Endian Conversion', () {
    test('converts int16 to big endian', () {
      final bytes = GS805Protocol.int16ToBigEndian(0x1234);
      expect(bytes, equals([0x12, 0x34]));
    });

    test('converts big endian to int16', () {
      final bytes = Uint8List.fromList([0x12, 0x34]);
      final value = GS805Protocol.bigEndianToInt16(bytes);
      expect(value, equals(0x1234));
    });

    test('converts int32 to big endian', () {
      final bytes = GS805Protocol.int32ToBigEndian(0x12345678);
      expect(bytes, equals([0x12, 0x34, 0x56, 0x78]));
    });

    test('converts big endian to int32', () {
      final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      final value = GS805Protocol.bigEndianToInt32(bytes);
      expect(value, equals(0x12345678));
    });
  });

  group('GS805Protocol - Message Detection', () {
    test('finds command message start', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0xAA, 0x55, 0x02, 0x0B]);
      final offset = GS805Protocol.findMessageStart(bytes);
      expect(offset, equals(2));
    });

    test('finds response message start', () {
      final bytes = Uint8List.fromList([0x00, 0xA5, 0x5A, 0x03, 0x0B]);
      final offset = GS805Protocol.findMessageStart(bytes, isResponse: true);
      expect(offset, equals(1));
    });

    test('returns -1 when no message found', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final offset = GS805Protocol.findMessageStart(bytes);
      expect(offset, equals(-1));
    });

    test('extracts complete message', () {
      // AA 55 02 0B 0C (complete message)
      final bytes = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B, 0x0C]);
      final result = GS805Protocol.extractMessage(bytes);
      expect(result.message, isNotNull);
      expect(result.consumed, equals(5));
      expect(result.message, equals(bytes));
    });

    test('handles incomplete message', () {
      // AA 55 02 0B (missing checksum)
      final bytes = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B]);
      final result = GS805Protocol.extractMessage(bytes);
      expect(result.message, isNull);
      expect(result.consumed, equals(0)); // Don't consume incomplete message
    });
  });

  group('GS805Protocol - Hex Utilities', () {
    test('converts bytes to hex string', () {
      final bytes = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B]);
      final hex = GS805Protocol.bytesToHex(bytes);
      expect(hex, equals('aa 55 02 0b'));
    });

    test('parses hex string to bytes', () {
      final bytes = GS805Protocol.hexToBytes('AA 55 02 0B');
      expect(bytes, equals([0xAA, 0x55, 0x02, 0x0B]));
    });

    test('parses hex string without spaces', () {
      final bytes = GS805Protocol.hexToBytes('AA55020B');
      expect(bytes, equals([0xAA, 0x55, 0x02, 0x0B]));
    });
  });

  group('CommandMessage', () {
    test('creates simple command message', () {
      final cmd = CommandMessage(command: CommandCodes.getMachineStatus);
      final bytes = cmd.toBytes();

      // Expected: AA 55 02 0B 0C
      expect(bytes.length, equals(5));
      expect(bytes[0], equals(0xAA)); // FLAG1 high
      expect(bytes[1], equals(0x55)); // FLAG1 low
      expect(bytes[2], equals(0x02)); // LEN
      expect(bytes[3], equals(0x0B)); // COMND
      expect(bytes[4], equals(0x0C)); // SUM
    });

    test('creates command with single byte parameter', () {
      final cmd = CommandMessage.withByte(CommandCodes.getSalesCount, 0x01);
      final bytes = cmd.toBytes();

      // Expected: AA 55 03 06 01 SUM
      expect(bytes.length, equals(6));
      expect(bytes[2], equals(0x03)); // LEN
      expect(bytes[3], equals(0x06)); // COMND
      expect(bytes[4], equals(0x01)); // DATA
    });

    test('creates command with multiple parameters', () {
      final cmd = CommandMessage.withBytes(
        CommandCodes.setHotTemperature,
        [85, 75],
      );
      final bytes = cmd.toBytes();

      // Expected: AA 55 04 04 55 4B SUM
      expect(bytes.length, equals(7));
      expect(bytes[2], equals(0x04)); // LEN
      expect(bytes[3], equals(0x04)); // COMND
      expect(bytes[4], equals(85)); // High temp
      expect(bytes[5], equals(75)); // Low temp
    });

    test('validates message length', () {
      expect(
        () => CommandMessage(
          command: 0x01,
          data: Uint8List(256), // Too large
        ),
        throwsArgumentError,
      );
    });
  });

  group('ResponseMessage', () {
    test('parses success response', () {
      // A5 5A 03 0B 00 0D (status query success response)
      final bytes = Uint8List.fromList([0xA5, 0x5A, 0x03, 0x0B, 0x00, 0x0D]);
      final response = ResponseMessage.fromBytes(bytes);

      expect(response, isNotNull);
      expect(response!.command, equals(0x0B));
      expect(response.statusCode, equals(0x00));
      expect(response.isSuccess, isTrue);
      expect(response.isError, isFalse);
    });

    test('parses error response', () {
      // A5 5A 03 01 02 05 (make drink failed - device error)
      final bytes = Uint8List.fromList([0xA5, 0x5A, 0x03, 0x01, 0x02, 0x05]);
      final response = ResponseMessage.fromBytes(bytes);

      expect(response, isNotNull);
      expect(response!.command, equals(0x01));
      expect(response.statusCode, equals(0x02));
      expect(response.isSuccess, isFalse);
      expect(response.isError, isTrue);
      expect(response.statusMessage, contains('error'));
    });

    test('parses response with data', () {
      // A5 5A 0B 06 00 01 00 00 00 0A 00 00 00 05 SUM
      // (sales count response: local=10, cmd=5)
      final response = ResponseMessage(
        command: 0x06,
        data: Uint8List.fromList([
          0x00, // STA
          0x01, // DrinkNo
          0x00, 0x00, 0x00, 0x0A, // Local_NUM = 10
          0x00, 0x00, 0x00, 0x05, // Cmd_NUM = 5
        ]),
      );

      expect(response.statusCode, equals(0x00));
      expect(response.getDataByte(0), equals(0x01)); // DrinkNo
      expect(response.getDataDWord(1), equals(10)); // Local_NUM
      expect(response.getDataDWord(5), equals(5)); // Cmd_NUM
    });

    test('rejects invalid header', () {
      // Wrong header: AA 55 instead of A5 5A
      final bytes = Uint8List.fromList([0xAA, 0x55, 0x03, 0x0B, 0x00, 0x13]);
      final response = ResponseMessage.fromBytes(bytes);

      expect(response, isNull);
    });

    test('rejects invalid checksum', () {
      // A5 5A 03 0B 00 14 (wrong checksum)
      final bytes = Uint8List.fromList([0xA5, 0x5A, 0x03, 0x0B, 0x00, 0x14]);
      final response = ResponseMessage.fromBytes(bytes);

      expect(response, isNull);
    });

    test('handles incomplete message', () {
      // Incomplete: A5 5A 03 0B
      final bytes = Uint8List.fromList([0xA5, 0x5A, 0x03, 0x0B]);
      final response = ResponseMessage.fromBytes(bytes);

      expect(response, isNull);
    });
  });

  group('GS805Protocol - Command Builders', () {
    test('builds make drink command', () {
      final cmd = GS805Protocol.makeDrinkCommand(0x01);
      final bytes = cmd.toBytes();

      expect(bytes[3], equals(0x01)); // COMND = makeDrink
      expect(bytes[4], equals(0x01)); // DrinkNo = hot drink 1
      expect(bytes[5], equals(0x02)); // DirectCommand
    });

    test('builds make drink with balance command', () {
      final cmd =
          GS805Protocol.makeDrinkCommand(0x11, useLocalBalance: true);
      final bytes = cmd.toBytes();

      expect(bytes[4], equals(0x11)); // DrinkNo = cold drink 1
      expect(bytes[5], equals(0x01)); // UseLocalBalance
    });

    test('builds set temperature command', () {
      final cmd = GS805Protocol.setHotTemperatureCommand(85, 75);
      final bytes = cmd.toBytes();

      expect(bytes[3], equals(0x04)); // COMND = setHotTemperature
      expect(bytes[4], equals(85)); // High temp
      expect(bytes[5], equals(75)); // Low temp
    });

    test('validates temperature range', () {
      expect(
        () => GS805Protocol.setHotTemperatureCommand(50, 60),
        throwsArgumentError, // Low > High
      );

      expect(
        () => GS805Protocol.setColdTemperatureCommand(50, 10),
        throwsArgumentError, // Out of range
      );
    });

    test('builds status query commands', () {
      final statusCmd = GS805Protocol.getMachineStatusCommand();
      expect(statusCmd.command, equals(CommandCodes.getMachineStatus));

      final errorCmd = GS805Protocol.getErrorCodeCommand();
      expect(errorCmd.command, equals(CommandCodes.getErrorCode));

      final balanceCmd = GS805Protocol.getBalanceCommand();
      expect(balanceCmd.command, equals(CommandCodes.getBalance));
    });

    test('builds control commands', () {
      final cupDropCmd =
          GS805Protocol.setCupDropModeCommand(CupDropMode.automatic);
      expect(cupDropCmd.command, equals(CommandCodes.setCupDropMode));

      final testCmd = GS805Protocol.testCupDropCommand();
      expect(testCmd.command, equals(CommandCodes.testCupDrop));

      final cleanCmd = GS805Protocol.cleanAllPipesCommand();
      expect(cleanCmd.command, equals(CommandCodes.cleanAllPipes));
    });
  });
}
