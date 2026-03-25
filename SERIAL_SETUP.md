# USB Serial Setup Guide

This guide explains how to set up USB serial communication for the GS805 plugin.

## Android Setup

### 1. Add USB Feature to AndroidManifest.xml

In your app's `android/app/src/main/AndroidManifest.xml`, add the USB host feature:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- USB Host permission -->
    <uses-feature android:name="android.hardware.usb.host" android:required="false" />

    <application>
        ...
    </application>
</manifest>
```

### 2. Add USB Device Attached Intent Filter

Inside your main `<activity>` tag, add:

```xml
<activity>
    <!-- Your existing intent filters -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>

    <!-- USB device attached intent -->
    <intent-filter>
        <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
    </intent-filter>

    <!-- USB device metadata -->
    <meta-data
        android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
        android:resource="@xml/device_filter" />
</activity>
```

### 3. Create USB Device Filter (Optional)

Create `android/app/src/main/res/xml/device_filter.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Common USB Serial Chipsets -->
    <usb-device vendor-id="1027" />  <!-- FTDI -->
    <usb-device vendor-id="4292" />  <!-- CP210x -->
    <usb-device vendor-id="6790" />  <!-- CH340/CH341 -->
    <usb-device vendor-id="1659" />  <!-- Prolific PL2303 -->

    <!-- Add your specific device VID/PID if known -->
    <!-- <usb-device vendor-id="XXXX" product-id="YYYY" /> -->
</resources>
```

## Usage Example

### List Available Devices

```dart
import 'package:gs805serial/src/serial/usb_serial_connection.dart';

final connection = UsbSerialConnection();
final devices = await connection.listDevices();

for (var device in devices) {
  print('Device: ${device.name}');
  print('  ID: ${device.id}');
  print('  VID: 0x${device.vendorId?.toRadixString(16)}');
  print('  PID: 0x${device.productId?.toRadixString(16)}');
}
```

### Connect to Device

```dart
import 'package:gs805serial/src/serial/serial_connection.dart';
import 'package:gs805serial/src/serial/usb_serial_connection.dart';

// Method 1: Manual device selection
final connection = UsbSerialConnection();
final devices = await connection.listDevices();
await connection.connect(devices.first, SerialConfig.gs805);

// Method 2: Connect to first device
final connection2 = await UsbSerialConnectionExt.connectToFirstDevice();

// Method 3: Connect by VID/PID
final connection3 = await UsbSerialConnectionExt.connectByVidPid(
  0x1A86, // CH340 vendor ID
  0x7523, // CH340 product ID
);
```

### Send and Receive Data

```dart
// Send data
final bytes = Uint8List.fromList([0xAA, 0x55, 0x02, 0x0B, 0x0C]);
await connection.write(bytes);

// Receive data
connection.inputStream.listen((data) {
  print('Received: ${data.map((b) => b.toRadixString(16)).join(' ')}');
});

// Disconnect
await connection.disconnect();
```

## Troubleshooting

### Device Not Found

1. Check USB cable connection
2. Verify device is powered on
3. Check USB OTG adapter (if using tablet)
4. Ensure proper permissions in AndroidManifest.xml

### Permission Denied

The `usb_serial` package automatically requests USB permissions. If you encounter permission issues:

1. Unplug and replug the USB device
2. Check that the device_filter.xml includes your device's VID/PID
3. Restart the app

### Data Not Received

1. Verify correct baud rate (GS805 uses 9600)
2. Check cable quality
3. Ensure device is sending data
4. Monitor connection state:

```dart
connection.connectionStateStream.listen((isConnected) {
  print('Connection state: ${isConnected ? 'Connected' : 'Disconnected'}');
});
```

## Supported USB Serial Chipsets

The `usb_serial` package supports:

- **FTDI** - FT232, FT2232, FT4232, etc.
- **CP210x** - CP2102, CP2104, CP2105, etc.
- **CH34x** - CH340, CH341
- **PL2303** - Prolific USB-to-Serial
- **CDC ACM** - Generic USB serial devices

## Finding Your Device VID/PID

### On Android

Use the `listDevices()` method to see all connected devices and their VID/PID.

### On Windows

1. Open Device Manager
2. Find your device under "Ports (COM & LPT)"
3. Right-click → Properties → Details
4. Select "Hardware Ids"
5. Look for `VID_XXXX&PID_YYYY`

### On Linux/Mac

```bash
lsusb
```

Look for your device in the output. Format: `Bus XXX Device XXX: ID VID:PID`

## Notes

- USB serial communication requires physical USB connection
- Not supported on iOS (iOS has limited USB host support)
- Some Android devices may not support USB host mode
- Always check `isConnected` before sending data
- Handle disconnection events gracefully
