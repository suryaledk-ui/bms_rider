import 'package:flutter/services.dart';

/// Thin wrapper around the native Android notification channel
/// (bmsrider/notify) implemented in MainActivity.kt.
class NativeNotifications {
  static const MethodChannel _channel = MethodChannel('bmsrider/notify');

  static Future<void> show(String title, String body) async {
    try {
      await _channel.invokeMethod('show', {'title': title, 'body': body});
    } catch (_) {}
  }
}
