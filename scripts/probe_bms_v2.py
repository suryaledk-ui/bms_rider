"""Probe v2: JBD clone on 0xFF00/0xFF01/0xFF02 — capture every response frame.

Skips the mystery 0x00010203 service (needs bonding; kills the link).
Writes each read command, waits, then also tries a PULL read on 0xFF01.
"""
import asyncio
import datetime
import sys

from bleak import BleakClient

TARGET_ADDR = "A5:C2:37:05:AB:B2"

FF01 = "0000ff01-0000-1000-8000-00805f9b34fb"
FF02 = "0000ff02-0000-1000-8000-00805f9b34fb"

# JBD-style read commands (cmd, label)
READ_CMDS = [
    (bytes([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77]), "basic(03)"),
    (bytes([0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77]), "cells(04)"),
    (bytes([0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77]), "hw(05)"),
    (bytes([0xDD, 0xA5, 0x02, 0x00, 0xFF, 0xFE, 0x77]), "cmd02"),
    (bytes([0xDD, 0xA5, 0x06, 0x00, 0xFF, 0xFA, 0x77]), "cmd06"),
    (bytes([0xDD, 0xA5, 0x07, 0x00, 0xFF, 0xF9, 0x77]), "cmd07"),
]


def hexs(b):
    return " ".join(f"{x:02X}" for x in b)


def ts():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


async def main():
    client = BleakClient(TARGET_ADDR)
    try:
        await asyncio.wait_for(client.connect(), timeout=25)
    except Exception as e:
        print(f"CONNECT FAILED: {e!r}")
        return
    print(f"[{ts()}] connected, mtu={client.mtu_size}")

    rx = []
    def cb(_s, data):
        rx.append((ts(), bytes(data)))
        print(f"[{ts()}] RX {hexs(data)}")
    await client.start_notify(FF01, cb)

    for frame, label in READ_CMDS:
        print(f"\n[{ts()}] >>> TX {label}: {hexs(frame)}")
        try:
            await client.write_gatt_char(FF02, frame, response=False)
        except Exception as e:
            print(f"    write FAIL: {e!r}")
        await asyncio.sleep(1.2)
        # pull-read what the module currently holds on FF01
        try:
            val = await client.read_gatt_char(FF01)
            print(f"[{ts()}] PULL-READ FF01: {hexs(val)}")
        except Exception as e:
            print(f"    pull-read FAIL: {e!r}")

    print(f"\n== TOTAL RX FRAGMENTS: {len(rx)} ==")
    await client.disconnect()
    print("done.")


try:
    asyncio.run(main())
except Exception as e:
    print(f"FATAL: {e!r}", file=sys.stderr)
    sys.exit(1)
