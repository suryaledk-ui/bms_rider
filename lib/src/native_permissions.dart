import 'package:flutter/services.dart';

/// Thin wrapper around native Android permission handling in MainActivity.kt
/// (avoids a plugin dependency that would drag in newer compileSdk versions).
class NativePermissions {
  static const MethodChannel _channel = MethodChannel('bmsrider/permissions');

  static Future<bool> requestBleAndLocation() async {
    try {
      final result = await _channel.invokeMethod<Map>('request');
      return result?['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
  }
}
