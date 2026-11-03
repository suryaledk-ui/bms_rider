"""BLE probe tool for BMS Rider.

1) Scans for the scooter BMS (MAC A5:C2:37:05:AB:B2 or name "60v 30a").
2) Connects, dumps full GATT services/characteristics.
3) Subscribes to all notify-capable characteristics.
4) Writes JBD-style read frames to every writable characteristic.
5) Prints every raw response byte so we can decode the register map.
"""
import asyncio
import datetime
import sys

from bleak import BleakScanner, BleakClient

TARGET_ADDR = "A5:C2:37:05:AB:B2"
TARGET_NAME = "60v 30a"

JBD_FRAMES = [
    ("read_basic", bytes([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77])),
    ("read_cells", bytes([0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77])),
    ("read_hw",    bytes([0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77])),
]


def hexs(b):
    return " ".join(f"{x:02X}" for x in b)


def ts():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


async def scan():
    print(f"[{ts()}] scanning 12s...")
    found = []
    loop = asyncio.get_running_loop()
    stop = loop.create_future()

    def cb(device, adv):
        found.append((device, adv))

    scanner = BleakScanner(detection_callback=cb, scanning_mode="active")
    await asyncio.wait_for(scanner.start(), timeout=10)
    await asyncio.sleep(12)
    await scanner.stop()

    print(f"\n== DEVICES SEEN ({len(found)}) ==")
    seen = {}
    for device, adv in found:
        key = device.address
        name = adv.local_name or device.name or "(no name)"
        rssi = adv.rssi
        if key not in seen or (name != "(no name)" and seen[key][0] == "(no name)"):
            seen[key] = (name, rssi, adv.service_uuids)
    for addr, (name, rssi, svcs) in sorted(seen.items()):
        print(f"{addr}  rssi={rssi:5d}  {name!r}  svcs={svcs}")

    for addr, (name, rssi, svcs) in seen.items():
        if addr.upper() == TARGET_ADDR.upper() or TARGET_NAME.lower() in name.lower():
            return addr
    return None


async def probe(addr):
    print(f"\n[{ts()}] connecting to {addr} ...")
    client = BleakClient(addr)
    try:
        await asyncio.wait_for(client.connect(), timeout=25)
    except Exception as e:
        print(f"CONNECT FAILED: {e!r}")
        return
    print(f"[{ts()}] connected! mtu={client.mtu_size}")

    print("\n== GATT DUMP ==")
    notify_chars = []
    writable_chars = []
    readable_chars = []
    for service in client.services:
        print(f"\nService {service.uuid}")
        for char in service.characteristics:
            props = ",".join(sorted(char.properties))
            print(f"  char {char.uuid}  [{props}]")
            if "notify" in char.properties or "indicate" in char.properties:
                notify_chars.append(char)
            if "write" in char.properties or "write-without-response" in char.properties:
                writable_chars.append(char)
            if "read" in char.properties:
                readable_chars.append(char)

    # subscribe to every notify characteristic
    rx = {char.uuid: [] for char in notify_chars}

    def make_cb(uuid):
        def cb(_sender, data):
            rx[uuid].append(bytes(data))
            print(f"[{ts()}] RX  {uuid}  {hexs(data)}")
        return cb

    for char in notify_chars:
        try:
            await client.start_notify(char, make_cb(char.uuid))
            print(f"[{ts()}] subscribed {char.uuid}")
        except Exception as e:
            print(f"[{ts()}] subscribe FAIL {char.uuid}: {e!r}")

    # probe writes
    for label, frame in JBD_FRAMES:
        for char in writable_chars:
            for with_response in (True, False):
                tag = "wr" if with_response else "wo"
                try:
                    if with_response:
                        await client.write_gatt_char(char, frame, response=True)
                    else:
                        await client.write_gatt_char(char, frame, response=False)
                    print(f"[{ts()}] TX {tag} {char.uuid} {label}: {hexs(frame)}")
                except Exception as e:
                    print(f"[{ts()}] TX {tag} {char.uuid} {label} FAIL: {e!r}")
                await asyncio.sleep(0.7)
        await asyncio.sleep(0.5)

    # read every readable char
    for char in readable_chars:
        try:
            val = await client.read_gatt_char(char)
            print(f"[{ts()}] READ {char.uuid}: {hexs(val)}")
        except Exception as e:
            print(f"[{ts()}] READ {char.uuid} FAIL: {e!r}")

    print("\n== NOTIFY COLLECTED ==")
    for uuid, frames in rx.items():
        print(f"{uuid}: {len(frames)} frames")
        for f in frames:
            print(f"    {hexs(f)}")

    await client.disconnect()
    print(f"\n[{ts()}] disconnected. done.")


async def main():
    addr = await scan()
    if addr is None:
        print("\nTARGET NOT FOUND — is the scooter ON and nearby?")
        sys.exit(1)
    await probe(addr)


try:
    asyncio.run(main())
except Exception as e:
    print(f"FATAL: {e!r}", file=sys.stderr)
    sys.exit(1)
