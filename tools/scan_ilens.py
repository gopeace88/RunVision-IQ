#!/usr/bin/env python3
"""
iLens BLE Advertising Data Scanner
Windows에서 실행: python scan_ilens.py

새 펌웨어의 Advertising Packet 구조를 분석합니다.
"""

import asyncio
from bleak import BleakScanner

async def scan_for_ilens():
    print("Scanning for BLE devices (10 seconds)...")
    print("=" * 60)

    devices = await BleakScanner.discover(
        timeout=10.0,
        return_adv=True
    )

    for device, adv_data in devices.values():
        name = device.name or adv_data.local_name or "Unknown"

        # Show all devices, highlight iLens
        is_ilens = 'ilens' in name.lower() if name else False
        prefix = ">>> " if is_ilens else "    "

        print(f"\n{prefix}Device: {name}")
        print(f"{prefix}Address: {device.address}")
        print(f"{prefix}RSSI: {adv_data.rssi} dBm")

        # Service UUIDs
        if adv_data.service_uuids:
            print(f"{prefix}Service UUIDs: {adv_data.service_uuids}")

        # Manufacturer Data (CRITICAL for debugging)
        if adv_data.manufacturer_data:
            print(f"{prefix}Manufacturer Data:")
            for company_id, data in adv_data.manufacturer_data.items():
                print(f"{prefix}  Company ID: 0x{company_id:04X}")
                # Hex dump
                hex_str = ' '.join(f'{b:02X}' for b in data)
                print(f"{prefix}  Data (hex): {hex_str}")
                # ASCII (printable chars only)
                ascii_str = ''.join(chr(b) if 0x20 <= b <= 0x7E else '.' for b in data)
                print(f"{prefix}  Data (ascii): {ascii_str}")
                # Positions for RunVision-IQ debugging
                print(f"{prefix}  Data length: {len(data)} bytes")
                if len(data) >= 8:
                    name_candidate = ''.join(chr(b) if 0x20 <= b <= 0x7E else '' for b in data[0:8])
                    print(f"{prefix}  Position 0-7: {name_candidate}")

        # Service Data
        if adv_data.service_data:
            print(f"{prefix}Service Data:")
            for uuid, data in adv_data.service_data.items():
                hex_str = ' '.join(f'{b:02X}' for b in data)
                print(f"{prefix}  {uuid}: {hex_str}")

        if is_ilens:
            print(f"\n{prefix}*** iLens DEVICE FOUND! ***")
            print("=" * 60)

if __name__ == "__main__":
    print("iLens BLE Scanner")
    print("Run this on Windows (not WSL2)")
    print("Install: pip install bleak")
    print()
    asyncio.run(scan_for_ilens())
