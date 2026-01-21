# BLE Central Compatibility for RunVision-IQ

## Overview

RunVision-IQ requires **BLE Central** (Toybox.BluetoothLowEnergy) capability to connect to iLens/rLens AR glasses. Not all Garmin devices support this feature.

## How to Check BLE Central Support

### 1. Official Garmin API Documentation
The definitive source for BLE Central support:
- https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html

### 2. ActiveLook Reference
ActiveLook (similar AR glasses project) maintains a tested device list:
- https://github.com/ActiveLook/Garmin-Datafield-sample-code

### 3. SDK Device Simulator
Build for a device and check if BLE APIs are available in the simulator.

---

## Three Device Lists Comparison

### Summary Table

| Source | Total | Focus | Last Updated |
|--------|-------|-------|--------------|
| **Garmin Official** | 120+ | All BLE Central devices | 2026-01 |
| **ActiveLook** | 77 | Cycling + Premium watches | 2025-07 |
| **RunVision-IQ** | 84 | Running/Fitness | 2026-01-21 |

---

## 1. Garmin Official BLE Central Device List (120+ devices)

Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html

### Watches - Running/Fitness
| Series | Device IDs |
|--------|------------|
| **Forerunner** | fr55, fr165, fr165m, fr245, fr245m, fr255, fr255m, fr255s, fr255sm, fr265, fr265s, fr57042mm, fr57047mm, fr645m, fr745, fr945, fr945lte, fr955, fr965, fr970 |
| **Fenix 5+** | fenix5plus, fenix5splus, fenix5xplus |
| **Fenix 6** | fenix6, fenix6s, fenix6pro, fenix6spro, fenix6xpro |
| **Fenix 7** | fenix7, fenix7s, fenix7x, fenix7pro, fenix7spro, fenix7xpro, fenix7pronowifi, fenix7xpronowifi |
| **Fenix 8** | fenix843mm, fenix847mm, fenix8solar47mm, fenix8solar51mm, fenix8pro47mm, fenix8pro51mm, fenixe |
| **Epix** | epix2, epix2pro42mm, epix2pro47mm, epix2pro51mm |
| **Enduro** | enduro, enduro2, enduro3 |
| **Venu** | venu, venu2, venu2s, venu2plus, venu3, venu3s, venu441mm, venu445mm, venusqm, venusq2m, venux1, venumercedesbenz |
| **Vivoactive** | vivoactive3m, vivoactive3mlte, vivoactive4, vivoactive4s, vivoactive5, vivoactive6 |
| **Instinct 2** | instinct2, instinct2s, instinct2x + Solar/Tactical variants |
| **Instinct 3** | instinct3amoled45mm, instinct3amoled50mm, instinct3solar45mm, instinct3solar50mm |
| **Instinct Other** | instinctcrossover, instinctcrossoveramoled, instincte40mm, instincte45mm |
| **MARQ Gen 1** | marqadventurer, marqathlete, marqaviator, marqcaptain, marqcommander, marqdriver, marqexpedition, marqgolfer |
| **MARQ Gen 2** | marq2, marq2aviator |

### Watches - Specialty (Not in RunVision-IQ)
| Series | Device IDs | Purpose |
|--------|------------|---------|
| **D2** | d2air, d2airx10, d2x15, d2mach1, d2mach2 | Aviation |
| **Descent** | descentg1, descentg1solar, descentg2, descentmk2, descentmk2i, descentmk2s, descentmk343mm, descentmk3i43mm, descentmk3i51mm | Diving |
| **Approach** | approachs50, approachs7042mm, approachs7047mm | Golf |
| **Marvel/SW** | captainmarvel, darthvader, firstavenger, rey | Limited Edition |

### Cycling Computers (Not in RunVision-IQ)
| Series | Device IDs |
|--------|------------|
| **Edge** | edge530, edge540, edge540solar, edge550, edge830, edge840, edge840solar, edge850, edge1030, edge1030plus, edge1040, edge1040solar, edge1050, edgeexplore, edgeexplore2, edgemtb |

### Handheld GPS (Not in RunVision-IQ)
| Series | Device IDs |
|--------|------------|
| **GPSMAP** | gpsmap66s, gpsmap66i, gpsmap66sr, gpsmap66st, gpsmap67, gpsmap67i, gpsmapH1, gpsmapH1iPlus |
| **Montana** | montana7 series |
| **eTrex** | etrextouch |

---

## 2. ActiveLook Device List (77 devices)

Source: https://github.com/ActiveLook/Garmin-Datafield-sample-code/blob/master/manifest.xml

### Included Devices
| Series | Count | Device IDs |
|--------|-------|------------|
| **Forerunner** | 17 | fr165, fr165m, fr245m, fr255, fr255m, fr255s, fr255sm, fr265, fr265s, fr57042mm, fr57047mm, fr745, fr945, fr945lte, fr955, fr965, fr970 |
| **Fenix** | 20 | fenix5plus, fenix5splus, fenix5xplus, fenix6pro, fenix6spro, fenix6xpro, fenix7, fenix7s, fenix7x, fenix7pro, fenix7spro, fenix7xpro, fenix7pronowifi, fenix7xpronowifi, fenix843mm, fenix847mm, fenix8pro47mm, fenix8solar47mm, fenix8solar51mm, fenixe |
| **Epix** | 4 | epix2, epix2pro42mm, epix2pro47mm, epix2pro51mm |
| **Enduro** | 1 | enduro3 |
| **Venu** | 6 | venu2, venu2s, venu2plus, venu3, venu3s, venusq2m |
| **Vivoactive** | 2 | vivoactive5, vivoactive6 |
| **MARQ** | 10 | marq2, marq2aviator, marqadventurer, marqathlete, marqaviator, marqcaptain, marqcommander, marqdriver, marqexpedition, marqgolfer |
| **Edge** | 10 | edge530, edge540, edge830, edge840, edge1030, edge1030plus, edge1040, edge1050, edgeexplore, edgeexplore2 |
| **D2** | 2 | d2airx10, d2mach1 |
| **Descent** | 4 | descentmk2, descentmk2s, descentmk343mm, descentmk351mm |
| **Approach** | 2 | approachs7042mm, approachs7047mm |
| **Venu X** | 1 | venux1 |

### NOT in ActiveLook (Missing)
- ❌ FR55, FR245, FR645M (entry-level runners)
- ❌ Fenix 6 non-Pro (fenix6, fenix6s)
- ❌ Enduro 1, Enduro 2
- ❌ Venu (original), Venu 4 series, Venu Sq Music
- ❌ Vivoactive 3/4 series
- ❌ **Instinct series (entire)** - 11 devices
- ❌ fenix8pro51mm

---

## 3. RunVision-IQ Device List (84 devices)

### Included Devices
| Series | Count | Device IDs |
|--------|-------|------------|
| **Forerunner** | 20 | fr55, fr165, fr165m, fr245, fr245m, fr255, fr255m, fr255s, fr255sm, fr265, fr265s, fr57042mm, fr57047mm, fr645m, fr745, fr945, fr945lte, fr955, fr965, fr970 |
| **Fenix 5+** | 3 | fenix5plus, fenix5splus, fenix5xplus |
| **Fenix 6** | 5 | fenix6, fenix6s, fenix6pro, fenix6spro, fenix6xpro |
| **Fenix 7** | 6 | fenix7, fenix7s, fenix7x, fenix7pro, fenix7spro, fenix7xpro |
| **Fenix 8** | 7 | fenix843mm, fenix847mm, fenix8solar47mm, fenix8solar51mm, fenix8pro47mm, fenix8pro51mm, fenixe |
| **Epix** | 4 | epix2, epix2pro42mm, epix2pro47mm, epix2pro51mm |
| **Enduro** | 2 | enduro, enduro3 |
| **Venu** | 10 | venu, venu2, venu2s, venu2plus, venu3, venu3s, venusqm, venusq2m, venu441mm, venu445mm |
| **Vivoactive** | 6 | vivoactive3m, vivoactive3mlte, vivoactive4, vivoactive4s, vivoactive5, vivoactive6 |
| **Instinct** | 11 | instinct2, instinct2s, instinct2x, instinct3amoled45mm, instinct3amoled50mm, instinct3solar45mm, instinct3solar50mm, instinctcrossover, instinctcrossoveramoled, instincte40mm, instincte45mm |
| **MARQ** | 10 | marq2, marq2aviator, marqadventurer, marqathlete, marqaviator, marqcaptain, marqcommander, marqdriver, marqexpedition, marqgolfer |

### NOT in RunVision-IQ (Excluded)
| Category | Devices | Reason |
|----------|---------|--------|
| **D2 Series** | d2air, d2airx10, d2mach1, d2mach2 | Aviation-focused |
| **Descent Series** | descentg1, descentg2, descentmk2, descentmk2s, descentmk343mm, descentmk3i51mm | Diving-focused |
| **Edge Series** | All 16 devices | Cycling computers |
| **Approach** | approachs50, approachs7042mm, approachs7047mm | Golf |
| **GPSMAP/Montana** | All handheld devices | Navigation, not wearable |
| **Limited Edition** | Marvel/Star Wars editions | Rare, same as base model |

---

## Detailed Comparison: RunVision-IQ vs ActiveLook

### RunVision-IQ Only (Not in ActiveLook) - 27 devices

| Series | Devices | Reason for Inclusion |
|--------|---------|---------------------|
| **Forerunner** | fr55, fr245, fr645m | Entry/mid-level runners - large user base |
| **Fenix 6** | fenix6, fenix6s | Non-Pro still popular |
| **Fenix 7** | - | (All included in both) |
| **Fenix 8** | fenix8pro51mm | Larger size option |
| **Enduro** | enduro | Original ultra running watch |
| **Venu** | venu, venu441mm, venu445mm, venusqm | Original Venu + Venu 4 series |
| **Vivoactive** | vivoactive3m, vivoactive3mlte, vivoactive4, vivoactive4s | Fitness watch users |
| **Instinct** | **All 11 devices** | Trail runners, outdoor athletes |

### ActiveLook Only (Not in RunVision-IQ) - 20 devices

| Series | Devices | Reason for Exclusion |
|--------|---------|---------------------|
| **Edge** | 10 devices | Cycling computers - no wrist HR |
| **D2** | d2airx10, d2mach1 | Aviation |
| **Descent** | 4 devices | Diving |
| **Approach** | 2 devices | Golf |
| **Fenix 7** | fenix7pronowifi, fenix7xpronowifi | NoWifi variants (rare) |
| **Venu X** | venux1 | New model, not yet tested |

### Strategic Differences

| Aspect | RunVision-IQ | ActiveLook |
|--------|--------------|------------|
| **Primary Target** | Runners | Cyclists |
| **Instinct Support** | ✅ Full (11 devices) | ❌ None |
| **Edge Support** | ❌ None | ✅ Full (10 devices) |
| **Entry-Level FR** | ✅ FR55, FR245 | ❌ Missing |
| **Vivoactive 3/4** | ✅ Included | ❌ Missing |

---

## Version History

| Date | Change |
|------|--------|
| 2026-01-21 | Initial documentation |
| 2026-01-21 | Removed D2/Descent series (10 devices) |
| 2026-01-21 | Added three-way comparison (Official/ActiveLook/RunVision-IQ) |
