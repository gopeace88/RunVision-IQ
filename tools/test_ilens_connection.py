#!/usr/bin/env python3
"""
iLens Direct Connection Test
MAC: E0:79:C4:C2:72:EC
"""

import asyncio
from bleak import BleakClient, BleakScanner

ILENS_MAC = "E0:79:C4:C2:72:EC"

# iLens UUIDs
ILENS_SERVICE = "4b329cf2-3816-498c-8453-ee8798502a08"
EXERCISE_CHAR = "c259c1bd-18d3-c348-b88d-5447aea1b615"
CONFIG_SERVICE = "58211c97-482a-2808-2d3e-228405f1e749"
CURRENT_TIME_CHAR = "54ac7f82-eb87-aa4e-0154-a71d80471e6e"
BATTERY_CHAR = "33bd4a32-f763-0391-2820-55610f999aef"

async def main():
    print("=" * 60)
    print(f"iLens Direct Connection Test")
    print(f"Target: {ILENS_MAC}")
    print("=" * 60)

    print("\n[1] Connecting to iLens...")

    try:
        async with BleakClient(ILENS_MAC, timeout=15.0) as client:
            print(f"[2] Connected: {client.is_connected}")

            print("\n[3] Discovering services...")
            services = client.services

            print("\n" + "=" * 60)
            print("DISCOVERED SERVICES AND CHARACTERISTICS")
            print("=" * 60)

            ilens_service_found = False
            config_service_found = False

            for service in services:
                service_uuid = service.uuid.lower()

                # Mark known services
                label = ""
                if ILENS_SERVICE.lower() in service_uuid:
                    label = " <<< iLens Exercise Service"
                    ilens_service_found = True
                elif CONFIG_SERVICE.lower() in service_uuid:
                    label = " <<< Device Config Service"
                    config_service_found = True
                elif "180a" in service_uuid:
                    label = " (Device Information)"
                elif "1800" in service_uuid:
                    label = " (Generic Access)"
                elif "1801" in service_uuid:
                    label = " (Generic Attribute)"

                print(f"\nService: {service.uuid}{label}")

                for char in service.characteristics:
                    props = ', '.join(char.properties)
                    char_uuid = char.uuid.lower()

                    # Mark known characteristics
                    char_label = ""
                    if EXERCISE_CHAR.lower() in char_uuid:
                        char_label = " <<< Exercise Data"
                    elif CURRENT_TIME_CHAR.lower() in char_uuid:
                        char_label = " <<< Current Time"
                    elif BATTERY_CHAR.lower() in char_uuid:
                        char_label = " <<< Battery"

                    print(f"  Char: {char.uuid} [{props}]{char_label}")

            print("\n" + "=" * 60)
            print("SUMMARY")
            print("=" * 60)
            print(f"iLens Exercise Service: {'FOUND' if ilens_service_found else 'NOT FOUND'}")
            print(f"Device Config Service: {'FOUND' if config_service_found else 'NOT FOUND'}")

            # Try to read battery
            if config_service_found:
                print("\n[4] Trying to read battery level...")
                try:
                    battery = await client.read_gatt_char(BATTERY_CHAR)
                    print(f"Battery: {battery[0]}%")
                except Exception as e:
                    print(f"Battery read failed: {e}")

            # Try to write test data to exercise char
            if ilens_service_found:
                print("\n[5] Trying to write test data to Exercise characteristic...")
                # Simple test packet: Metric ID 0x07 (Velocity) + Value 0 (4 bytes)
                test_packet = bytes([0x07, 0x00, 0x00, 0x00, 0x00])
                try:
                    await client.write_gatt_char(EXERCISE_CHAR, test_packet, response=True)
                    print("Write SUCCESS!")
                except Exception as e:
                    print(f"Write failed: {e}")

            print("\n[6] Connection test complete!")

    except Exception as e:
        print(f"\nConnection failed: {e}")
        print("\nPossible causes:")
        print("- iLens is connected to another device (phone app)")
        print("- iLens is in hibernation mode")
        print("- Bluetooth adapter issue")

if __name__ == "__main__":
    asyncio.run(main())
