import 'package:flutter/services.dart';

/// Result of the native legacy BLE scan (BluetoothAdapter.startLeScan).
class LegacyScanResult {
  final String id;
  final String name;
  final int rssi;
  const LegacyScanResult({required this.id, required this.name, required this.rssi});
}

/// Native BLE scanner mirroring BAT-BMS/FastBLE's legacy API. On cheap
/// Android 12 stacks (MediaTek/LAVA) the new BluetoothLeScanner silently
/// returns nothing while the legacy API works.
class NativeLegacyScan {
  static const MethodChannel _channel = MethodChannel('bmsrider/legacy_scan');

  static Future<List<LegacyScanResult>> scan(Duration timeout) async {
    try {
      final raw = await _channel.invokeListMethod('scan', {
        'timeoutMs': timeout.inMilliseconds,
      });
      if (raw == null) return const [];
      return raw.whereType<Map>().map((m) {
        return LegacyScanResult(
          id: (m['id'] as String?) ?? '',
          name: (m['name'] as String?) ?? '',
          rssi: (m['rssi'] as num?)?.toInt() ?? -127,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
