/// Drink Information Models
///
/// This file contains models for drink-related data.

import '../protocol/gs805_constants.dart';

/// Drink number enumeration
enum DrinkNumber {
  /// Hot drink 1 (0x01)
  hotDrink1(0x01, 'Hot Drink 1', true),

  /// Hot drink 2 (0x02)
  hotDrink2(0x02, 'Hot Drink 2', true),

  /// Hot drink 3 (0x03)
  hotDrink3(0x03, 'Hot Drink 3', true),

  /// Hot drink 4 (0x04)
  hotDrink4(0x04, 'Hot Drink 4', true),

  /// Hot drink 5 (0x05)
  hotDrink5(0x05, 'Hot Drink 5', true),

  /// Hot drink 6 (0x06)
  hotDrink6(0x06, 'Hot Drink 6', true),

  /// Hot drink 7 (0x07)
  hotDrink7(0x07, 'Hot Drink 7', true),

  /// Cold drink 1 (0x11)
  coldDrink1(0x11, 'Cold Drink 1', false),

  /// Cold drink 2 (0x12)
  coldDrink2(0x12, 'Cold Drink 2', false),

  /// Cold drink 3 (0x13)
  coldDrink3(0x13, 'Cold Drink 3', false),

  /// Cold drink 4 (0x14)
  coldDrink4(0x14, 'Cold Drink 4', false),

  /// Cold drink 5 (0x15)
  coldDrink5(0x15, 'Cold Drink 5', false),

  /// Cold drink 6 (0x16)
  coldDrink6(0x16, 'Cold Drink 6', false),

  /// Cold drink 7 (0x17)
  coldDrink7(0x17, 'Cold Drink 7', false);

  /// Protocol code for this drink
  final int code;

  /// Display name for this drink
  final String displayName;

  /// Whether this is a hot drink
  final bool isHot;

  const DrinkNumber(this.code, this.displayName, this.isHot);

  /// Whether this is a cold drink
  bool get isCold => !isHot;

  /// Get drink number from protocol code
  static DrinkNumber? fromCode(int code) {
    try {
      return DrinkNumber.values.firstWhere((d) => d.code == code);
    } catch (e) {
      return null;
    }
  }

  /// Get all hot drinks
  static List<DrinkNumber> get hotDrinks =>
      DrinkNumber.values.where((d) => d.isHot).toList();

  /// Get all cold drinks
  static List<DrinkNumber> get coldDrinks =>
      DrinkNumber.values.where((d) => d.isCold).toList();

  @override
  String toString() => displayName;
}

/// Drink price information
class DrinkPrice {
  /// Drink number
  final DrinkNumber drink;

  /// Price in token value (0-99)
  final int price;

  /// Create drink price information
  DrinkPrice({
    required this.drink,
    required this.price,
  }) {
    if (!PriceLimits.isValid(price)) {
      throw ArgumentError(
        'Invalid price: $price (must be ${PriceLimits.min}-${PriceLimits.max})',
      );
    }
  }

  /// Create a copy with updated price
  DrinkPrice copyWith({int? price}) {
    return DrinkPrice(
      drink: drink,
      price: price ?? this.price,
    );
  }

  @override
  String toString() => '$drink: $price tokens';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrinkPrice &&
          runtimeType == other.runtimeType &&
          drink == other.drink &&
          price == other.price;

  @override
  int get hashCode => drink.hashCode ^ price.hashCode;
}

/// Drink sales statistics
class DrinkSalesCount {
  /// Drink number
  final DrinkNumber drink;

  /// Total cups sold via local balance transaction
  final int localSalesCount;

  /// Total cups made via direct command
  final int commandSalesCount;

  /// Create drink sales statistics
  DrinkSalesCount({
    required this.drink,
    required this.localSalesCount,
    required this.commandSalesCount,
  }) {
    if (localSalesCount < 0 || localSalesCount > 0xFFFFFFFF) {
      throw ArgumentError('Invalid local sales count: $localSalesCount');
    }
    if (commandSalesCount < 0 || commandSalesCount > 0xFFFFFFFF) {
      throw ArgumentError('Invalid command sales count: $commandSalesCount');
    }
  }

  /// Total cups sold (local + command)
  int get totalCount => localSalesCount + commandSalesCount;

  @override
  String toString() =>
      '$drink: total=$totalCount (local=$localSalesCount, cmd=$commandSalesCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrinkSalesCount &&
          runtimeType == other.runtimeType &&
          drink == other.drink &&
          localSalesCount == other.localSalesCount &&
          commandSalesCount == other.commandSalesCount;

  @override
  int get hashCode =>
      drink.hashCode ^ localSalesCount.hashCode ^ commandSalesCount.hashCode;
}

/// Temperature settings for drinks
class TemperatureSettings {
  /// Upper limit temperature (°C)
  final int upperLimit;

  /// Lower limit temperature (°C)
  final int lowerLimit;

  /// Whether this is for hot drinks
  final bool isHot;

  /// Create temperature settings
  TemperatureSettings({
    required this.upperLimit,
    required this.lowerLimit,
    required this.isHot,
  }) {
    if (isHot) {
      if (!TemperatureLimits.isValidHotTemp(upperLimit, lowerLimit)) {
        throw ArgumentError(
          'Invalid hot temperature range: upper=$upperLimit, lower=$lowerLimit',
        );
      }
    } else {
      if (!TemperatureLimits.isValidColdTemp(upperLimit, lowerLimit)) {
        throw ArgumentError(
          'Invalid cold temperature range: upper=$upperLimit, lower=$lowerLimit',
        );
      }
    }
  }

  /// Create hot drink temperature settings
  factory TemperatureSettings.hot({
    required int upperLimit,
    required int lowerLimit,
  }) {
    return TemperatureSettings(
      upperLimit: upperLimit,
      lowerLimit: lowerLimit,
      isHot: true,
    );
  }

  /// Create cold drink temperature settings
  factory TemperatureSettings.cold({
    required int upperLimit,
    required int lowerLimit,
  }) {
    return TemperatureSettings(
      upperLimit: upperLimit,
      lowerLimit: lowerLimit,
      isHot: false,
    );
  }

  /// Temperature difference between upper and lower limits
  int get temperatureDifference => upperLimit - lowerLimit;

  /// Create a copy with updated values
  TemperatureSettings copyWith({
    int? upperLimit,
    int? lowerLimit,
  }) {
    return TemperatureSettings(
      upperLimit: upperLimit ?? this.upperLimit,
      lowerLimit: lowerLimit ?? this.lowerLimit,
      isHot: isHot,
    );
  }

  @override
  String toString() =>
      '${isHot ? 'Hot' : 'Cold'} temperature: $lowerLimit°C - $upperLimit°C';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemperatureSettings &&
          runtimeType == other.runtimeType &&
          upperLimit == other.upperLimit &&
          lowerLimit == other.lowerLimit &&
          isHot == other.isHot;

  @override
  int get hashCode =>
      upperLimit.hashCode ^ lowerLimit.hashCode ^ isHot.hashCode;
}

/// Cup drop mode
enum CupDropModeEnum {
  /// Machine automatically drops cup (0x00)
  automatic(CupDropMode.automatic, 'Automatic'),

  /// Manual cup placement (0x01)
  manual(CupDropMode.manual, 'Manual');

  /// Protocol code
  final int code;

  /// Display name
  final String displayName;

  const CupDropModeEnum(this.code, this.displayName);

  /// Get cup drop mode from code
  static CupDropModeEnum? fromCode(int code) {
    try {
      return CupDropModeEnum.values.firstWhere((m) => m.code == code);
    } catch (e) {
      return null;
    }
  }

  @override
  String toString() => displayName;
}
