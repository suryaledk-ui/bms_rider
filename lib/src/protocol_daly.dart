import 'dart:typed_data';

import 'models.dart';
import 'protocol.dart';

/// Daly classic 0xA5 UART-over-BLE protocol.
class DalyA5Protocol implements BmsProtocol {
  @override
  final BmsFamily family = BmsFamily.dalyA5;
  @override
  String get name => 'Daly A5';

  @override
  void Function(List<int>) send = (_) {};
  @override
  void Function(Telemetry) onTelemetry = (_) {};

  final List<int> _buf = [];
  final Map<int, List<int>> _last = {};
  Telemetry? _acc;
  int _txFrame = 0;

  int _cellCount = 0;

  Uint8List _req(int cmd) {
    final b = <int>[0xA5, 0x80, cmd, 0x08, 0, 0, 0, 0, 0, 0, 0, 0];
    b.add(sum8(b, 0, b.length));
    return Uint8List.fromList(b);
  }

  @override
  Future<bool> init() async {
    _txFrame = 0;
    return true;
  }

  @override
  void poll() {
    // Poll a rotating subset each tick: SOC/volts/current, min/max cell,
    // temps, mode/capacity, status, THEN a frame of cell voltages.
    _txFrame++;
    switch (_txFrame % 7) {
      case 1:
        send(_req(0x90));
      case 2:
        send(_req(0x91));
      case 3:
        send(_req(0x92));
      case 4:
        send(_req(0x93));
      case 5:
        send(_req(0x94));
      case 6:
        send(_req(0x98));
      case 0:
        final n = _cellCount == 0 ? 16 : _cellCount;
        final frame = ((_txFrame ~/ 7) % ((n + 2) ~/ 3)) + 1;
        send(_req(0x95)); // frame of 3 cells
        _pendingCellFrame = frame;
    }
  }

  int _pendingCellFrame = 1;

  @override
  void feed(List<int> chunk) {
    _buf.addAll(chunk);
    while (_buf.length >= 13) {
      final f = _buf.sublist(0, 13);
      _buf.removeRange(0, 13);
      if (f[0] != 0xA5) continue;
      if (sum8(f, 0, 12) != f[12]) continue;
      final board = f[1];
      if (board < 0x01 || board > 0x10) continue;
      _dispatch(f);
    }
  }

  void _dispatch(List<int> f) {
    final cmd = f[2];
    final d = f.sublist(4, 12);
    _last[cmd] = d;
    switch (cmd) {
      case 0x90:
        final v = rdI16BE(d, 0) / 10.0;
        final cur = (rdU16BE(d, 4) - 30000) / 10.0; // negative = charging
        final soc = rdU16BE(d, 6) / 10.0;
        _acc ??= Telemetry(
          voltageV: 0,
          currentA: 0,
          socPercent: 0,
          residualAh: 0,
          nominalAh: 0,
          cycleCount: 0,
          cellVolts: const [],
          tempsC: const [],
          charging: false,
          discharging: false,
          protocol: name,
          ts: DateTime.now(),
        );
        _acc = Telemetry(
          voltageV: v,
          currentA: -cur,
          socPercent: soc.round(),
          residualAh: _acc!.residualAh,
          nominalAh: _acc!.nominalAh,
          cycleCount: _acc!.cycleCount,
          cellVolts: _acc!.cellVolts,
          tempsC: _acc!.tempsC,
          charging: _acc!.charging,
          discharging: _acc!.discharging,
          protocol: name,
          ts: DateTime.now(),
        );
        _emit();
      case 0x91:
        final maxMv = rdU16BE(d, 0);
        final minMv = rdU16BE(d, 4);
        final cells = <double>[minMv / 1000.0, maxMv / 1000.0];
        _merge(cells: cells);
      case 0x92:
        final temps = <double>[];
        for (var i = 0; i < 4; i++) {
          temps.add((d[i] - 40).toDouble());
        }
        _merge(temps: temps);
      case 0x93:
        final mode = d[0];
        final charging = d[1] == 1;
        final discharging = d[2] == 1;
        final capAh = (rdU32BE(d, 4) / 1000.0).toDouble();
        final resAh = (rdU32BE(d, 4) / 1000.0).toDouble();
        _merge(
          charging: mode == 1 ? true : charging,
          discharging: mode == 1 ? false : discharging,
          residualAh: resAh,
          nominalAh: capAh,
        );
      case 0x94:
        final nCells = d[0];
        final charging = d[2] == 1;
        final discharging = d[3] == 1;
        final cycles = rdU16BE(d, 5);
        _cellCount = nCells;
        _merge(
          charging: charging,
          discharging: discharging,
          cycleCount: cycles,
        );
      case 0x95:
        final frameIdx = _pendingCellFrame;
        // Build cells array: we got 3 cells per frame.
        final got = <double>[];
        for (var i = 0; i + 1 < d.length; i += 2) {
          if (d[i] == 0 && d[i + 1] == 0) continue;
          got.add(rdU16BE(d, i) / 1000.0);
        }
        final start = (frameIdx - 1) * 3;
        final merged = List<double>.from(_acc?.cellVolts ?? const <double>[]);
        for (var i = 0; i < got.length; i++) {
          final idx = start + i;
          if (idx < merged.length) merged[idx] = got[i];
        }
        _merge(cells: merged);
    }
  }

  void _merge({
    List<double>? cells,
    List<double>? temps,
    bool? charging,
    bool? discharging,
    double? residualAh,
    double? nominalAh,
    int? cycleCount,
  }) {
    if (_acc == null) return;
    _acc = Telemetry(
      voltageV: _acc!.voltageV,
      currentA: _acc!.currentA,
      socPercent: _acc!.socPercent,
      residualAh: residualAh ?? _acc!.residualAh,
      nominalAh: nominalAh ?? _acc!.nominalAh,
      cycleCount: cycleCount ?? _acc!.cycleCount,
      cellVolts: cells ?? _acc!.cellVolts,
      tempsC: temps ?? _acc!.tempsC,
      charging: charging ?? _acc!.charging,
      discharging: discharging ?? _acc!.discharging,
      protocol: name,
      ts: DateTime.now(),
    );
    _emit();
  }

  void _emit() {
    if (_acc != null && _acc!.voltageV > 0) onTelemetry(_acc!);
  }

  @override
  void dispose() {
    _buf.clear();
    _acc = null;
  }
}

/// Daly newer Modbus-over-BLE firmware.
class DalyModbusProtocol implements BmsProtocol {
  @override
  final BmsFamily family = BmsFamily.dalyModbus;
  @override
  String get name => 'Daly Modbus';

  @override
  void Function(List<int>) send = (_) {};
  @override
  void Function(Telemetry) onTelemetry = (_) {};

  final List<int> _buf = [];

  static final Uint8List _readAll = _buildReadAll();

  static Uint8List _buildReadAll() {
    final req = <int>[0xD2, 0x03, 0x00, 0x00, 0x00, 0x3E];
    final crc = modbusCrc16(req);
    req.add(crc & 0xFF);
    req.add((crc >> 8) & 0xFF);
    return Uint8List.fromList(req);
  }

  @override
  Future<bool> init() async => true;

  @override
  void poll() {
    send(_readAll);
  }

  @override
  void feed(List<int> chunk) {
    _buf.addAll(chunk);
    while (_buf.length >= 5) {
      if (_buf[0] != 0xD2) {
        _buf.removeAt(0);
        continue;
      }
      final fn = _buf[1];
      if (fn == 0x03) {
        final cnt = _buf[2];
        final total = 3 + cnt + 2;
        if (_buf.length < total) return;
        final f = _buf.sublist(0, total);
        _buf.removeRange(0, total);
        final crc = modbusCrc16(f.sublist(0, f.length - 2));
        if ((crc & 0xFF) != f[f.length - 2] || ((crc >> 8) & 0xFF) != f[f.length - 1]) {
          continue;
        }
        _parseRegs(f.sublist(3, 3 + cnt));
      } else if (fn == 0x83) {
        // exception -> drop
        _buf.removeRange(0, 5);
      } else {
        _buf.removeAt(0);
      }
    }
  }

  void _parseRegs(List<int> data) {
    if (data.length < 114) return;
    final regs = List<int>.generate(data.length ~/ 2, (i) => rdU16BE(data, i * 2));

    final nCells = regs.length > 0x31 ? regs[0x31] : 16;
    final nTemps = regs.length > 0x32 ? regs[0x32] : 2;

    final cells = <double>[];
    for (var i = 0; i < nCells && i < 0x20; i++) {
      cells.add(regs[i] / 1000.0);
    }
    final temps = <double>[];
    for (var i = 0; i < nTemps && (0x20 + i) < regs.length && i < 8; i++) {
      temps.add((regs[0x20 + i] - 40).toDouble());
    }

    final voltage = regs.length > 0x28 ? regs[0x28] / 10.0 : 0.0;
    var current = regs.length > 0x29 ? (regs[0x29] - 30000) / 10.0 : 0.0;
    current = -current; // positive = discharge
    final soc = regs.length > 0x2A ? (regs[0x2A] / 10.0).round() : 0;
    final residual = regs.length > 0x30 ? regs[0x30] / 10.0 : 0.0;
    final cycles = regs.length > 0x33 ? regs[0x33] : 0;
    final chargeMos = regs.length > 0x35 ? regs[0x35] == 1 : false;
    final dischargeMos = regs.length > 0x36 ? regs[0x36] == 1 : false;

    final t = Telemetry(
      voltageV: voltage,
      currentA: current,
      socPercent: soc,
      residualAh: residual,
      nominalAh: 0,
      cycleCount: cycles,
      cellVolts: cells,
      tempsC: temps,
      charging: chargeMos,
      discharging: dischargeMos,
      protocol: name,
      ts: DateTime.now(),
    );
    onTelemetry(t);
  }

  @override
  void dispose() {
    _buf.clear();
  }
}
