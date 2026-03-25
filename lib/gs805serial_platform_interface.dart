import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'gs805serial_method_channel.dart';

abstract class Gs805serialPlatform extends PlatformInterface {
  /// Constructs a Gs805serialPlatform.
  Gs805serialPlatform() : super(token: _token);

  static final Object _token = Object();

  static Gs805serialPlatform _instance = MethodChannelGs805serial();

  /// The default instance of [Gs805serialPlatform] to use.
  ///
  /// Defaults to [MethodChannelGs805serial].
  static Gs805serialPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [Gs805serialPlatform] when
  /// they register themselves.
  static set instance(Gs805serialPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
