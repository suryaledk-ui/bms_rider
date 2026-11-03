"""Offline decode: replicate lib/src/protocol_jbd.dart parsing on captured
frames from probe v1/v2, so we can verify the app parser output values.

Frames used (from the live probes of A5:C2:37:05:AB:B2):
  - basic(03): DD 03 00 26 ... F7 F7 77   (v1)
  - cells(04): DD 04 00 20 <16x2> FC D0 77 (v2)
  - hw(05):   DD 05 00 11 "A5:C2:37:05:AB:B2" FC 1C 77 (v2)
"""
import sys

BASIC = bytes.fromhex(
    "DD 03 00 26 19 CE 00 00 0B 91 0B B8 01 D9 2E AD 55 45 00 00 "
    "00 00 33 63 03 10 03 0C 91 0C 6B 0C 23 00 00 00 0B B8 0B 91 "
    "00 00 F7 F7 77"
)
CELLS = bytes.fromhex(
    "DD 04 00 20 10 29 10 20 10 1F 10 07 10 02 10 1F 10 23 10 22 "
    "10 25 10 22 10 22 10 23 10 24 10 24 10 28 10 3F FC D0 77"
)
HW = bytes.fromhex(
    "DD 05 00 11 41 35 3A 43 32 3A 33 37 3A 30 35 3A 41 42 3A 42 "
    "32 FC 1C 77"
)


def sum16(b, start, end):
    s = 0
    for v in b[start:end]:
        s = (s + v) & 0xFFFF
    return s


def rd_u16be(b, o):
    return (b[o] << 8) | b[o + 1]


def rd_i16be(b, o):
    v = rd_u16be(b, o)
    return v - 65536 if v >= 0x8000 else v


def parse(frame, label):
    print(f"--- {label}: {frame.hex(' ')}")
    if len(frame) < 5 or frame[0] != 0xDD:
        print("  BAD header"); return
    fn = frame[1]
    status = frame[2]
    length = frame[3]
    total = length + 7
    ok = len(frame) == total and frame[-1] == 0x77
    if not ok:
        print(f"  LEN MISMATCH len={length} total={total} actual={len(frame)}"); return
    chk = rd_u16be(frame, total - 3)
    s16 = sum16(frame, 2, total - 3)
    expect16 = (0 - s16) & 0xFFFF
    expect8 = (0 - (s16 & 0xFF)) & 0xFF
    print(f"  fn=0x{fn:02X} status=0x{status:02X} len={length} chk=0x{chk:04X} "
          f"expect16=0x{expect16:04X} expect8=0x{expect8:02X} "
          f"{'CHK16 OK' if chk == expect16 else ('CHK8 OK' if chk == expect8 else 'CHK FAIL')}")
    if status != 0:
        print("  status != 0 -> parser drops"); return
    p = frame[4:4 + length]
    if fn == 0x03:
        if len(p) < 23: print("  basic too short"); return
        unit_flag = (p[20] & 0x80) != 0
        div = 0.1 if unit_flag else 0.01
        voltage = rd_u16be(p, 0) * 0.01
        current = rd_i16be(p, 2) * div
        residual = rd_u16be(p, 4) * div
        nominal = rd_u16be(p, 6) * div
        cycles = rd_u16be(p, 8)
        soc = p[19]
        op = p[20]
        n_cells = p[21]
        n_ntc = p[22]
        temps = [(rd_u16be(p, 23 + i * 2) - 2731) * 0.1 for i in range(n_ntc)]
        print(f"  voltage={voltage:.2f}V current={current:.2f}A residual={residual:.2f}Ah "
              f"nominal={nominal:.2f}Ah cycles={cycles} SOC={soc}% op=0x{op:02X} "
              f"cells={n_cells} ntc={n_ntc} temps={[round(t,1) for t in temps]}C")
    elif fn == 0x04:
        cells = [rd_u16be(p, i) / 1000.0 for i in range(0, len(p) - 1, 2)]
        print(f"  cells({len(cells)}): {[round(c,3) for c in cells]}")
    elif fn == 0x05:
        s = p.decode('ascii', 'replace')
        print(f"  hw string: {s!r}")
    else:
        print(f"  payload({len(p)}): {p.hex(' ')}")


parse(BASIC, "basic(03) v1")
parse(CELLS, "cells(04) v2")
parse(HW, "hw(05) v2")
