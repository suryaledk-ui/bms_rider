import 'dart:typed_data';

import 'models.dart';
import 'protocol.dart';

/// JBD (Jiabaida / Xiaoxiang) BMS over BLE.
///
/// Service 0xFF00 (or 0xFFF0 on some dongles), notify 0xFF01/0xFFF1,
/// write 0xFF02/0xFFF2. Frames are 0xDD ... 0x77 with a 16-bit inverted-sum
/// checksum over the function/type, length and payload bytes.
class JbdProtocol implements BmsProtocol {
  @override
  final BmsFamily family = BmsFamily.jbd;
  @override
  String get name => 'JBD';

  @override
  void Function(List<int>) send = (_) {};
  @override
  void Function(Telemetry) onTelemetry = (_) {};

  final List<int> _buf = [];
  Telemetry? _last;

  static final Uint8List _readBasic = Uint8List.fromList([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77]);
  static final Uint8List _readCells = Uint8List.fromList([0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77]);

  @override
  Future<bool> init() async {
    // Most JBD boards accept commands immediately. Auth-gated boards are
    // handled best-effort: if a read comes back as an auth frame we respond
    // with the default '123456' credential in _handleAuthFrame.
    return true;
  }

  @override
  void poll() {
    send(_readBasic);
    // cells polled at lower rate by connector (poll() called for basic only)
  }

  Uint8List pollCells() => _readCells;

  @override
  void feed(List<int> chunk) {
    _buf.addAll(chunk);
    while (true) {
      // resync to frame start
      var start = _buf.indexOf(0xDD);
      if (start < 0) {
        _buf.clear();
        return;
      }
      if (start > 0) {
        _buf.removeRange(0, start);
      }
      if (_buf.length < 5) return;
      final len = _buf[3];
      final total = len + 7;
      if (_buf.length < total) return;
      final frame = _buf.sublist(0, total);
      _buf.removeRange(0, total);

      if (frame[total - 1] != 0x77) continue; // garbage, resync

      // Clone boards (e.g. "60v 30a" JBD clones) emit a real 16-bit
      // inverted-sum checksum; some boards use the 8-bit variant.
      // Accept both.
      var s16 = 0;
      for (var i = 2; i < total - 3; i++) {
        s16 = (s16 + frame[i]) & 0xFFFF;
      }
      final chk = rdU16BE(frame, total - 3);
      final ok16 = chk == ((0 - s16) & 0xFFFF);
      final ok8 = chk == ((0 - (s16 & 0xFF)) & 0xFF);
      if (!ok16 && !ok8) continue; // bad checksum

      _dispatch(frame, len);
    }
  }

  void _dispatch(List<int> f, int len) {
    final fn = f[1];
    if (fn == 0xFF) {
      // auth channel (0xAA at f[1]? no: auth frames start FF AA cmd...)
      _handleAuthFrame(f);
      return;
    }
    if (f[2] != 0x00) return; // status != ok
    final payload = f.sublist(4, 4 + len);
    switch (fn) {
      case 0x03:
        _parseBasic(payload);
      case 0x04:
        _parseCells(payload);
    }
  }

  void _handleAuthFrame(List<int> f) {
    // Auth frame structure: FF AA <cmd> <len> <payload...> <sum>
    if (f.length < 4) return;
    final cmd = f[2];
    final len = f[3];
    final payload = f.length >= 4 + len ? f.sublist(4, 4 + len) : <int>[];
    if (cmd == 0x15 && payload.isNotEmpty && payload[0] == 0x02) {
      // no password set -> proceed
    } else if (cmd == 0x17 && payload.isNotEmpty) {
      // random challenge: answer with encrypted password '123456'
      final rnd = payload[0];
      const pwd = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36]; // '123456'
      final b = List<int>.generate(6, (i) => (pwd[i] + rnd) & 0xFF);
      final frame = [0xFF, 0xAA, 0x18, 0x06, ...b];
      frame.add(sum8(frame, 2, frame.length));
      send(frame);
    }
  }

  void _parseBasic(List<int> p) {
    if (p.length < 23) return;
    final unitFlag = (p[20] & 0x80) != 0;
    final div = unitFlag ? 0.1 : 0.01;

    final voltage = rdU16BE(p, 0) * 0.01;
    final current = rdI16BE(p, 2) * div;
    final residual = rdU16BE(p, 4) * div;
    final nominal = rdU16BE(p, 6) * div;
    final cycles = rdU16BE(p, 8);
    final soc = p[19];
    final op = p[20];
    final nCells = p[21];
    final nNtc = p[22];

    final temps = <double>[];
    for (var i = 0; i < nNtc; i++) {
      final raw = rdU16BE(p, 23 + i * 2);
      temps.add((raw - 2731) * 0.1);
    }

    _last = Telemetry(
      voltageV: voltage,
      currentA: current,
      socPercent: soc,
      residualAh: residual,
      nominalAh: nominal,
      cycleCount: cycles,
      cellVolts: List.filled(nCells, 0), // filled from 0x04 replies
      tempsC: temps,
      charging: (op & 0x01) != 0,
      discharging: (op & 0x02) != 0,
      protocol: name,
      ts: DateTime.now(),
    );
    _emit();
  }

  void _parseCells(List<int> p) {
    if (_last == null || p.isEmpty) return;
    final cells = <double>[];
    for (var i = 0; i + 1 < p.length; i += 2) {
      cells.add(rdU16BE(p, i) / 1000.0);
    }
    _last = Telemetry(
      voltageV: _last!.voltageV,
      currentA: _last!.currentA,
      socPercent: _last!.socPercent,
      residualAh: _last!.residualAh,
      nominalAh: _last!.nominalAh,
      cycleCount: _last!.cycleCount,
      cellVolts: cells,
      tempsC: _last!.tempsC,
      charging: _last!.charging,
      discharging: _last!.discharging,
      protocol: name,
      ts: DateTime.now(),
    );
    _emit();
  }

  void _emit() {
    if (_last != null) onTelemetry(_last!);
  }

  @override
  void dispose() {
    _buf.clear();
  }
}
