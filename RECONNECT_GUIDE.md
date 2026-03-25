# Reconnection Guide

The GS805 Serial plugin includes automatic reconnection capabilities to handle temporary connection losses.

## Features

- **Automatic Reconnection**: Automatically attempts to reconnect when connection is lost
- **Multiple Strategies**: Choose from immediate, exponential backoff, or fixed interval
- **Configurable**: Customize retry count, delays, and backoff multipliers
- **Event Streaming**: Monitor reconnection attempts in real-time

## Reconnection Strategies

### 1. Never (No Reconnection)

```dart
final manager = SerialManager(
  connection,
  reconnectConfig: ReconnectConfig.never,
);
```

### 2. Immediate Reconnection

Reconnects immediately when connection is lost (no delay).

```dart
final manager = SerialManager(
  connection,
  reconnectConfig: ReconnectConfig.immediate,
);
```

### 3. Exponential Backoff (Recommended)

Starts with a short delay and exponentially increases between attempts.

```dart
final manager = SerialManager(
  connection,
  reconnectConfig: ReconnectConfig.exponentialBackoff, // Default
);

// Delays: 500ms, 1s, 2s, 4s, 8s, ...
```

### 4. Fixed Interval

Waits a fixed amount of time between each attempt.

```dart
final manager = SerialManager(
  connection,
  reconnectConfig: ReconnectConfig.fixedInterval,
);

// Delays: 2s, 2s, 2s, 2s, ...
```

## Custom Configuration

```dart
final customConfig = ReconnectConfig(
  strategy: ReconnectStrategy.exponentialBackoff,
  maxAttempts: 10,                           // Try up to 10 times
  initialDelay: Duration(milliseconds: 100), // Start with 100ms
  maxDelay: Duration(seconds: 60),           // Cap at 60 seconds
  backoffMultiplier: 2.0,                    // Double delay each time
  reconnectOnError: true,                    // Reconnect on errors
);

final manager = SerialManager(
  connection,
  reconnectConfig: customConfig,
);
```

## Monitoring Reconnection

### Listen to Reconnection Events

```dart
manager.reconnectEventStream.listen((event) {
  print('Reconnect State: ${event.state}');
  print('Attempt: ${event.attempt}/${event.maxAttempts}');

  switch (event.state) {
    case ReconnectState.waiting:
      print('Waiting ${event.nextAttemptDelay}...');
      break;
    case ReconnectState.connecting:
      print('Attempting to reconnect...');
      break;
    case ReconnectState.connected:
      print('Reconnected successfully!');
      break;
    case ReconnectState.failed:
      print('Reconnection failed: max attempts reached');
      break;
    default:
      break;
  }
});
```

### Check Reconnection Status

```dart
// Check if currently reconnecting
if (manager.isReconnecting) {
  print('Reconnecting... Attempt ${manager.reconnectAttemptCount}');
}

// Get current state
final state = manager.reconnectState;
print('Current state: $state');
```

## Manual Reconnection

You can manually trigger reconnection:

```dart
try {
  await manager.reconnect();
  print('Manually reconnected!');
} catch (e) {
  print('Manual reconnection failed: $e');
}
```

## Disconnect Behavior

By default, disconnecting clears reconnection settings:

```dart
// Disconnect and stop reconnection attempts
await manager.disconnect(); // clearReconnection: true (default)

// Disconnect but keep reconnection enabled
await manager.disconnect(clearReconnection: false);
```

## Complete Example

```dart
import 'package:gs805serial/src/serial/usb_serial_connection.dart';
import 'package:gs805serial/src/serial/serial_manager.dart';
import 'package:gs805serial/src/serial/reconnect_manager.dart';

void main() async {
  // Create manager with exponential backoff
  final connection = UsbSerialConnection();
  final manager = SerialManager(
    connection,
    reconnectConfig: ReconnectConfig(
      strategy: ReconnectStrategy.exponentialBackoff,
      maxAttempts: 5,
      initialDelay: Duration(milliseconds: 500),
      maxDelay: Duration(seconds: 30),
    ),
  );

  // Monitor reconnection events
  manager.reconnectEventStream.listen((event) {
    switch (event.state) {
      case ReconnectState.waiting:
        print('⏳ Waiting ${event.nextAttemptDelay?.inMilliseconds}ms '
              'before attempt ${event.attempt + 1}/${event.maxAttempts}');
        break;
      case ReconnectState.connecting:
        print('🔄 Reconnecting... (attempt ${event.attempt + 1})');
        break;
      case ReconnectState.connected:
        print('✅ Reconnected successfully!');
        break;
      case ReconnectState.failed:
        print('❌ Reconnection failed after ${event.attempt} attempts');
        break;
      default:
        break;
    }
  });

  // Monitor connection state
  manager.connectionStateStream.listen((isConnected) {
    if (isConnected) {
      print('📡 Connected');
    } else {
      print('📡 Disconnected - reconnection will start automatically');
    }
  });

  // Connect to device
  final devices = await manager.listDevices();
  if (devices.isNotEmpty) {
    await manager.connect(devices.first);
  }

  // Connection lost? Reconnection happens automatically!
  // No manual intervention needed.

  // Later, disconnect
  await manager.disconnect();
  await manager.dispose();
}
```

## Reconnection Delays

### Exponential Backoff Example

With default settings (`initialDelay: 500ms`, `backoffMultiplier: 2.0`, `maxDelay: 30s`):

| Attempt | Delay     |
|---------|-----------|
| 1       | 500ms     |
| 2       | 1s        |
| 3       | 2s        |
| 4       | 4s        |
| 5       | 8s        |
| 6       | 16s       |
| 7+      | 30s (cap) |

### Fixed Interval Example

With default settings (`initialDelay: 2s`):

| Attempt | Delay |
|---------|-------|
| 1-10    | 2s    |

## Best Practices

1. **Use Exponential Backoff**: Best for most cases - balances quick recovery with reduced load
2. **Set Max Attempts**: Prevent infinite reconnection attempts
3. **Monitor Events**: Show users reconnection status
4. **Handle Failed State**: Notify users when max attempts reached
5. **Test Connection Loss**: Simulate USB cable unplug to verify behavior

## Troubleshooting

### Reconnection Not Working

1. Check that reconnection is enabled:
   ```dart
   if (manager.reconnectState == ReconnectState.idle) {
     print('Reconnection not active');
   }
   ```

2. Verify configuration:
   ```dart
   print('Max attempts: ${reconnectConfig.maxAttempts}');
   print('Strategy: ${reconnectConfig.strategy}');
   ```

### Too Many Reconnection Attempts

Increase the delay or reduce max attempts:

```dart
final config = ReconnectConfig(
  maxAttempts: 3,              // Reduce attempts
  initialDelay: Duration(seconds: 5), // Longer initial delay
);
```

### Reconnection Too Slow

Use immediate strategy or shorter delays:

```dart
final config = ReconnectConfig(
  strategy: ReconnectStrategy.immediate, // No delay
  maxAttempts: 3,
);
```
