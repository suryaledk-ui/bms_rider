import 'package:flutter/services.dart';

/// Thin wrapper around native Android location-service state in MainActivity.kt.
class NativeLocationServices {
  static const MethodChannel _channel = MethodChannel('bmsrider/location_services');

  /// True when the system Location Services (GPS) master switch is ON.
  /// BLE scanning on Android <12 (and on many 12+ OEM stacks without
  /// neverForLocation) silently returns zero devices while this is OFF.
  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }
}
