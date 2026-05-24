#!/usr/bin/env bash
# RunVision-IQ 빌드 — manifest.xml 의 app version 을 source/AppVersion.mc 로 자동 동기화 후 monkeyc 실행.
# 버전은 manifest.xml(iq:application version)에서만 변경하면 됨 → 화면 표시·.iq 파일명 모두 자동 반영.
#
# 사용:
#   ./build.sh            → 단일 기기 .prg (기본 fr165) = bin/RunVisionIQ.prg   (사이드로드/시뮬용)
#   ./build.sh fr265      → 지정 기기 .prg
#   ./build.sh iq         → 전체 기기 릴리즈 .iq = bin/RunVisionIQ-<ver>.iq      (스토어 업로드용)
#
# WSL 네이티브 경로 + Windows monkeyc → powershell.exe(UNC 인지) 경유. cmd.exe 는 UNC cwd 불가.
set -eu
cd "$(dirname "$0")"

# --- manifest 에서 app version(semver) 추출 (스키마 version="3"/"1.0" 과 구분: 3-파트 semver) ---
VER=$(grep -oE 'version="[0-9]+\.[0-9]+\.[0-9]+"' manifest.xml | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
if [ -z "$VER" ]; then
    echo "ERROR: manifest.xml 에서 app version(semver) 추출 실패" >&2
    exit 1
fi

# --- AppVersion.mc 자동 생성 (manifest 단일 출처) ---
cat > source/AppVersion.mc <<EOF
// 자동 생성 파일 — build.sh 가 manifest.xml 의 iq:application version 에서 주입.
// 직접 수정 금지(빌드 시 덮어씌워짐). 버전 변경은 manifest.xml 에서만.
// (Monkey C 는 런타임에 자기 manifest version 을 못 읽어 빌드 타임 주입으로 동기화함.)
module AppVersion {
    const VALUE = "$VER";
}
EOF
echo "[build] AppVersion.mc 동기화: v$VER (manifest 기준)"

# --- monkeyc 경로 ---
SDK="C:\\Users\\jinhee\\AppData\\Roaming\\Garmin\\ConnectIQ\\Sdks\\connectiq-sdk-win-8.4.0-2025-12-03-5122605dc\\bin\\monkeyc.bat"
W=$(wslpath -w "$(pwd)")
JUNGLE="$W\\monkey.jungle"
KEY="$W\\developer_key.der"

if [ "${1:-}" = "iq" ]; then
    OUT="$W\\bin\\RunVisionIQ-$VER.iq"
    echo "[build] 릴리즈 .iq (전체 기기): bin/RunVisionIQ-$VER.iq"
    powershell.exe -NoProfile -Command "& '$SDK' -e -r -o '$OUT' -f '$JUNGLE' -y '$KEY'"
else
    DEV="${1:-fr165}"
    OUT="$W\\bin\\RunVisionIQ.prg"
    echo "[build] 테스트 .prg ($DEV): bin/RunVisionIQ.prg"
    powershell.exe -NoProfile -Command "& '$SDK' -o '$OUT' -f '$JUNGLE' -y '$KEY' -d $DEV -w"
fi
echo "[build] 완료."
