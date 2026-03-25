import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/src/models/drink_info.dart';
import 'package:gs805serial/src/models/machine_status.dart';
import 'package:gs805serial/src/models/error_code.dart';
import 'package:gs805serial/src/protocol/gs805_constants.dart';

void main() {
  group('DrinkNumber', () {
    test('creates hot drinks correctly', () {
      expect(DrinkNumber.hotDrink1.code, equals(0x01));
      expect(DrinkNumber.hotDrink1.isHot, isTrue);
      expect(DrinkNumber.hotDrink1.isCold, isFalse);
    });

    test('creates cold drinks correctly', () {
      expect(DrinkNumber.coldDrink1.code, equals(0x11));
      expect(DrinkNumber.coldDrink1.isHot, isFalse);
      expect(DrinkNumber.coldDrink1.isCold, isTrue);
    });

    test('finds drink by code', () {
      final drink = DrinkNumber.fromCode(0x01);
      expect(drink, equals(DrinkNumber.hotDrink1));

      final coldDrink = DrinkNumber.fromCode(0x11);
      expect(coldDrink, equals(DrinkNumber.coldDrink1));
    });

    test('returns null for invalid code', () {
      final drink = DrinkNumber.fromCode(0xFF);
      expect(drink, isNull);
    });

    test('filters hot drinks', () {
      final hotDrinks = DrinkNumber.hotDrinks;
      expect(hotDrinks.length, equals(7));
      expect(hotDrinks.every((d) => d.isHot), isTrue);
    });

    test('filters cold drinks', () {
      final coldDrinks = DrinkNumber.coldDrinks;
      expect(coldDrinks.length, equals(7));
      expect(coldDrinks.every((d) => d.isCold), isTrue);
    });
  });

  group('DrinkPrice', () {
    test('creates valid price', () {
      final price = DrinkPrice(
        drink: DrinkNumber.hotDrink1,
        price: 50,
      );
      expect(price.drink, equals(DrinkNumber.hotDrink1));
      expect(price.price, equals(50));
    });

    test('rejects invalid price', () {
      expect(
        () => DrinkPrice(drink: DrinkNumber.hotDrink1, price: 100),
        throwsArgumentError,
      );
      expect(
        () => DrinkPrice(drink: DrinkNumber.hotDrink1, price: -1),
        throwsArgumentError,
      );
    });

    test('copies with new price', () {
      final price = DrinkPrice(drink: DrinkNumber.hotDrink1, price: 50);
      final updated = price.copyWith(price: 60);
      expect(updated.price, equals(60));
      expect(updated.drink, equals(DrinkNumber.hotDrink1));
    });
  });

  group('DrinkSalesCount', () {
    test('creates sales count', () {
      final sales = DrinkSalesCount(
        drink: DrinkNumber.hotDrink1,
        localSalesCount: 100,
        commandSalesCount: 50,
      );
      expect(sales.totalCount, equals(150));
    });

    test('validates counts', () {
      expect(
        () => DrinkSalesCount(
          drink: DrinkNumber.hotDrink1,
          localSalesCount: -1,
          commandSalesCount: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TemperatureSettings', () {
    test('creates hot temperature settings', () {
      final temp = TemperatureSettings.hot(
        upperLimit: 85,
        lowerLimit: 75,
      );
      expect(temp.isHot, isTrue);
      expect(temp.upperLimit, equals(85));
      expect(temp.lowerLimit, equals(75));
      expect(temp.temperatureDifference, equals(10));
    });

    test('creates cold temperature settings', () {
      final temp = TemperatureSettings.cold(
        upperLimit: 10,
        lowerLimit: 5,
      );
      expect(temp.isHot, isFalse);
      expect(temp.upperLimit, equals(10));
      expect(temp.lowerLimit, equals(5));
    });

    test('validates hot temperature range', () {
      expect(
        () => TemperatureSettings.hot(upperLimit: 70, lowerLimit: 80),
        throwsArgumentError, // Upper < Lower
      );

      expect(
        () => TemperatureSettings.hot(upperLimit: 50, lowerLimit: 45),
        throwsArgumentError, // Out of valid range
      );
    });

    test('validates cold temperature range', () {
      expect(
        () => TemperatureSettings.cold(upperLimit: 50, lowerLimit: 10),
        throwsArgumentError, // Out of valid range
      );
    });
  });

  group('MachineStatus', () {
    test('creates status from code', () {
      final status = MachineStatus.fromCode(StatusCodes.success);
      expect(status, equals(MachineStatus.ready));
      expect(status.isReady, isTrue);
      expect(status.isError, isFalse);
    });

    test('identifies error status', () {
      final status = MachineStatus.fromCode(StatusCodes.error);
      expect(status, equals(MachineStatus.error));
      expect(status.isReady, isFalse);
      expect(status.isError, isTrue);
    });

    test('handles unknown status', () {
      final status = MachineStatus.fromCode(0xAB);
      expect(status, equals(MachineStatus.unknown));
    });
  });

  group('MachineBalance', () {
    test('creates valid balance', () {
      final balance = MachineBalance(balance: 50);
      expect(balance.balance, equals(50));
      expect(balance.isEmpty, isFalse);
      expect(balance.isFull, isFalse);
    });

    test('checks if balance is sufficient', () {
      final balance = MachineBalance(balance: 50);
      expect(balance.isSufficient(30), isTrue);
      expect(balance.isSufficient(60), isFalse);
    });

    test('identifies empty balance', () {
      final balance = MachineBalance(balance: 0);
      expect(balance.isEmpty, isTrue);
    });

    test('identifies full balance', () {
      final balance = MachineBalance(balance: 99);
      expect(balance.isFull, isTrue);
    });

    test('validates balance range', () {
      expect(
        () => MachineBalance(balance: 100),
        throwsArgumentError,
      );
      expect(
        () => MachineBalance(balance: -1),
        throwsArgumentError,
      );
    });
  });

  group('MachineError', () {
    test('parses no water error', () {
      final error = MachineError(errorCode: ErrorCodeBits.noWater);
      expect(error.hasNoWater, isTrue);
      expect(error.hasNoCup, isFalse);
      expect(error.hasErrors, isTrue);
      expect(error.preventsDrinkMaking, isTrue);
    });

    test('parses no cup error', () {
      final error = MachineError(errorCode: ErrorCodeBits.noCup);
      expect(error.hasNoCup, isTrue);
      expect(error.hasNoWater, isFalse);
      expect(error.preventsDrinkMaking, isTrue);
    });

    test('parses multiple errors', () {
      final errorCode = ErrorCodeBits.noWater | ErrorCodeBits.noCup;
      final error = MachineError(errorCode: errorCode);
      expect(error.hasNoWater, isTrue);
      expect(error.hasNoCup, isTrue);
      expect(error.activeErrors.length, equals(2));
    });

    test('handles first heating flag', () {
      final error = MachineError(errorCode: ErrorCodeBits.firstHeating);
      expect(error.isFirstHeating, isTrue);
      expect(error.hasErrors, isFalse); // First heating is not an error
      expect(error.preventsDrinkMaking, isFalse);
    });

    test('handles no errors', () {
      final error = MachineError(errorCode: 0);
      expect(error.hasErrors, isFalse);
      expect(error.activeErrors, isEmpty);
    });
  });

  group('MachineEventType', () {
    test('identifies cup drop success', () {
      final event =
          MachineEventType.fromCode(ActiveReportCodes.cupDropSuccess);
      expect(event, equals(MachineEventType.cupDropSuccess));
    });

    test('identifies drink complete', () {
      final event = MachineEventType.fromCode(ActiveReportCodes.drinkComplete);
      expect(event, equals(MachineEventType.drinkComplete));
    });

    test('handles unknown event', () {
      final event = MachineEventType.fromCode(0xFF);
      expect(event, equals(MachineEventType.unknown));
    });
  });

  group('MachineEvent', () {
    test('creates success event', () {
      final event = MachineEvent.fromCode(ActiveReportCodes.cupDropSuccess);
      expect(event.type, equals(MachineEventType.cupDropSuccess));
      expect(event.isSuccess, isTrue);
      expect(event.isError, isFalse);
    });

    test('creates error event', () {
      final event = MachineEvent.fromCode(ActiveReportCodes.trackObstacle);
      expect(event.type, equals(MachineEventType.trackObstacle));
      expect(event.isSuccess, isFalse);
      expect(event.isError, isTrue);
    });

    test('stores additional data', () {
      final event = MachineEvent.fromCode(
        ActiveReportCodes.drinkComplete,
        additionalData: [0x01, 0x02, 0x03],
      );
      expect(event.additionalData, equals([0x01, 0x02, 0x03]));
    });
  });

  group('ErrorInfo', () {
    test('provides recovery actions for no water', () {
      final error = MachineError(errorCode: ErrorCodeBits.noWater);
      final info = ErrorInfo.fromError(error);
      expect(info.requiresUserIntervention, isTrue);
      expect(info.severity, equals(ErrorSeverity.error));
      expect(info.recoveryActions, contains('Refill water tank'));
    });

    test('provides recovery actions for multiple errors', () {
      final error = MachineError(
        errorCode: ErrorCodeBits.noWater | ErrorCodeBits.noCup,
      );
      final info = ErrorInfo.fromError(error);
      expect(info.recoveryActions.length, greaterThan(1));
      expect(info.recoveryActions, contains('Refill water tank'));
      expect(info.recoveryActions, contains('Refill cup dispenser'));
    });

    test('handles first heating as info', () {
      final error = MachineError(errorCode: ErrorCodeBits.firstHeating);
      final info = ErrorInfo.fromError(error);
      expect(info.severity, equals(ErrorSeverity.info));
      expect(info.requiresUserIntervention, isFalse);
    });
  });

  group('ChangerStatus', () {
    test('parses dispensing status', () {
      final status = ChangerStatus.fromByte(0x10);
      expect(status.isDispensing, isTrue);
      expect(status.hasFaults, isFalse);
    });

    test('parses fault status', () {
      final status = ChangerStatus.fromByte(0x01); // Motor fault
      expect(status.hasMotorFault, isTrue);
      expect(status.hasFaults, isTrue);
      expect(status.activeFaults, contains('Motor fault'));
    });

    test('parses multiple faults', () {
      final status = ChangerStatus.fromByte(0x03); // Motor + coin faults
      expect(status.hasMotorFault, isTrue);
      expect(status.hasInsufficientCoins, isTrue);
      expect(status.activeFaults.length, equals(2));
    });
  });
}
