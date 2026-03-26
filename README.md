# GS805 Serial Communication Plugin

A Flutter plugin for communicating with GS805 coffee machines via serial communication (RS232).

[![pub package](https://img.shields.io/badge/pub-v0.0.1-blue)](https://pub.dev/packages/gs805serial)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Features

- 🔌 **Easy Connection Management** - Simple API for connecting to GS805 devices via USB Serial
- ☕ **Complete Machine Control** - Make drinks, adjust temperature, manage prices, and more
- 📊 **Real-time Status Monitoring** - Get machine status, balance, and error information
- 🔄 **Automatic Reconnection** - Built-in reconnection with multiple strategies (exponential backoff, fixed interval, etc.)
- 📡 **Event Streaming** - Listen to machine events (cup drop, drink complete, errors)
- 🛠️ **Maintenance Functions** - Clean pipes, test mechanisms, run inspections
- 🧪 **Well Tested** - 97+ unit tests covering protocol, models, and serial communication

## Supported Platforms

- ✅ Android
- ⚠️ iOS (limited - USB Serial restrictions)

## Requirements

- Flutter SDK: >=3.0.0
- Dart SDK: >=3.0.0
- Android: API 19+ (Android 4.4+)

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  gs805serial: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### Android Setup

Add USB permissions to your `AndroidManifest.xml`:

```xml
<manifest>
  <uses-feature android:name="android.hardware.usb.host" />

  <application>
    <!-- Add inside <activity> tag -->
    <intent-filter>
      <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
    </intent-filter>

    <meta-data
      android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
      android:resource="@xml/device_filter" />
  </application>
</manifest>
```

Create `android/app/src/main/res/xml/device_filter.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <!-- Add your USB device VID/PID here -->
  <usb-device vendor-id="1234" product-id="5678" />
</resources>
```

For detailed setup instructions, see [SERIAL_SETUP.md](SERIAL_SETUP.md).

## Quick Start

```dart
import 'package:gs805serial/gs805serial.dart';

void main() async {
  // Create instance with automatic reconnection
  final gs805 = GS805Serial(
    reconnectConfig: ReconnectConfig.exponentialBackoff,
  );

  // List available devices
  final devices = await gs805.listDevices();
  print('Found ${devices.length} devices');

  // Connect to first device
  await gs805.connect(devices.first);

  // Check machine status
  final status = await gs805.getMachineStatus();
  print('Status: ${status.description}');

  // Make a hot drink
  await gs805.makeDrink(DrinkNumber.hotDrink1);

  // Listen to events
  gs805.eventStream.listen((event) {
    print('Machine event: ${event.type.description}');
  });

  // Disconnect when done
  await gs805.disconnect();
  await gs805.dispose();
}
```

## Usage Examples

### Connection Management

```dart
final gs805 = GS805Serial();

// List all devices
final devices = await gs805.listDevices();

// Connect to specific device
await gs805.connect(devices.first);

// Or connect by VID/PID
await gs805.connectByVidPid(0x1234, 0x5678);

// Check connection status
if (gs805.isConnected) {
  print('Connected to: ${gs805.connectedDevice?.name}');
}

// Disconnect
await gs805.disconnect();
```

### Making Drinks

```dart
// Make drinks
await gs805.makeDrink(DrinkNumber.hotDrink1);  // Hot drink 1
await gs805.makeDrink(DrinkNumber.coldDrink3); // Cold drink 3

// Use local balance (if available)
await gs805.makeDrink(
  DrinkNumber.hotDrink2,
  useLocalBalance: true,
);

// Available drinks
DrinkNumber.hotDrinks;  // [hotDrink1, hotDrink2, ..., hotDrink7]
DrinkNumber.coldDrinks; // [coldDrink1, coldDrink2, ..., coldDrink7]
```

### Temperature Control

```dart
// Set hot drink temperature (60-99°C)
await gs805.setHotTemperature(
  upperLimit: 85,
  lowerLimit: 75,
);

// Set cold drink temperature (2-40°C)
await gs805.setColdTemperature(
  upperLimit: 10,
  lowerLimit: 5,
);
```

### Status & Information

```dart
// Get machine status
final status = await gs805.getMachineStatus();
print('Status: ${status.description}');
// Status can be: ready, busy, soldOut, cupOut, errorOccurred, etc.

// Get balance
final balance = await gs805.getBalance();
print('Balance: ${balance.balance} tokens');

// Get sales count for a drink
final sales = await gs805.getSalesCount(DrinkNumber.hotDrink1);
print('Local sales: ${sales.localSalesCount}');
print('Command sales: ${sales.commandSalesCount}');

// Get error code
final error = await gs805.getErrorCode();
if (error.hasError) {
  print('Error bits: ${error.errorBits}');
}

// Get detailed error info with recovery suggestions
final errorInfo = await gs805.getErrorInfo();
if (errorInfo.error.hasError) {
  print('Severity: ${errorInfo.severity}');
  print('Recovery actions:');
  for (var action in errorInfo.recoveryActions) {
    print('  - $action');
  }
}
```

### MDB Card Payment

SDK includes `MdbCashless` class for controlling MDB cashless card readers via MDB-RS232 bridge.
Uses a **separate serial port** from the GS805 machine.

```dart
// MDB 카드리더 인스턴스 (GS805Serial과 별도)
final mdb = MdbCashless();

// 1. MDB 브릿지 연결
final mdbDevices = await mdb.listDevices();
await mdb.connect(mdbDevices.first);

// 2. 초기 설정 (앱 시작 시 1회)
await mdb.setup(maxPrice: 0xFFFF, minPrice: 0x0000);
await mdb.enable();

// 3. 결제 이벤트 수신
mdb.eventStream.listen((event) {
  switch (event.type) {
    case CashlessEventType.cardDetected:
      mdb.requestVend(price: 1000, itemNumber: 1);
      break;
    case CashlessEventType.vendApproved:
      gs805.makeDrink(DrinkNumber.hotDrink1);  // 음료 제조
      mdb.vendSuccess(itemNumber: 1);
      mdb.sessionComplete();
      break;
    case CashlessEventType.vendDenied:
      mdb.sessionComplete();
      break;
    default:
      break;
  }
});
```

#### MDB API Summary

| Method | Description |
|---|---|
| `listDevices()` | List MDB bridge devices |
| `connect(device)` | Connect to MDB-RS232 bridge |
| `disconnect()` | Disconnect |
| `setup({maxPrice, minPrice})` | Initialize card reader |
| `enable()` / `disable()` | Enable/disable card reader |
| `requestVend({price, itemNumber})` | Request payment |
| `vendSuccess({itemNumber})` | Confirm dispensing success |
| `vendCancel()` | Cancel vend |
| `cashSale({price, itemNumber})` | Report cash sale |
| `sessionComplete()` | End session |

> For detailed guide, see [ShakeBox_MDB_Payment_Guide](ShakeBox_MDB_Payment_Guide.html)

### Custom Recipe (R Series)

```dart
// Method 1: Define recipe then execute
final steps = [
  RecipeStep.cupDispense(dispenser: 1),
  RecipeStep.instantChannel(
    channel: 0, waterType: WaterType.hot,
    materialDuration: 1000, waterAmount: 2000,
    materialSpeed: 50, mixSpeed: 30,
  ),
  RecipeStep.instantChannel(
    channel: 1, waterType: WaterType.hot,
    materialDuration: 500, waterAmount: 0,
    materialSpeed: 50, mixSpeed: 30,
  ),
];
await gs805.setDrinkRecipeProcess(DrinkNumber.hotDrink1, steps);
await gs805.makeDrink(DrinkNumber.hotDrink1);

// Method 2: Execute channels directly
await gs805.testCupDrop();
await gs805.executeChannel(channel: 0, waterType: WaterType.hot,
    materialDuration: 1000, waterAmount: 2000, materialSpeed: 50);
await gs805.executeChannel(channel: 1, waterType: WaterType.hot,
    materialDuration: 500, waterAmount: 0, materialSpeed: 50);
```

### Maintenance Operations

```dart
// Test cup drop
await gs805.testCupDrop();

// Clean all pipes
await gs805.cleanAllPipes();

// Clean specific pipe
await gs805.cleanSpecificPipe(1); // Pipe 1

// Run auto inspection
await gs805.autoInspection();

// Set cup drop mode
await gs805.setCupDropMode(CupDropModeEnum.automatic);

// Return change (for coin dispenser)
final changerStatus = await gs805.returnChange();
print('Changer status: ${changerStatus.description}');
```

### Event Streaming

```dart
// Listen to all messages
gs805.messageStream.listen((message) {
  print('Received message: $message');
});

// Listen to machine events
gs805.eventStream.listen((event) {
  switch (event.type) {
    case MachineEventType.cupDropSuccess:
      print('Cup dropped successfully');
      break;
    case MachineEventType.drinkComplete:
      print('Drink is ready!');
      break;
    case MachineEventType.iceDropComplete:
      print('Ice dropped');
      break;
    case MachineEventType.trackObstacle:
      print('Track obstacle detected');
      break;
  }
});

// Monitor connection state
gs805.connectionStateStream.listen((isConnected) {
  print(isConnected ? 'Connected' : 'Disconnected');
});

// Monitor reconnection attempts
gs805.reconnectEventStream.listen((event) {
  print('Reconnect state: ${event.state}');
  print('Attempt: ${event.attempt}/${event.maxAttempts}');
});
```

### Automatic Reconnection

```dart
// Create with reconnection enabled
final gs805 = GS805Serial(
  reconnectConfig: ReconnectConfig.exponentialBackoff,
);

// Custom reconnection config
final customConfig = ReconnectConfig(
  strategy: ReconnectStrategy.exponentialBackoff,
  maxAttempts: 10,
  initialDelay: Duration(milliseconds: 500),
  maxDelay: Duration(seconds: 30),
  backoffMultiplier: 2.0,
);

final gs805 = GS805Serial(reconnectConfig: customConfig);

// Check reconnection status
if (gs805.isReconnecting) {
  print('Reconnecting...');
}

// Manually trigger reconnection
await gs805.reconnect();
```

For detailed reconnection guide, see [RECONNECT_GUIDE.md](RECONNECT_GUIDE.md).

## API Reference

### Main Classes

- **`GS805Serial`** - Main API class for controlling the coffee machine
- **`SerialDevice`** - Represents a USB serial device
- **`DrinkNumber`** - Enum for drink selection (14 drinks)
- **`MachineStatus`** - Enum for machine status (9 states)
- **`MachineError`** - Machine error information with bit flags
- **`MachineEvent`** - Active report events from machine
- **`LockStatus`** - Door lock status (Series 3/R)
- **`ControllerStatus`** - 32-bit controller status (Series 3/R)
- **`DrinkPreparationStatus`** - Drink preparation progress/failure (Series 3/R)
- **`ObjectExceptionInfo`** - Per-object exception details (Series 3/R)
- **`ObjectType`** - Object type enum for exception queries (Series 3/R)

### Connection Methods

- `listDevices()` → `List<SerialDevice>`
- `connect(SerialDevice device)` → `Future<void>`
- `connectToFirstDevice()` → `Future<void>`
- `connectByVidPid(int vid, int pid)` → `Future<void>`
- `disconnect()` → `Future<void>`

### Drink & Control Methods

- `makeDrink(DrinkNumber drink, {bool useLocalBalance})` → `Future<void>`
- `setDrinkRecipeProcess(DrinkNumber drink, List<RecipeStep> steps)` → `Future<void>` *(R series)*
- `executeChannel({required int channel, ...})` → `Future<void>` *(R series)*
- `setHotTemperature(int upperLimit, int lowerLimit)` → `Future<void>`
- `setColdTemperature(int upperLimit, int lowerLimit)` → `Future<void>`
- `setCupDropMode(CupDropModeEnum mode)` → `Future<void>`
- `testCupDrop()` → `Future<void>`
- `cleanAllPipes()` → `Future<void>`
- `cleanSpecificPipe(int pipeNumber)` → `Future<void>`
- `autoInspection()` → `Future<void>`

### Information Methods

- `getMachineStatus()` → `Future<MachineStatus>`
- `getBalance()` → `Future<MachineBalance>`
- `getSalesCount(DrinkNumber drink)` → `Future<DrinkSalesCount>`
- `getErrorCode()` → `Future<MachineError>`
- `getErrorInfo()` → `Future<ErrorInfo>`
- `setDrinkPrice(DrinkNumber drink, int price)` → `Future<void>`
- `returnChange()` → `Future<ChangerStatus>`

### Series 3/R Extension Methods

- `unitFunctionTest(int testCmd, int data1, int data2, int data3)` → `Future<void>`
- `lockDoor({int lockNumber})` → `Future<LockStatus>`
- `unlockDoor({int lockNumber})` → `Future<LockStatus>`
- `getLockStatus({int lockNumber})` → `Future<LockStatus>`
- `waterRefill()` → `Future<void>`
- `getControllerStatus()` → `Future<ControllerStatus>`
- `getDrinkStatus()` → `Future<DrinkPreparationStatus>`
- `getObjectException(ObjectType objectType)` → `Future<ObjectExceptionInfo>`
- `forceStopDrinkProcess()` → `Future<void>`
- `forceStopCupDelivery()` → `Future<void>`
- `cupDelivery(int waitTimeSeconds)` → `Future<void>`

### Event Streams

- `messageStream` → `Stream<ResponseMessage>`
- `eventStream` → `Stream<MachineEvent>`
- `connectionStateStream` → `Stream<bool>`
- `reconnectEventStream` → `Stream<ReconnectEvent>`

### Properties

- `isConnected` → `bool`
- `connectedDevice` → `SerialDevice?`
- `isReconnecting` → `bool`
- `bufferSize` → `int`

For complete API documentation, run:

```bash
dart doc
```

## Protocol Details

- **Communication**: UART RS232
- **Baud Rate**: 9600
- **Format**: 8N1 (8 data bits, no parity, 1 stop bit)
- **Byte Order**: Big Endian
- **Timeout**: 100ms (with retry mechanism)

## Architecture

The plugin is structured in three layers:

```
┌─────────────────────────────────┐
│      API Layer (GS805Serial)    │  ← High-level user-facing API
├─────────────────────────────────┤
│   Serial Layer (SerialManager)  │  ← Connection & message parsing
├─────────────────────────────────┤
│  Protocol Layer (GS805Protocol) │  ← Message encoding/decoding
└─────────────────────────────────┘
```

## Testing

Run all tests:

```bash
flutter test
```

Run specific test file:

```bash
flutter test test/protocol_test.dart
flutter test test/models_test.dart
flutter test test/api_test.dart
```

Current test coverage: **97/101 tests passing**

## Example App

A complete example app is available in the `example/` directory. It demonstrates:

- Device selection and connection
- Making hot and cold drinks
- Monitoring machine status and events
- Maintenance operations
- Event logging
- Automatic reconnection handling

Run the example:

```bash
cd example
flutter run
```

## Troubleshooting

### Device not found

1. Check USB cable connection
2. Verify USB permissions in AndroidManifest.xml
3. Add your device's VID/PID to device_filter.xml
4. Check if device is recognized: `adb shell ls /dev/tty*`

### Connection fails

1. Ensure correct baud rate (9600)
2. Check that no other app is using the serial port
3. Try reconnecting after a few seconds
4. Enable automatic reconnection

### Command timeout

1. Check machine power and cable connection
2. Verify machine is in ready state
3. Increase timeout duration if needed
4. Check for communication errors in event log

For more help, see:
- [SERIAL_SETUP.md](SERIAL_SETUP.md) - Detailed USB Serial setup
- [RECONNECT_GUIDE.md](RECONNECT_GUIDE.md) - Reconnection configuration
- [GitHub Issues](https://github.com/yourusername/gs805serial/issues)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Author

Created for controlling GS805 series coffee machines via serial communication.

## Acknowledgments

- Uses the [usb_serial](https://pub.dev/packages/usb_serial) package for USB communication
- Implements the GS805 protocol specification
