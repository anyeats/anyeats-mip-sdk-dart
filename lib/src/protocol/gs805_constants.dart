/// GS805 Serial Communication Protocol Constants
///
/// This file contains all protocol-level constants for GS805 coffee machine
/// serial communication based on the official protocol documentation.

/// Protocol header flags
class ProtocolFlags {
  /// Command message header (from host to machine)
  /// Value: 0xAA55
  static const int commandHeader = 0xAA55;

  /// Response message header (from machine to host)
  /// Value: 0xA55A
  static const int responseHeader = 0xA55A;

  /// Minimum message length (LEN field minimum)
  static const int minMessageLength = 2;

  /// Maximum message length (LEN field maximum)
  static const int maxMessageLength = 255;
}

/// Protocol command codes (COMND field)
class CommandCodes {
  /// 0x01: Make a specified drink
  static const int makeDrink = 0x01;

  /// 0x04: Set hot drink temperature threshold
  static const int setHotTemperature = 0x04;

  /// 0x05: Set cold drink temperature threshold
  static const int setColdTemperature = 0x05;

  /// 0x06: Read sales count for specified drink
  static const int getSalesCount = 0x06;

  /// 0x07: Set cup drop mode
  static const int setCupDropMode = 0x07;

  /// 0x08: Test cup drop function
  static const int testCupDrop = 0x08;

  /// 0x09: Automatic full inspection
  static const int autoInspection = 0x09;

  /// 0x0A: Clean all instant coffee pipes
  static const int cleanAllPipes = 0x0A;

  /// 0x0B: Query machine status
  static const int getMachineStatus = 0x0B;

  /// 0x0C: Query error code
  static const int getErrorCode = 0x0C;

  /// 0x0E: Set local drink price
  static const int setDrinkPrice = 0x0E;

  /// 0x0F: Query machine balance
  static const int getBalance = 0x0F;

  /// 0x10: Return change operation
  static const int returnChange = 0x10;

  /// 0x12: Clean specified instant formula pipeline
  static const int cleanSpecificPipe = 0x12;

  /// 0x15: Set drink recipe water/material time (Series 2,3,R)
  static const int setDrinkRecipeTime = 0x15;

  /// 0x1A: Unit function test (3,R series)
  static const int unitFunctionTest = 0x1A;

  /// 0x1B: Electronic lock control (3,R series)
  static const int electronicLock = 0x1B;

  /// 0x1C: Water refill (R series)
  static const int waterRefill = 0x1C;

  /// 0x1D: Set drink recipe process configuration (R series)
  static const int setDrinkRecipeProcess = 0x1D;

  /// 0x1E: Main controller status query (R series)
  static const int getControllerStatus = 0x1E;

  /// 0x1F: Drink preparation status query (R series)
  static const int getDrinkStatus = 0x1F;

  /// 0x22: Object exception info query (R series)
  static const int getObjectException = 0x22;

  /// 0x23: Force stop (R series)
  static const int forceStop = 0x23;

  /// 0x24: Cup delivery (R series)
  static const int cupDelivery = 0x24;

  /// 0x25: Immediate single channel execution (R series)
  static const int executeChannel = 0x25;
}

/// Response status codes (STA field)
class StatusCodes {
  /// 0x00: Device normal/Operation successful
  /// Control board accepts and executes the command
  static const int success = 0x00;

  /// 0x01: Device busy, cannot execute command
  static const int busy = 0x01;

  /// 0x02: Device error/Execution failed
  /// Cannot execute command
  static const int error = 0x02;

  /// 0x03: Parameter error
  /// Cannot execute command
  static const int parameterError = 0x03;

  /// 0x04: Insufficient balance
  /// Cannot execute command
  static const int insufficientBalance = 0x04;

  /// 0x05: Configuration parameters restrict command function
  /// Cannot execute command
  static const int configRestricted = 0x05;

  /// 0x06: Required data/recipe does not exist or is invalid
  /// Cannot execute command
  static const int dataNotFound = 0x06;

  /// 0x07: Execution conditions not met
  /// (e.g., ice machine offline when requesting iced drink)
  static const int conditionsNotMet = 0x07;

  /// 0x08: Specified device/component/function does not exist
  /// Cannot execute command
  static const int deviceNotFound = 0x08;

  /// 0x7F: Control board actively reporting data
  static const int activeReport = 0x7F;

  /// Get human-readable status message
  static String getMessage(int code) {
    switch (code) {
      case success:
        return 'Success';
      case busy:
        return 'Device busy';
      case error:
        return 'Device error or execution failed';
      case parameterError:
        return 'Parameter error';
      case insufficientBalance:
        return 'Insufficient balance';
      case configRestricted:
        return 'Configuration restricted';
      case dataNotFound:
        return 'Data or recipe not found';
      case conditionsNotMet:
        return 'Execution conditions not met';
      case deviceNotFound:
        return 'Device or function not found';
      case activeReport:
        return 'Active report from control board';
      default:
        return 'Unknown status code: 0x${code.toRadixString(16)}';
    }
  }

  /// Check if status code indicates success
  static bool isSuccess(int code) => code == success;

  /// Check if status code indicates error
  /// 0x00=success, 0x01=busy, 0x02-0x08=error, 0x09-0x7E=status, 0x7F=activeReport
  static bool isError(int code) => code >= 0x02 && code <= 0x08;
}

/// Drink number definitions
class DrinkNumbers {
  /// Hot drinks: 0x01 - 0x07
  static const int hotDrink1 = 0x01;
  static const int hotDrink2 = 0x02;
  static const int hotDrink3 = 0x03;
  static const int hotDrink4 = 0x04;
  static const int hotDrink5 = 0x05;
  static const int hotDrink6 = 0x06;
  static const int hotDrink7 = 0x07;

  /// Cold drinks: 0x11 - 0x17
  static const int coldDrink1 = 0x11;
  static const int coldDrink2 = 0x12;
  static const int coldDrink3 = 0x13;
  static const int coldDrink4 = 0x14;
  static const int coldDrink5 = 0x15;
  static const int coldDrink6 = 0x16;
  static const int coldDrink7 = 0x17;

  /// Check if drink number is valid
  static bool isValid(int drinkNo) {
    return (drinkNo >= hotDrink1 && drinkNo <= hotDrink7) ||
        (drinkNo >= coldDrink1 && drinkNo <= coldDrink7);
  }

  /// Check if drink is hot
  static bool isHot(int drinkNo) {
    return drinkNo >= hotDrink1 && drinkNo <= hotDrink7;
  }

  /// Check if drink is cold
  static bool isCold(int drinkNo) {
    return drinkNo >= coldDrink1 && drinkNo <= coldDrink7;
  }
}

/// Make drink command parameters
class MakeDrinkParams {
  /// 0x01: Purchase drink using local balance (requires transaction function)
  static const int useLocalBalance = 0x01;

  /// 0x02: Direct drink making command
  static const int directCommand = 0x02;
}

/// Cup drop mode parameters
class CupDropMode {
  /// 0x00: Machine automatically drops cup
  static const int automatic = 0x00;

  /// 0x01: Manual cup placement
  static const int manual = 0x01;
}

/// Error code bit flags (from 0x0C command response)
class ErrorCodeBits {
  /// Bit 7: First heating after device power on
  static const int firstHeating = 0x80;

  /// Bit 6: No lid
  static const int noLid = 0x40;

  /// Bit 5: Reserved
  static const int reserved5 = 0x20;

  /// Bit 4: Track fault
  static const int trackFault = 0x10;

  /// Bit 3: Sensor fault (hot water tank NTC or others)
  static const int sensorFault = 0x08;

  /// Bit 2: No water and no cup
  static const int noWaterNoCup = 0x04;

  /// Bit 1: No cup
  static const int noCup = 0x02;

  /// Bit 0: No water
  static const int noWater = 0x01;

  /// Get list of active errors from error code byte
  static List<String> getActiveErrors(int errorCode) {
    final errors = <String>[];

    if (errorCode & firstHeating != 0) {
      errors.add('First heating after power on');
    }
    if (errorCode & noLid != 0) {
      errors.add('No lid');
    }
    if (errorCode & trackFault != 0) {
      errors.add('Track fault');
    }
    if (errorCode & sensorFault != 0) {
      errors.add('Sensor fault');
    }
    if (errorCode & noWaterNoCup != 0) {
      errors.add('No water and no cup');
    }
    if (errorCode & noCup != 0) {
      errors.add('No cup');
    }
    if (errorCode & noWater != 0) {
      errors.add('No water');
    }

    return errors;
  }
}

/// Active report event codes (ErrorCode field in active reports)
class ActiveReportCodes {
  /// 0x05: Cup drop successful
  static const int cupDropSuccess = 0x05;

  /// 0x10: Drink making complete
  static const int drinkComplete = 0x10;

  /// 0x06: Ice drop complete (JK86 series only)
  static const int iceDropComplete = 0x06;

  /// 0x20: Foreign object on track / Capping failed / Front door module offline
  /// (JK82 model only)
  static const int trackObstacle = 0x20;
}

/// Communication protocol configuration
class ProtocolConfig {
  /// Serial port baud rate
  static const int baudRate = 9600;

  /// Data bits
  static const int dataBits = 8;

  /// Stop bits
  static const int stopBits = 1;

  /// Parity: none
  static const int parity = 0; // 0 = none, 1 = odd, 2 = even

  /// Response timeout in milliseconds
  static const int responseTimeout = 100;

  /// Maximum retry count for command retransmission
  static const int maxRetries = 2;

  /// Byte order: Big Endian
  static const bool bigEndian = true;
}

/// Temperature limits
class TemperatureLimits {
  /// Hot drink temperature upper limit (°C)
  static const int hotTempMax = 99;

  /// Hot drink temperature lower limit (°C)
  static const int hotTempMin = 60;

  /// Cold drink temperature upper limit (°C)
  static const int coldTempMax = 40;

  /// Cold drink temperature lower limit (°C)
  static const int coldTempMin = 2;

  /// Minimum temperature difference for hot drinks (°C)
  static const int hotTempDiff = 5;

  /// Validate hot temperature range
  static bool isValidHotTemp(int high, int low) {
    return high >= hotTempMin &&
        high <= hotTempMax &&
        low >= hotTempMin &&
        low <= hotTempMax &&
        high >= low + hotTempDiff;
  }

  /// Validate cold temperature range
  static bool isValidColdTemp(int high, int low) {
    return high >= coldTempMin &&
        high <= coldTempMax &&
        low >= coldTempMin &&
        low <= coldTempMax &&
        high >= low;
  }
}

/// Price limits (in token value)
class PriceLimits {
  /// Minimum price
  static const int min = 0;

  /// Maximum price
  static const int max = 99;

  /// Maximum balance
  static const int maxBalance = 99;

  /// Validate price value
  static bool isValid(int price) => price >= min && price <= max;
}
