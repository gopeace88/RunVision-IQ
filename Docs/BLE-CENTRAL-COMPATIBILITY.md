# RunVision-IQ BLE Central Compatibility

> ⭐ **이 문서는 RunVision-IQ 호환 기기의 기준 문서입니다.**
> 기기 추가/제거 시 반드시 이 문서를 먼저 업데이트하고, manifest.xml에 반영하세요.

---

## 판단 기준 (필수 참조)

기기 호환성을 판단할 때 아래 3가지 기준을 순서대로 적용합니다.

### 기준 1 — ActiveLook Manifest (최우선 검증 레퍼런스)

> ActiveLook은 동일한 BLE Central API를 사용해 AR 글래스와 연동하는 실제 출시 제품.
> 실사용 사용자들이 검증한 목록이므로 RunVision-IQ의 가장 신뢰할 수 있는 기준점.

- ActiveLook manifest에 포함된 기기(러닝/피트니스 관련) → **무조건 포함**
- 출처: https://github.com/ActiveLook/Garmin-Datafield-sample-code/blob/master/manifest.xml

### 기준 2 — SDK 기반 검증

기기가 Connect IQ SDK에서 다음 세 가지를 **모두** 지원해야 함:
1. `Toybox.BluetoothLowEnergy` — BLE Central 역할 (iLens/rLens 연결에 필수)
2. Running 액티비티 지원 — DataField가 실행되는 활동 컨텍스트
3. DataField 앱 타입 지원 — 앱 자체가 설치/실행 가능해야 함

> ⚠️ 공식 Garmin BLE Central 문서 목록은 참고용이며 완전하지 않음.
> Venu Gen 1이 문서에는 있으나 실제로는 DataField 미지원 사례 확인됨.

### 기준 3 — 출시 연도 안전 기준

> ActiveLook manifest에 포함된 기기 중 가장 오래된 것은 **Fenix 5 Plus (2018년)**.
> ActiveLook에 없는 기기가 이 연도와 같거나 이전 출시라면 안전성을 위해 제거.

- ActiveLook에 없는 기기 + 2019년 이전 출시 → **제거**
- ActiveLook에 없는 기기 + 2021년 이후 출시 → 기준 2 확인 후 포함 가능
- 동일 세대/동일 하드웨어 기기가 ActiveLook에 있으면 포함 가능 (예: fr245m ↔ fr245)

---

## 호환 기기 목록 (77개 활성 — 2026-03-15 기준)

### Tier 1: ActiveLook 실사용 검증 (61개, 러닝/피트니스 관련)

사이클링 컴퓨터(Edge), 항공(D2), 다이빙(Descent), 골프(Approach)는 제외.

| 시리즈 | 수 | Product IDs |
|--------|-----|------------|
| **Forerunner** | 17 | fr165, fr165m, fr245m, fr255, fr255m, fr255s, fr255sm, fr265, fr265s, fr57042mm, fr57047mm, fr745, fr945, fr945lte, fr955, fr965, fr970 |
| **fēnix® 5 Plus** | 3 | fenix5plus, fenix5splus, fenix5xplus |
| **fēnix® 6 Pro** | 3 | fenix6pro, fenix6spro, fenix6xpro |
| **fēnix® 7** | 8 | fenix7, fenix7s, fenix7x, fenix7pro, fenix7spro, fenix7xpro, fenix7pronowifi, fenix7xpronowifi |
| **fēnix® 8** | 6 | fenix843mm, fenix847mm, fenix8pro47mm, fenix8solar47mm, fenix8solar51mm, fenixe |
| **epix™** | 4 | epix2, epix2pro42mm, epix2pro47mm, epix2pro51mm |
| **Enduro™** | 1 | enduro3 |
| **Venu®** | 6 | venu2, venu2s, venu2plus, venu3, venu3s, venusq2m |
| **vívoactive®** | 2 | vivoactive5, vivoactive6 |
| **MARQ®** | 10 | marq2, marq2aviator, marqadventurer, marqathlete, marqaviator, marqcaptain, marqcommander, marqdriver, marqexpedition, marqgolfer |
| **Venu® X** | 1 | venux1 |

### Tier 2: 동일 하드웨어 세대 (ActiveLook 기기와 동일 플랫폼, 3개)

| Product ID | 근거 | 출시 |
|------------|------|------|
| fr245 | fr245m(Music)이 ActiveLook에 포함 — 동일 하드웨어 | 2019 |
| fenix6 | fenix6pro가 ActiveLook에 포함 — 동일 세대 | 2019 |
| fenix6s | fenix6spro가 ActiveLook에 포함 — 동일 세대 | 2019 |

### Tier 3: 신규 기기 (2021년 이후, 기준 2 충족 확인, 13개)

| Product ID | 시리즈 | 출시 | 근거 |
|------------|--------|------|------|
| fr55 | Forerunner 55 | 2021 | 러닝 워치, BLE Central 지원 |
| enduro | Enduro™ (Gen 1) | 2021 | enduro3이 ActiveLook에 포함 — 동일 계열 |
| instinct2 | Instinct® 2 | 2022 | 신형, BLE Central 지원 |
| instinct2s | Instinct® 2S | 2022 | 신형, BLE Central 지원 |
| instinct2x | Instinct® 2X | 2023 | 신형, BLE Central 지원 |
| instinct3amoled45mm | Instinct® 3 AMOLED 45mm | 2024 | 신형 |
| instinct3amoled50mm | Instinct® 3 AMOLED 50mm | 2024 | 신형 |
| instinct3solar45mm | Instinct® 3 Solar 45mm | 2024 | 신형 |
| instinctcrossover | Instinct® Crossover | 2022 | 신형, BLE Central 지원 |
| instinctcrossoveramoled | Instinct® Crossover AMOLED | 2023 | 신형 |
| instincte40mm | Instinct® E 40mm | 2024 | 신형 |
| instincte45mm | Instinct® E 45mm | 2024 | 신형 |
| venu441mm | Venu® 4 41mm | 2024 | 신형, venusq2m이 ActiveLook에 포함 |
| venu445mm | Venu® 4 45mm | 2024 | 신형 |

> **참고**: Tier 3는 14개이지만 enduro가 Tier 1의 enduro3과 같은 계열이므로 실질 신규 13개.

---

## 제외 기기

### ActiveLook 기준 적용 제외 (기준 1+3)

| Product ID | 제외 이유 |
|------------|---------|
| fr645m | ActiveLook 미포함, 2018년 출시, 동일 세대 대응 기기 없음 |
| venu | **DataField 미지원 실사용 확인**, ActiveLook 미포함 |
| venusqm | ActiveLook 미포함, 2020년 출시 (Venu Gen 1과 동일 세대) |
| vivoactive3m | ActiveLook 미포함, 2018년 출시 |
| vivoactive3mlte | ActiveLook 미포함, 2018년 출시 |
| vivoactive4 | ActiveLook 미포함, 2019년 출시 |
| vivoactive4s | ActiveLook 미포함, 2019년 출시 |

### 용도 미해당 제외 (비러닝/비손목착용)

| 카테고리 | 기기 | 이유 |
|----------|------|------|
| **Edge 시리즈** | edge530~edgemtb | 사이클링 컴퓨터 (손목 착용 아님) |
| **D2 시리즈** | d2air, d2airx10, d2x15, d2mach1, d2mach1pro, d2mach2 | 항공 특화 |
| **Descent 시리즈** | descentg1~descentmk3i51mm | 다이빙 특화 |
| **Approach 시리즈** | approachs50, approachs7042mm, approachs7047mm | 골프 특화 |
| **GPSMAP/Montana** | 전체 | 핸드헬드 (손목 착용 아님) |

### SDK 미포함 / 확인 필요

| Product ID | 상태 |
|------------|------|
| fenix8pro51mm | `fenix8pro47mm`이 51mm까지 커버하는지 빌드 테스트 필요 |
| instinct3solar50mm | `instinct3solar45mm`이 커버하는지 빌드 테스트 필요 |
| enduro2 | 2022년 출시, ActiveLook 미포함. Tier 3 추가 검토 가능 |

> **참고**: quatix, tactix, Mercedes-Benz Venu, ForeAthlete 등은 별도 product ID가 아닌
> 기존 fenix/venu/fr 시리즈의 마케팅 별칭(alias)임. manifest 추가 불필요.

---

## Version History

| 날짜 | 변경 내용 |
|------|----------|
| 2026-01-21 | 초기 문서 작성 (Garmin 공식 BLE Central 문서 기반) |
| 2026-03-15 | 공식 스토어 실제 노출 확인 — 문서와 실제 동작 불일치 발견 |
| 2026-03-15 | 판단 기준 3가지 확립 (ActiveLook 우선 / SDK 검증 / 출시연도 안전기준) |
| 2026-03-15 | 전면 재작성: Tier 1/2/3 구조, 77개 활성 (82 → 77, -7 +2) |
| 2026-03-15 | 제거: fr645m, venu(DataField 미지원 확인), venusqm, vivoactive3m/3mlte/4/4s |
| 2026-03-15 | 추가: fenix7pronowifi, fenix7xpronowifi (ActiveLook 포함이나 manifest 누락이었음) |
