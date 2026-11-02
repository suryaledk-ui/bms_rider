import asyncio
import sys

from bleak import BleakScanner

async def main():
    results = {}

    def cb(device, adv):
        key = device.address
        svcs = [str(s) for s in (adv.service_uuids or [])]
        if key not in results or adv.local_name:
            results[key] = (device.name or "(no name)", adv.rssi, svcs, adv.manufacturer_data is not None)

    scanner = BleakScanner(detection_callback=cb, scanning_mode="active")
    await scanner.start()
    await asyncio.sleep(14)
    await scanner.stop()

    print(f"TOTAL DEVICES: {len(results)}")
    for addr, (name, rssi, svcs, has_mfg) in sorted(results.items()):
        print(f"{addr}  rssi={rssi:5d}  name={name!r:35s}  svcs=[{', '.join(svcs)}]  mfg={has_mfg}")

try:
    asyncio.run(main())
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
