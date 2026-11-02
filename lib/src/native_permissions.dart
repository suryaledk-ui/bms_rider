import 'package:flutter/services.dart';

/// Thin wrapper around native Android permission handling in MainActivity.kt
/// (avoids a plugin dependency that would drag in newer compileSdk versions).
class NativePermissions {
  static const MethodChannel _channel = MethodChannel('bmsrider/permissions');

  /// Bluetooth permissions required for BLE scanning/connecting.
  /// On Android 12+ we do NOT need (and do not request) location for BLE,
  /// since the app declares neverForLocation on BLUETOOTH_SCAN.
  /// On Android <12 location is required for scanning, so we include it.
  static Future<bool> requestBleOnly() async {
    try {
      final result = await _channel.invokeMethod<Map>('requestBle');
      return result?['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Used only when starting a ride (GPS tracking).
  static Future<bool> requestLocation() async {
    try {
      final result = await _channel.invokeMethod<Map>('requestLocation');
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
