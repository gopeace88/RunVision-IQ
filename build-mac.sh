#!/usr/bin/env bash
# RunVision-IQ 빌드 (macOS) — build.sh(윈도우)의 맥 대응판.
# manifest.xml 의 app version 을 source/AppVersion.mc 로 자동 동기화 후 mac monkeyc 실행.
# 버전은 manifest.xml(iq:application version)에서만 변경 → 화면 표시·.iq 파일명 자동 반영.
#
# 사용:
#   ./build-mac.sh            → 단일 기기 .prg (기본 fr165) = bin/RunVisionIQ-fr165.prg  (사이드로드/시뮬용)
#   ./build-mac.sh venusq2    → 지정 기기 .prg = bin/RunVisionIQ-<기기>.prg
#   ./build-mac.sh iq         → 전체 기기 릴리즈 .iq = bin/RunVisionIQ-<ver>.iq          (스토어 업로드용)
#
# developer_key.der 는 레포 루트(gitignore됨) 또는 ~/.Garmin/ 에서 자동 탐색.
set -eu
cd "$(dirname "$0")"

# --- mac Connect IQ SDK 자동 탐색 (가장 최신 버전) ---
SDK_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"
MONKEYC=$(ls -d "$SDK_DIR"/connectiq-sdk-mac-*/bin/monkeyc 2>/dev/null | sort -V | tail -1 || true)
if [ -z "$MONKEYC" ]; then
    echo "ERROR: mac Connect IQ SDK(monkeyc) 를 찾을 수 없습니다: $SDK_DIR" >&2
    exit 1
fi

# --- developer key 탐색 (레포 루트 우선, 없으면 ~/.Garmin) ---
if [ -f "developer_key.der" ]; then
    KEY="developer_key.der"
elif [ -f "$HOME/.Garmin/developer_key.der" ]; then
    KEY="$HOME/.Garmin/developer_key.der"
else
    echo "ERROR: developer_key.der 없음 (레포 루트 또는 ~/.Garmin/ 에 두세요)" >&2
    exit 1
fi

# --- manifest 에서 app version(semver) 추출 (스키마 version="3" 등과 구분: 3-파트 semver) ---
VER=$(grep -oE 'version="[0-9]+\.[0-9]+\.[0-9]+"' manifest.xml | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ -z "$VER" ]; then
    echo "ERROR: manifest.xml 에서 app version(semver) 추출 실패" >&2
    exit 1
fi

# --- AppVersion.mc 자동 생성 (manifest 단일 출처, build.sh 와 동일 내용) ---
cat > source/AppVersion.mc <<EOF
// 자동 생성 파일 — build.sh 가 manifest.xml 의 iq:application version 에서 주입.
// 직접 수정 금지(빌드 시 덮어씌워짐). 버전 변경은 manifest.xml 에서만.
// (Monkey C 는 런타임에 자기 manifest version 을 못 읽어 빌드 타임 주입으로 동기화함.)
module AppVersion {
    const VALUE = "$VER";
}
EOF
echo "[build] AppVersion.mc 동기화: v$VER (manifest 기준)"
echo "[build] SDK: $MONKEYC"

mkdir -p bin

if [ "${1:-}" = "iq" ]; then
    OUT="bin/RunVisionIQ-$VER.iq"
    echo "[build] 릴리즈 .iq (전체 기기): $OUT"
    "$MONKEYC" -e -r -o "$OUT" -f monkey.jungle -y "$KEY"
else
    DEV="${1:-fr165}"
    OUT="bin/RunVisionIQ-$DEV.prg"
    echo "[build] 테스트 .prg ($DEV): $OUT"
    "$MONKEYC" -o "$OUT" -f monkey.jungle -y "$KEY" -d "$DEV" -w
fi
echo "[build] 완료: $OUT"
