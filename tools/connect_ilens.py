#!/usr/bin/env python3
"""
iLens BLE Direct Connection Test
이미 페어링된 iLens에 직접 연결 시도
"""

import asyncio
from bleak import BleakClient, BleakScanner

# iLens UUIDs
ILENS_SERVICE = "4b329cf2-3816-498c-8453-ee8798502a08"
EXERCISE_CHAR = "c259c1bd-18d3-c348-b88d-5447aea1b615"
CONFIG_SERVICE = "58211c97-482a-2808-2d3e-228405f1e749"
CURRENT_TIME_CHAR = "54ac7f82-eb87-aa4e-0154-a71d80471e6e"

async def scan_all_devices():
    """모든 기기 스캔 (이름 없는 기기 포함)"""
    print("Scanning ALL devices for 15 seconds...")
    print("Looking for iLens service UUID in advertisements...\n")

    devices = await BleakScanner.discover(
        timeout=15.0,
        return_adv=True
    )

    ilens_candidates = []

    for device, adv_data in devices.values():
        # Check if iLens service UUID is advertised
        has_ilens_service = False
        if adv_data.service_uuids:
            for uuid in adv_data.service_uuids:
                if ILENS_SERVICE.lower() in uuid.lower():
                    has_ilens_service = True
                    break

        # Check manufacturer data for "iLens"
        has_ilens_name = False
        if adv_data.manufacturer_data:
            for company_id, data in adv_data.manufacturer_data.items():
                ascii_str = ''.join(chr(b) if 0x20 <= b <= 0x7E else '' for b in data)
                if 'ilens' in ascii_str.lower():
                    has_ilens_name = True
                    break

        # Check device name
        name = device.name or adv_data.local_name or ""
        if 'ilens' in name.lower():
            has_ilens_name = True

        if has_ilens_service or has_ilens_name:
            ilens_candidates.append((device, adv_data))
            print(f">>> POTENTIAL iLens: {device.address}")
            print(f"    Name: {name or 'Unknown'}")
            print(f"    RSSI: {adv_data.rssi} dBm")
            if adv_data.service_uuids:
                print(f"    Services: {adv_data.service_uuids}")
            if adv_data.manufacturer_data:
                for cid, data in adv_data.manufacturer_data.items():
                    print(f"    Mfr Data: {' '.join(f'{b:02X}' for b in data)}")
            print()

    if not ilens_candidates:
        print("No iLens devices found in scan.")
        print("\nTrying to connect to known iLens addresses...")

    return ilens_candidates

async def try_connect(address: str):
    """특정 주소로 연결 시도"""
    print(f"\nTrying to connect to {address}...")

    try:
        async with BleakClient(address, timeout=10.0) as client:
            print(f"Connected: {client.is_connected}")

            print("\nDiscovering services...")
            services = client.services

            for service in services:
                print(f"\nService: {service.uuid}")
                for char in service.characteristics:
                    props = ', '.join(char.properties)
                    print(f"  Char: {char.uuid} [{props}]")

            # Check for iLens service
            ilens_found = False
            for service in services:
                if ILENS_SERVICE.lower() in service.uuid.lower():
                    ilens_found = True
                    print(f"\n*** iLens Service FOUND! ***")
                    break

            if not ilens_found:
                print(f"\n*** iLens Service NOT found ***")

            return True

    except Exception as e:
        print(f"Connection failed: {e}")
        return False

async def main():
    print("=" * 60)
    print("iLens Direct Connection Test")
    print("=" * 60)

    # First scan
    candidates = await scan_all_devices()

    if candidates:
        # Try to connect to first candidate
        device, adv = candidates[0]
        await try_connect(device.address)
    else:
        # Manual address input
        print("\nNo iLens found. Enter MAC address manually")
        print("(Check Windows Bluetooth settings for paired iLens)")
        addr = input("MAC Address (e.g., AA:BB:CC:DD:EE:FF): ").strip()
        if addr:
            await try_connect(addr)

if __name__ == "__main__":
    asyncio.run(main())
