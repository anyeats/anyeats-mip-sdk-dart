import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'gs805serial_platform_interface.dart';

/// An implementation of [Gs805serialPlatform] that uses method channels.
class MethodChannelGs805serial extends Gs805serialPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('gs805serial');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
