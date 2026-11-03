import 'package:bms_rider/src/models.dart';
import 'package:bms_rider/src/protocol_jbd.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a valid JBD 0x03 "basic info" RESPONSE frame (BLE framing: the
/// 0xA5 sync byte appears only in requests; responses are
/// `DD <cmd> <status> <len> <payload> <chk hi/lo> 77` — exactly the 2+1+1+1+
/// len+2+1 = len+7 layout the connector's feed() expects).
List<int> _basicFrame({
  int rawCurrent = 50,
  bool unitFlag = true,
  int rawVoltage = 6000,
  int soc = 80,
  double tempC = 25.0,
}) {
  final op = (unitFlag ? 0x80 : 0x00) | 0x02; // unit flag + discharging
  final payload = <int>[
    (rawVoltage >> 8) & 0xFF,
    rawVoltage & 0xFF,
    (rawCurrent >> 8) & 0xFF,
    rawCurrent & 0xFF,
    0x00,
    0xC8, // residual 200 (20.0 Ah @ 0.1)
    0x01,
    0x2C, // nominal 300 (30.0 Ah)
    0x00,
    0x00, // cycles
    0, 0, 0, 0, 0, 0, 0, 0, 0, // bytes 10..18
    soc,
    op,
    16, // cell count
    2, // NTC count
  ];
  final tRaw = (tempC * 10).round() + 2731;
  payload.addAll([(tRaw >> 8) & 0xFF, tRaw & 0xFF]);
  payload.addAll([(tRaw >> 8) & 0xFF, tRaw & 0xFF]);

  final frame = <int>[0xDD, 0x03, 0x00, payload.length, ...payload];
  var s16 = 0;
  // Checksum covers status + len + payload (frame[2 .. len+3]).
  for (var i = 2; i < frame.length; i++) {
    s16 = (s16 + frame[i]) & 0xFFFF;
  }
  final chk = (0 - s16) & 0xFFFF;
  frame.addAll([(chk >> 8) & 0xFF, chk & 0xFF, 0x77]);
  return frame;
}

void main() {
  group('JbdProtocol basic frame parsing', () {
    Telemetry? parse(List<int> frame) {
      final p = JbdProtocol();
      Telemetry? got;
      p.onTelemetry = (t) => got = t;
      p.feed(frame);
      return got;
    }

    test('standard 0.1A unit-flag frame decodes V/I/SOC/cells', () {
      final t = parse(_basicFrame());
      expect(t, isNotNull);
      expect(t!.voltageV, closeTo(60.0, 1e-9));
      expect(t.currentA, closeTo(5.0, 1e-9)); // 50 × 0.1
      expect(t.residualAh, closeTo(20.0, 1e-9));
      expect(t.nominalAh, closeTo(30.0, 1e-9));
      expect(t.socPercent, 80);
      expect(t.cellVolts.length, 16);
      expect(t.tempsC.first, closeTo(25.0, 1e-9));
      expect(t.discharging, isTrue);
      expect(t.charging, isFalse);
    });

    test('0.01A unit (flag unset) also decodes', () {
      final t = parse(_basicFrame(rawCurrent: 500, unitFlag: false));
      expect(t!.currentA, closeTo(5.0, 1e-9)); // 500 × 0.01
    });

    test('sign preserved: negative current = charging/regen', () {
      final t = parse(_basicFrame(rawCurrent: -50, unitFlag: true));
      expect(t!.currentA, closeTo(-5.0, 1e-9));
      expect(t.powerW, closeTo(60.0 * -5.0, 1e-6));
    });

    test('absurd primary decode falls back to alternate unit', () {
      // unit flag set (0.1A) but board actually speaks 0.01A: raw 3000
      // would be 300A (absurd) → alternate unit gives a sane 30A.
      final t = parse(_basicFrame(rawCurrent: 3000, unitFlag: true));
      expect(t!.currentA, closeTo(30.0, 1e-9));
    });

    test('fully absurd current is zeroed instead of forwarded', () {
      // raw 30000 → 3000A (0.1) or 300A (0.01): both absurd → 0.
      final t = parse(_basicFrame(rawCurrent: 30000, unitFlag: true));
      expect(t!.currentA, 0);
    });
  });
}
