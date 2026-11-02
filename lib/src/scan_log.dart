import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rolling scan/connect log persisted locally so the user can send it when
/// a BMS does not show up.
class ScanLogger extends ChangeNotifier {
  final List<String> _lines = [];
  static const int maxLines = 400;
  static const String _prefKey = 'scan_log_lines';
  bool _loaded = false;

  String get text => _lines.join('\n');
  bool get isEmpty => _lines.isEmpty;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefKey);
      if (saved != null) {
        _lines..clear()..addAll(saved.take(maxLines));
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  static String _ts(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  void log(String tag, String message) {
    final line = '[${_ts(DateTime.now())}] [$tag] $message';
    _lines.add(line);
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
    }
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, List.of(_lines));
    } catch (_) {}
  }

  Future<void> clear() async {
    _lines.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> exportTo(String path) async {
    try {
      final file = await File(path).create(recursive: true);
      await file.writeAsString(text);
    } catch (_) {}
  }
}
