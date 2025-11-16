# 소스 코드 리뷰 결과

## 🔍 발견된 문제점

### 1. **프로필 등록 불일치 (중요)**
**위치**: `ILens.mc` 라인 64-66, 279

**문제**:
- `PROFILE_BATTERY_INFO`가 정의되어 있지만 `ILENS_PROFILES` 배열에 포함되지 않음
- 프로필 등록 완료 체크가 `ILENS_PROFILES.size()` (3개)로 되어 있음
- 하지만 실제로는 3개 프로필만 등록하면 됨 (Battery는 선택사항)

**현재 상태**: ✅ 정상 (Battery 프로필은 사용하지 않으므로 제외하는 것이 맞음)

---

### 2. **스캔 재시도 빈도 문제**
**위치**: `RunVisionIQView.mc` 라인 128-133

**문제**:
- `compute()` 함수가 매 초마다 호출되는데, 스캔 재시도 로직이 매 초마다 실행됨
- 너무 빈번한 재시도는 BLE 스택에 부담을 줄 수 있음

**개선 제안**:
```monkey-c
// 재시도 카운터 추가
private var _scanRetryCount as Lang.Number = 0;
private var _lastScanRetryTime as Lang.Number = 0;

// compute()에서
if (_profileReady && _ilens != null && !_isConnected && 
    _scanStatus != "SCANNING" && _scanStatus != "SCAN_ERR") {
    var now = System.getTimer();
    // 5초마다만 재시도
    if (now - _lastScanRetryTime > 5000) {
        addDebugLog("retry:scan");
        ILensBLE.ILens.requestScanning(true);
        _lastScanRetryTime = now;
        _scanRetryCount++;
    }
}
```

---

### 3. **속도 변환 정밀도 손실**
**위치**: `RunVisionIQView.mc` 라인 138, `ILensProtocol.mc` 라인 65

**문제**:
- `speedKmh`를 `toNumber()`로 변환하면 소수점이 손실됨
- iLens 프로토콜은 0.1 km/h 단위를 지원하지만 현재는 정수만 전송

**현재 코드**:
```monkey-c
var speedKmh = (speedMs * 3.6).toNumber();  // 소수점 손실
var packet = ILensProtocol.createVelocityPacket(speedKmh);
```

**개선 제안**:
```monkey-c
// 0.1 km/h 단위로 변환 (예: 15.7 km/h → 157)
var speedKmh = speedMs * 3.6;
var speedTenths = (speedKmh * 10).toNumber();  // 157
var packet = ILensProtocol.createVelocityPacket(speedTenths);
```

**참고**: iLens 프로토콜이 실제로 0.1 단위를 지원하는지 확인 필요

---

### 4. **첫 번째 기기만 연결하는 문제**
**위치**: `RunVisionIQView.mc` 라인 357

**문제**:
- `_devicesFound == 1`일 때만 연결 시도
- 여러 iLens 기기가 있을 때 첫 번째만 연결하고 나머지는 무시

**현재 코드**:
```monkey-c
if (_devicesFound == 1 && _ilens != null && !_isConnected) {
    addDebugLog("connecting...");
    _ilens.connect(scanResult);
}
```

**개선 제안**:
- RSSI 값으로 가장 가까운 기기 선택
- 또는 사용자 설정으로 특정 기기 선택
- 현재는 의도된 동작일 수 있음 (첫 발견 기기 자동 연결)

---

### 5. **에러 처리 부족**
**위치**: `RunVisionIQView.mc` 라인 154-157, 175-178 등

**문제**:
- `writeMetric()` 실패 시 에러 처리가 없음
- 연결이 끊어진 상태에서 전송 시도 시 무시됨

**현재 코드**:
```monkey-c
if (_isConnected && _ilens != null) {
    var packet = ILensProtocol.createVelocityPacket(speedKmh);
    _ilens.writeMetric(packet);  // 실패해도 알 수 없음
}
```

**개선 제안**:
```monkey-c
if (_isConnected && _ilens != null) {
    var packet = ILensProtocol.createVelocityPacket(speedKmh);
    var success = _ilens.writeMetric(packet);
    if (!success) {
        // 연결 끊김 감지 및 재연결 시도
        _isConnected = false;
        _scanStatus = "WRITE_FAIL";
    }
}
```

---

### 6. **타이머 리셋 시 통계 초기화 누락**
**위치**: `RunVisionIQView.mc` 라인 107-115

**문제**:
- `onTimerReset()`에서 `_distanceLabel`, `_timeLabel` 등이 리셋되지 않음

**개선 제안**:
```monkey-c
function onTimerReset() as Void {
    _totalSpeed = 0.0;
    _speedSamples = 0;
    _maxHeartRate = 0;
    _avgSpeedLabel = "---";
    _maxHrLabel = "---";
    _paceLabel = "--:--";
    _distanceLabel = "0.00";  // 추가
    _timeLabel = "0:00";      // 추가
    _speedLabel = "---";      // 추가
    _hrLabel = "---";         // 추가
    _cadenceLabel = "---";    // 추가
}
```

---

### 7. **프로필 등록 실패 처리 없음**
**위치**: `ILens.mc` 라인 272-288

**문제**:
- `onProfileRegister()`에서 `status != STATUS_SUCCESS`일 때 처리 없음
- 프로필 등록 실패 시 무한 대기 상태

**개선 제안**:
```monkey-c
function onProfileRegister(uuid as Toybox.BluetoothLowEnergy.Uuid, status as Toybox.BluetoothLowEnergy.Status) as Void {
    _log("onProfileRegister", [uuid, status, _registeredProfile.size()]);
    if (status == Toybox.BluetoothLowEnergy.STATUS_SUCCESS) {
        // ... 기존 코드 ...
    } else {
        _log("onProfileRegister", ["FAILED", uuid, status]);
        // 에러 처리: delegate에 알림
        _delegate.onBleError(new Toybox.Lang.Exception("Profile registration failed"));
    }
}
```

---

### 8. **디바이스 이름 필터링 개선 필요**
**위치**: `ILens.mc` 라인 316-323

**문제**:
- `find()` 메서드는 부분 문자열 매칭이므로 "iLens-ABC"와 "MyiLens-Device" 모두 매칭됨
- 더 정확한 매칭 필요

**현재 코드**:
```monkey-c
if (deviceName.find("iLens-") != null ||
    deviceName.find("ilens-") != null ||
    deviceName.find("ILENS-") != null) {
    isILens = true;
}
```

**개선 제안**:
```monkey-c
// 정확한 매칭: "iLens-"로 시작하는지 확인
var nameLower = deviceName.toLower();
if (nameLower.find("ilens-") == 0) {  // 시작 위치가 0인지 확인
    isILens = true;
}
```

---

## ✅ 잘 구현된 부분

1. **BLE 프로필 구조**: 3개 프로필로 제한하여 리소스 효율적
2. **에러 복구 로직**: `fixScanState()` 주기적 호출로 스캔 에러 복구
3. **상태 관리**: 명확한 상태 변수와 디버그 로그
4. **프로토콜 구현**: iLens 프로토콜이 정확하게 구현됨
5. **메모리 효율**: 불필요한 객체 생성 최소화

---

## 🔧 권장 수정 사항 (우선순위)

### 높음 (즉시 수정)
1. ✅ 스캔 재시도 빈도 제한 (5초 간격)
2. ✅ 프로필 등록 실패 처리 추가
3. ✅ `onTimerReset()` 완전한 리셋

### 중간 (개선 권장)
4. ⚠️ 속도 정밀도 개선 (0.1 km/h 단위 지원 여부 확인 후)
5. ⚠️ `writeMetric()` 실패 감지 및 처리
6. ⚠️ 디바이스 이름 필터링 정확도 개선

### 낮음 (선택사항)
7. 💡 여러 기기 중 선택 로직 (RSSI 기반)
8. 💡 연결 타임아웃 처리
9. 💡 배터리 레벨 모니터링 (PROFILE_BATTERY 사용)

---

## 📝 추가 확인 사항

1. **iLens 프로토콜 검증**:
   - 속도 단위가 정수인지 0.1 단위인지 확인 필요
   - 문서: "576 × 0.1 km/h = 0x0240" → 0.1 단위 지원하는 것으로 보임

2. **BLE 권한**:
   - `manifest.xml`에 `BluetoothLowEnergy` 권한 있음 ✅

3. **기기 호환성**:
   - `fr165`가 SDK에서 인식되지 않음 (빌드 경고)
   - `fr265`로 빌드하여 테스트 중

---

## 🎯 결론

전체적으로 잘 구현되어 있으나, 몇 가지 개선점이 있습니다:
- **에러 처리 강화** 필요
- **스캔 재시도 빈도 제한** 필요
- **속도 정밀도** 개선 검토 필요

현재 코드는 기본 기능은 동작하지만, 엣지 케이스와 에러 상황에 대한 처리가 부족합니다.

