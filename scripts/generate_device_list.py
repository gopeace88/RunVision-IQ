#!/usr/bin/env python3
"""
generate_device_list.py
-----------------------
manifest.xml에서 호환 기기 목록을 파싱해 CONNECT-IQ-STORE-LISTING.md를 자동 업데이트.

【호환 기기 판단 기준 3가지】
  1. ActiveLook manifest — 동일 방식 AR 글래스 실사용 검증 목록 (최우선)
  2. SDK 기반 — BLE Central + Running 액티비티 + DataField 모두 지원
  3. 출시 연도 — ActiveLook 미포함 기기는 2019년 이전 출시 시 제거
  상세: runvision-iq/Docs/BLE-CENTRAL-COMPATIBILITY.md

【Single Source of Truth 흐름】
  manifest.xml  →  이 스크립트  →  CONNECT-IQ-STORE-LISTING.md
  (product IDs)    (파싱/매핑)     (EN/KO 설명, Compatible Devices 테이블)

사용법:
    cd runvision-iq
    python3 scripts/generate_device_list.py          # 파일 업데이트
    python3 scripts/generate_device_list.py --dry-run  # 미리보기만

기기 추가 시:
  1. BLE-CENTRAL-COMPATIBILITY.md에 근거 기록
  2. manifest.xml에 <iq:product id="..."/> 추가
  3. DEVICE_DISPLAY / SERIES_GROUPS에 매핑 추가
  4. 이 스크립트 실행
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# ─── 경로 설정 ─────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
MANIFEST_PATH = REPO_ROOT / "manifest.xml"
STORE_LISTING_PATH = REPO_ROOT.parent / "Docs" / "runvision-iq" / "CONNECT-IQ-STORE-LISTING.md"

# ─── SDK Product ID → 마케팅 표시명 매핑 ────────────────────────────────────────

DEVICE_DISPLAY = {
    # Forerunner
    "fr55":      "55",
    "fr165":     "165",
    "fr165m":    "165 Music",
    "fr245":     "245",
    "fr245m":    "245 Music",
    "fr255":     "255",
    "fr255m":    "255 Music",
    "fr255s":    "255S",
    "fr255sm":   "255S Music",
    "fr265":     "265",
    "fr265s":    "265S",
    "fr57042mm": "570 (42mm)",
    "fr57047mm": "570 (47mm)",
    "fr745":     "745",
    "fr945":     "945",
    "fr945lte":  "945 LTE",
    "fr955":     "955",
    "fr965":     "965",
    "fr970":     "970",

    # Fenix 5 Plus
    "fenix5plus":  "5 Plus",
    "fenix5splus": "5S Plus",
    "fenix5xplus": "5X Plus",

    # Fenix 6
    "fenix6":    "6",
    "fenix6s":   "6S",
    "fenix6pro":  "6 Pro",
    "fenix6spro": "6S Pro",
    "fenix6xpro": "6X Pro",

    # Fenix 7
    "fenix7":           "7",
    "fenix7s":          "7S",
    "fenix7x":          "7X",
    "fenix7pro":        "7 Pro",
    "fenix7spro":       "7S Pro",
    "fenix7xpro":       "7X Pro",
    "fenix7pronowifi":  "7 Pro (No WiFi)",
    "fenix7xpronowifi": "7X Pro (No WiFi)",

    # Fenix 8
    "fenix843mm":     "8 AMOLED (43mm)",
    "fenix847mm":     "8 AMOLED (47mm)",
    "fenix8solar47mm": "8 Solar (47mm)",
    "fenix8solar51mm": "8 Solar (51mm)",
    "fenix8pro47mm":  "8 Pro",
    "fenix8pro51mm":  "8 Pro (51mm)",
    "fenixe":         "E",

    # Epix
    "epix2":        "2",
    "epix2pro42mm": "2 Pro (42mm)",
    "epix2pro47mm": "2 Pro (47mm)",
    "epix2pro51mm": "2 Pro (51mm)",

    # Enduro
    "enduro":  "1",
    "enduro2": "2",
    "enduro3": "3",

    # Venu (Gen1/venusqm 제외: DataField 미지원 또는 ActiveLook 미포함 구형)
    "venu2":     "2",
    "venu2s":    "2S",
    "venu2plus": "2 Plus",
    "venu3":     "3",
    "venu3s":    "3S",
    "venusq2m":  "Sq. 2 Music",
    "venu441mm": "4 (41mm)",
    "venu445mm": "4 (45mm)",

    # Vivoactive (3/4 시리즈 제외: ActiveLook 미포함 구형)
    "vivoactive5": "5",
    "vivoactive6": "6",

    # Instinct
    "instinct2":              "2",
    "instinct2s":             "2S",
    "instinct2x":             "2X",
    "instinct3amoled45mm":    "3 AMOLED (45mm)",
    "instinct3amoled50mm":    "3 AMOLED (50mm)",
    "instinct3solar45mm":     "3 Solar (45mm)",
    "instinct3solar50mm":     "3 Solar (50mm)",
    "instinctcrossover":      "Crossover",
    "instinctcrossoveramoled": "Crossover AMOLED",
    "instincte40mm":          "E (40mm)",
    "instincte45mm":          "E (45mm)",

    # MARQ
    "marq2":          "Gen 2",
    "marq2aviator":   "Aviator (Gen 2)",
    "marqadventurer": "Adventurer",
    "marqathlete":    "Athlete",
    "marqaviator":    "Aviator",
    "marqcaptain":    "Captain",
    "marqcommander":  "Commander",
    "marqdriver":     "Driver",
    "marqexpedition": "Expedition",
    "marqgolfer":     "Golfer",

    # Descent (다이빙 전용이나 BLE Central 지원, 러닝 모드 있음)
    "descentmk2":    "Mk2/Mk2i",
    "descentmk2s":   "Mk2S",
    "descentmk343mm": "Mk3/Mk3i (43mm)",
    "descentmk351mm": "Mk3i (51mm)",

    # D2 (항공용이나 Fenix급 멀티스포츠, 러닝 모드 있음)
    "d2airx10": "Air X10",
    "d2mach1":  "Mach 1",

    # Approach (골프 전용이나 Watches/Wearables, 러닝 모드 있음)
    "approachs7042mm": "S70 (42mm)",
    "approachs7047mm": "S70 (47mm)",

    # Venu X1 (직사각형 디스플레이)
    "venux1": "X1",
}

# ─── 시리즈 그룹 정의 (표시 순서) ───────────────────────────────────────────────

SERIES_GROUPS = [
    ("Forerunner",  [
        "fr55", "fr165", "fr165m", "fr245", "fr245m",
        "fr255", "fr255m", "fr255s", "fr255sm",
        "fr265", "fr265s", "fr57042mm", "fr57047mm",
        "fr745", "fr945", "fr945lte",
        "fr955", "fr965", "fr970",
    ]),
    ("fēnix® 5 Plus", ["fenix5plus", "fenix5splus", "fenix5xplus"]),
    ("fēnix® 6",     ["fenix6", "fenix6s", "fenix6pro", "fenix6spro", "fenix6xpro"]),
    ("fēnix® 7",     [
        "fenix7", "fenix7s", "fenix7x",
        "fenix7pro", "fenix7spro", "fenix7xpro",
        "fenix7pronowifi", "fenix7xpronowifi",
    ]),
    ("fēnix® 8",     [
        "fenix843mm", "fenix847mm",
        "fenix8solar47mm", "fenix8solar51mm",
        "fenix8pro47mm", "fenix8pro51mm", "fenixe",
    ]),
    ("epix™",        ["epix2", "epix2pro42mm", "epix2pro47mm", "epix2pro51mm"]),
    ("Enduro™",      ["enduro", "enduro2", "enduro3"]),
    ("Venu®",        [
        "venu2", "venu2s", "venu2plus",
        "venu3", "venu3s", "venusq2m",
        "venu441mm", "venu445mm", "venux1",
    ]),
    ("vívoactive®",  ["vivoactive5", "vivoactive6"]),
    ("Instinct®",    [
        "instinct2", "instinct2s", "instinct2x",
        "instinct3amoled45mm", "instinct3amoled50mm",
        "instinct3solar45mm", "instinct3solar50mm",
        "instinctcrossover", "instinctcrossoveramoled",
        "instincte40mm", "instincte45mm",
    ]),
    ("MARQ®",        [
        "marq2", "marq2aviator",
        "marqadventurer", "marqathlete", "marqaviator",
        "marqcaptain", "marqcommander", "marqdriver",
        "marqexpedition", "marqgolfer",
    ]),
    ("Descent™",     ["descentmk2", "descentmk2s", "descentmk343mm", "descentmk351mm"]),
    ("D2™",          ["d2airx10", "d2mach1"]),
    ("Approach®",    ["approachs7042mm", "approachs7047mm"]),
]

# ─── manifest.xml 파싱 ──────────────────────────────────────────────────────────

def parse_manifest(manifest_path: Path) -> list[str]:
    """manifest.xml에서 활성 product ID 목록 반환 (주석 처리된 항목 제외)."""
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    ns = {"iq": "http://www.garmin.com/xml/connectiq"}
    products = root.findall(".//iq:product", ns)
    return [p.get("id") for p in products if p.get("id")]


# ─── 텍스트 생성 ────────────────────────────────────────────────────────────────

def build_store_text(active_ids: set[str]) -> dict:
    """스토어 설명용 텍스트 블록 생성 (English / Korean)."""
    lines_en = []
    lines_ko = []
    total = 0

    for series_name, ids in SERIES_GROUPS:
        present = [pid for pid in ids if pid in active_ids]
        if not present:
            continue
        names = [DEVICE_DISPLAY.get(pid, pid) for pid in present]
        total += len(present)
        lines_en.append(f"{series_name}: {', '.join(names)}")
        lines_ko.append(f"{series_name}: {', '.join(names)}")

    header_en = f"[ SUPPORTED DEVICES - {total} Models ]"
    header_ko = f"[ 지원 기기 - {total}개 모델 ]"

    block_en = header_en + "\n\n" + "\n".join(lines_en)
    block_ko = header_ko + "\n\n" + "\n".join(lines_ko)

    return {"total": total, "en": block_en, "ko": block_ko}


def build_compatibility_table(active_ids: set[str]) -> str:
    """## Compatible Devices 섹션용 Markdown 테이블 생성."""
    total = sum(
        len([pid for pid in ids if pid in active_ids])
        for _, ids in SERIES_GROUPS
    )
    lines = [
        f"## Compatible Devices ({total} models in manifest.xml)",
        "",
        "<!-- AUTO-GENERATED: do not edit manually. Run scripts/generate_device_list.py -->",
        "",
        "| Series | Models |",
        "|--------|--------|",
    ]

    for series_name, ids in SERIES_GROUPS:
        present = [pid for pid in ids if pid in active_ids]
        if not present:
            continue
        names = [DEVICE_DISPLAY.get(pid, pid) for pid in present]
        lines.append(f"| **{series_name}** | {', '.join(names)} |")

    lines += [
        "",
        "> 기준 문서: `runvision-iq/Docs/BLE-CENTRAL-COMPATIBILITY.md`",
        "> AUTO-GENERATED — 직접 수정 금지. `python3 scripts/generate_device_list.py` 실행으로 업데이트.",
    ]
    return "\n".join(lines)


# ─── CONNECT-IQ-STORE-LISTING.md 업데이트 ───────────────────────────────────────

def update_store_listing(path: Path, store: dict, table: str, dry_run: bool):
    content = path.read_text(encoding="utf-8")

    # 1. English 설명 내 SUPPORTED DEVICES 블록 교체
    content = re.sub(
        r"\[ SUPPORTED DEVICES - \d+ Models \].*?(?=\n\n\[)",
        store["en"],
        content,
        flags=re.DOTALL,
    )

    # 2. Korean 설명 내 지원 기기 블록 교체
    content = re.sub(
        r"\[ 지원 기기 - \d+개 모델 \].*?(?=\n\n\[)",
        store["ko"],
        content,
        flags=re.DOTALL,
    )

    # 3. ## Compatible Devices 섹션 교체
    content = re.sub(
        r"## Compatible Devices.*?(?=\n---)",
        table + "\n",
        content,
        flags=re.DOTALL,
    )

    if dry_run:
        print("=== DRY RUN: 변경 내용 미리보기 ===\n")
        print(content)
    else:
        path.write_text(content, encoding="utf-8")
        print(f"✅ 업데이트 완료: {path}")


# ─── 메인 ───────────────────────────────────────────────────────────────────────

def main():
    dry_run = "--dry-run" in sys.argv

    print(f"📂 manifest.xml: {MANIFEST_PATH}")
    active_ids = set(parse_manifest(MANIFEST_PATH))
    print(f"✅ 활성 기기 수: {len(active_ids)}개\n")

    # 인식 못한 ID 경고
    known_ids = {pid for _, ids in SERIES_GROUPS for pid in ids}
    unknown = active_ids - known_ids
    if unknown:
        print(f"⚠️  매핑 없는 product ID (DEVICE_DISPLAY에 추가 필요): {unknown}\n")

    store = build_store_text(active_ids)
    table = build_compatibility_table(active_ids)

    print("─── English Store Text ───────────────────────────")
    print(store["en"])
    print("\n─── Korean Store Text ────────────────────────────")
    print(store["ko"])
    print(f"\n총 {store['total']}개 모델\n")

    print(f"📝 업데이트 대상: {STORE_LISTING_PATH}")
    update_store_listing(STORE_LISTING_PATH, store, table, dry_run)


if __name__ == "__main__":
    main()
