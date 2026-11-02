// Protocol abstraction + shared byte utilities for smart-BMS families
// (JBD/Xiaoxiang, Daly classic A5 + Modbus, JK/Jikong, ANT).

import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';

/// [name] of the BMS family this protocol knows how to talk to.
enum BmsFamily { jbd, dalyA5, dalyModbus, jk, ant }

String familyHint(BmsFamily f) => switch (f) {
      BmsFamily.jbd => 'JBD',
      BmsFamily.dalyA5 => 'Daly A5',
      BmsFamily.dalyModbus => 'Daly Modbus',
      BmsFamily.jk => 'JK',
      BmsFamily.ant => 'ANT',
    };

/// Callback interface the connector uses to drive a protocol implementation.
abstract class BmsProtocol {
  BmsFamily get family;
  String get name;

  /// Send a raw frame to the BMS.
  void Function(List<int>) get send;
  set send(void Function(List<int>) v);

  /// Feed bytes received from the notify characteristic. Implementations
  /// are responsible for frame reassembly + validation.
  void feed(List<int> chunk);

  /// Called by implementations when a complete telemetry snapshot is ready.
  void Function(Telemetry) get onTelemetry;
  set onTelemetry(void Function(Telemetry) v);

  /// Request a full basic-info poll. Called by the connector periodically.
  void poll();

  /// Some protocols need a handshake before commands are accepted. Called once
  /// after connect. Return true if handshake is complete or unnecessary.
  Future<bool> init();

  void dispose();
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

Uint8List u8(int v) => Uint8List.fromList([v & 0xFF]);

Uint8List u16be(int v) => Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
Uint8List u16le(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);

int rdU16BE(List<int> b, int off) => (b[off] << 8) | b[off + 1];
int rdU16LE(List<int> b, int off) => b[off] | (b[off + 1] << 8);

int rdI16BE(List<int> b, int off) {
  final v = rdU16BE(b, off);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int rdI16LE(List<int> b, int off) {
  final v = rdU16LE(b, off);
  return v >= 0x8000 ? v - 0x10000 : v;
}

int rdU32BE(List<int> b, int off) =>
    (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

int rdU32LE(List<int> b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

int rdI32LE(List<int> b, int off) {
  final v = rdU32LE(b, off);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

int sum8(List<int> b, int start, int end) {
  var s = 0;
  for (var i = start; i < end; i++) {
    s = (s + b[i]) & 0xFF;
  }
  return s;
}

int modbusCrc16(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc & 0xFFFF;
}

/// Pull a 128-bit GUID with the given 16-bit suffix.
Guid guidShort(int shortUuid) =>
    Guid('0000${shortUuid.toRadixString(16).padLeft(4, '0')}-0000-1000-8000-00805f9b34fb');

final Guid kSvcFF00 = Guid('0000ff00-0000-1000-8000-00805f9b34fb');
final Guid kSvcFFF0 = Guid('0000fff0-0000-1000-8000-00805f9b34fb');
final Guid kSvcFFE0 = Guid('0000ffe0-0000-1000-8000-00805f9b34fb');

/// Guess family from advertised service UUIDs + name (best effort).
BmsFamily? guessFamily(List<Guid> services, String name) {
  bool has(Guid g) => services.any((s) => s.toString().toLowerCase() == g.toString().toLowerCase());
  final n = name.toLowerCase();
  if (has(kSvcFFE0)) {
    if (n.contains('ant')) return BmsFamily.ant;
    if (n.contains('jk') || n.contains('jikong') || n.contains('bms') || n.contains('pb')) {
      return BmsFamily.jk;
    }
    return BmsFamily.jk; // probe will disambiguate
  }
  if (has(kSvcFF00)) {
    if (n.contains('daly') || n.startsWith('dl-')) return BmsFamily.dalyModbus;
    return BmsFamily.jbd; // probe will disambiguate
  }
  if (has(kSvcFFF0)) {
    if (n.contains('daly') || n.startsWith('dl-')) return BmsFamily.dalyA5;
    return BmsFamily.jbd; // probe will disambiguate
  }
  // Supermarket of guesses: look for known name patterns even without services.
  if (n.contains('jbd') || n.contains('xiaoxiang') || n.contains('lismart')) return BmsFamily.jbd;
  if (n.contains('daly') || n.startsWith('dl-')) return BmsFamily.dalyA5;
  if (n.contains('jk') || n.contains('jikong')) return BmsFamily.jk;
  if (n.contains('ant')) return BmsFamily.ant;
  return null;
}
