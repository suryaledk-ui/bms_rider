import 'dart:typed_data';

import 'models.dart';
import 'protocol.dart';

class JkProtocol implements BmsProtocol {
  @override
  final BmsFamily family = BmsFamily.jk;
  @override
  String get name => 'JK';

  @override
  void Function(List<int>) send = (_) {};
  @override
  void Function(Telemetry) onTelemetry = (_) {};

  final List<int> _buf = [];
  Telemetry? _last;

  int _counter = 0;

  Uint8List _cmd(int code) {
    final b = <int>[
      0xAA, 0x55, 0x90, 0xEB, code, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      _counter & 0xFF, 0x00, 0x00, 0x00,
    ];
    b[19] = sum8(b, 0, 19);
    _counter++;
    return Uint8List.fromList(b);
  }

  @override
  Future<bool> init() async {
    send(_cmd(0x96)); // settings request
    send(_cmd(0x97)); // device info request
    return true;
  }

  @override
  void poll() {
    // after init, BMS auto-streams cell-info frames; nothing else needed
  }

  @override
  void feed(List<int> chunk) {
    _buf.addAll(chunk);
    while (true) {
      var start = -1;
      for (var i = 0; i + 3 < _buf.length; i++) {
        if (_buf[i] == 0x55 && _buf[i + 1] == 0xAA && _buf[i + 2] == 0xEB && _buf[i + 3] == 0x90) {
          start = i;
          break;
        }
      }
      if (start < 0) {
        _buf.clear();
        return;
      }
      if (start > 0) _buf.removeRange(0, start);
      // try to find frame end: length depends on type; probe up to 320 bytes
      if (_buf.length < 10) return;
      final type = _buf[4];
      if (type == 0x02) {
        // cell info frame ~169+ bytes
        if (_buf.length < 190) return;
        final f = _buf.sublist(0, 190);
        _buf.removeRange(0, 190);
        _parseCellInfo(f);
      } else if (type == 0x01 || type == 0x03) {
        if (_buf.length < 30) return;
        _buf.removeRange(0, 30); // settings/device info: parse later
      } else {
        _buf.removeAt(0);
      }
    }
  }

  void _parseCellInfo(List<int> f) {
    final cells = <double>[];
    // cells start at offset 6, each 2 bytes LE, mV
    for (var i = 6; i + 1 < f.length && i < 6 + 64; i += 2) {
      final mv = rdU16LE(f, i);
      if (mv > 0 && mv < 6000) cells.add(mv / 1000.0);
    }
    double v = 0;
    if (f.length >= 154) v = rdU32LE(f, 150) / 1000.0;
    double cur = 0;
    if (f.length >= 162) cur = rdI32LE(f, 158) / 1000.0;
    double t1 = 0, t2 = 0;
    if (f.length >= 164) t1 = rdI16LE(f, 162) * 0.1;
    if (f.length >= 166) t2 = rdI16LE(f, 164) * 0.1;
    final soc = f.length > 173 ? f[173] : 0;
    double remAh = 0, nomAh = 0;
    if (f.length >= 178) remAh = rdU32LE(f, 174) / 1000.0;
    if (f.length >= 182) nomAh = rdU32LE(f, 178) / 1000.0;
    int cycles = 0;
    if (f.length >= 186) cycles = rdU32LE(f, 182);

    _last = Telemetry(
      voltageV: v,
      currentA: cur,
      socPercent: soc,
      residualAh: remAh,
      nominalAh: nomAh,
      cycleCount: cycles,
      cellVolts: cells,
      tempsC: [t1, t2].where((t) => t.abs() > 1).toList(),
      charging: false,
      discharging: cur > 0,
      protocol: name,
      ts: DateTime.now(),
    );
    onTelemetry(_last!);
  }

  @override
  void dispose() {
    _buf.clear();
  }
}

/// ANT — identification only for now (status parsing deferred).
class AntProtocol implements BmsProtocol {
  @override
  final BmsFamily family = BmsFamily.ant;
  @override
  String get name => 'ANT';

  @override
  void Function(List<int>) send = (_) {};
  @override
  void Function(Telemetry) onTelemetry = (_) {};

  @override
  Future<bool> init() async => false; // signals unsupported

  @override
  void poll() {}

  @override
  void feed(List<int> chunk) {}

  @override
  void dispose() {}
}
