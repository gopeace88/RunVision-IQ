#!/bin/bash
# RunVision-IQ TDD Automation Script
# WSL에서 Windows 시뮬레이터를 사용한 빌드-테스트 자동화

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 경로 설정
PROJECT_DIR="/mnt/d/00.Projects/00.RunVision-IQ"
WIN_PROJECT_DIR="D:\\00.Projects\\00.RunVision-IQ"
SDK_LIN="/home/jhkim/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.3.0-2025-09-22-5813687a0"
SDK_WIN='C:\Users\jinhee\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.3.0-2025-09-22-5813687a0\bin'
DEVICE="fr265"

# 함수 정의
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 1. 빌드
build() {
    print_header "Building RunVision-IQ"

    cd "$PROJECT_DIR"

    local BUILD_FLAGS=""
    if [ "$1" == "--test" ]; then
        BUILD_FLAGS="--unit-test"
        echo "Building with unit tests..."
    else
        echo "Building release..."
    fi

    java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true \
        -jar "$SDK_LIN/bin/monkeybrains.jar" \
        -o bin/RunVisionIQ.prg \
        -f monkey.jungle \
        -y developer_key.der \
        -d "$DEVICE" \
        -l 1 \
        $BUILD_FLAGS \
        2>&1

    if [ $? -eq 0 ]; then
        print_success "Build successful"
        return 0
    else
        print_error "Build failed"
        return 1
    fi
}

# 2. 시뮬레이터 상태 확인 및 시작
ensure_simulator() {
    print_header "Checking Simulator"

    # 시뮬레이터 프로세스 확인
    local sim_running=$(powershell.exe -Command "Get-Process -Name simulator -ErrorAction SilentlyContinue" 2>/dev/null | grep -c "simulator")

    if [ "$sim_running" -gt 0 ]; then
        print_success "Simulator is running"
    else
        print_warning "Starting simulator..."
        powershell.exe -Command "Start-Process '$SDK_WIN\\simulator.exe'" 2>/dev/null
        sleep 5
        print_success "Simulator started"
    fi
}

# 3. 앱 푸시
push_app() {
    print_header "Pushing App to Simulator"

    timeout 60 cmd.exe /C "cd /d ${SDK_WIN} && shell.exe push ${WIN_PROJECT_DIR}\\bin\\RunVisionIQ.prg" 2>&1 | tail -5

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "App pushed successfully"
        return 0
    else
        print_error "Failed to push app"
        return 1
    fi
}

# 4. 테스트 실행
run_tests() {
    print_header "Running Unit Tests"

    local output=$(timeout 60 cmd.exe /C "cd /d ${SDK_WIN} && monkeydo.bat ${WIN_PROJECT_DIR}\\bin\\RunVisionIQ.prg ${DEVICE} /t" 2>&1)

    echo "$output"

    # 테스트 결과 파싱
    local pass_count=$(echo "$output" | grep -c "PASS" || true)
    local fail_count=$(echo "$output" | grep -c "FAIL" || true)

    echo ""
    echo -e "${BLUE}Test Results:${NC}"
    echo -e "  ${GREEN}PASS: $pass_count${NC}"
    echo -e "  ${RED}FAIL: $fail_count${NC}"

    if [ "$fail_count" -gt 0 ]; then
        return 1
    fi
    return 0
}

# 5. 전체 TDD 사이클
tdd_cycle() {
    print_header "TDD Cycle"

    # 빌드
    if ! build "$1"; then
        return 1
    fi

    # 시뮬레이터 확인
    ensure_simulator

    # 앱 푸시
    if ! push_app; then
        return 1
    fi

    # 테스트가 요청된 경우에만 실행
    if [ "$1" == "--test" ]; then
        run_tests
    fi

    print_success "TDD cycle completed"
}

# 메인
main() {
    case "${1:-}" in
        build)
            build "${2:-}"
            ;;
        push)
            ensure_simulator
            push_app
            ;;
        test)
            run_tests
            ;;
        cycle)
            tdd_cycle "${2:-}"
            ;;
        *)
            echo "Usage: $0 {build|push|test|cycle} [--test]"
            echo ""
            echo "Commands:"
            echo "  build [--test]  - Build the project (with optional unit tests)"
            echo "  push            - Push app to simulator"
            echo "  test            - Run unit tests"
            echo "  cycle [--test]  - Full TDD cycle (build + push + optional test)"
            echo ""
            echo "Examples:"
            echo "  $0 build           # Release build"
            echo "  $0 build --test    # Test build"
            echo "  $0 cycle           # Build and push"
            echo "  $0 cycle --test    # Build, push, and test"
            ;;
    esac
}

main "$@"
