using Toybox.Application;
using Toybox.Activity;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.Time.Gregorian;

// using ILensBLE;  // FR55 호환성: Legacy 코드 제거
using ILensProtocol;
using DFLogger;

//! FR55 호환성: 전역 상수 Profile 제거
//! 파일 로드 시 BLE API 호출 방지 → lazy 함수로 이동

//! RunVision-IQ DataField - Garmin to iLens AR Bridge
//! Hybrid: Passive Connection 우선, 없으면 registerProfile() (ActiveLook 참조)
class RunVisionIQView extends WatchUi.DataField {

    // BleDelegate 메서드들을 직접 구현
    // FR55 호환성: ILensBLE legacy 코드 제거

    // BLE Scanner 방식: 직접 관리
    private var _connectedDevice as BluetoothLowEnergy.Device or Null;
    private var _exerciseCharacteristic as BluetoothLowEnergy.Characteristic or Null;
    private var _isConnected as Lang.Boolean = false;
    private var _scanStatus as Lang.String = "INIT";
    private var _devicesFound as Lang.Number = 0;

    // ✅ Auto-reconnect 변수 (Flutter 방식)
    private var _autoReconnectEnabled as Lang.Boolean = true;
    private var _isReconnecting as Lang.Boolean = false;  // 재연결 진행 중
    private var _reconnectAttempts as Lang.Number = 0;
    private const MAX_RECONNECT_ATTEMPTS = 3;
    private var _lastScanResult as BluetoothLowEnergy.ScanResult or Null;  // 마지막 연결 기기 정보
    private var _charRetryCount as Lang.Number = 0;  // Characteristic 검색 재시도 카운터

    // Display labels
    private var _speedLabel as Lang.String = "---";
    private var _hrLabel as Lang.String = "---";
    private var _cadenceLabel as Lang.String = "---";
    private var _distanceLabel as Lang.String = "0.00";
    private var _timeLabel as Lang.String = "0:00";
    private var _paceLabel as Lang.String = "--:--";
    private var _altitudeLabel as Lang.String = "---";  // 사이클 현재 고도(m) — 글래스 전송값(cadence슬롯 0x0E)과 동일

    // Profile registration tracking (ActiveLook 방식)
    private var _profileRegistered as Lang.Boolean = false;

    // ✅ 자체 경과 시간 카운터 (Flutter 방식)
    // Activity.Info.timerTime 사용 (ms), 미지원 기기는 fallback 카운터 사용
    private var _elapsedSeconds as Lang.Number = 0;
    private var _connectionStartTime as Lang.Number = 0;  // 연결 시작 시간 (Service Discovery 대기용)

    // Running Power 계산용 변수
    private var _previousAltitude as Lang.Float = 0.0;     // 이전 고도 (m)
    private var _previousDistance as Lang.Float = 0.0;     // 이전 거리 (m)
    private var _userWeight as Lang.Float = 70.0;          // 사용자 체중 (kg, 기본값 70kg)
    private var _weightInitialized as Lang.Boolean = false;  // 체중 초기화 플래그

    // Write Queue: 이번 tick 에 보낼 패킷(들). 페이싱으로 보통 1~3개. 콜백 기반 순차 전송.
    private var _writeQueue as Lang.Array<Lang.ByteArray> = [] as Lang.Array<Lang.ByteArray>;
    private var _isWriting as Lang.Boolean = false;  // Write 진행 중 플래그
    private var _computeCount as Lang.Number = 0;    // compute() 호출 횟수 (페이싱 라운드로빈 인덱스)

    // BLE Write 속도 자동 감지
    // - 빠른 기기 (FR165+): WRITE_WITH_RESPONSE (~80ms) → 5개/초 OK
    // - 느린 기기 (FR55):   WRITE_TYPE_DEFAULT 사용 → 빠르게 전송
    private var _useDefaultWrite as Lang.Boolean = false;  // true면 DEFAULT 사용
    private var _writeStartTime as Lang.Number = 0;        // 첫 Write 시작 시간 (ms)
    private var _speedDetected as Lang.Boolean = false;    // 속도 감지 완료 여부
    private const SLOW_DEVICE_THRESHOLD_MS = 500;          // 500ms 이상이면 느린 기기

    // 자동 재연결 관련 변수 (추가)
    private var _lastReconnectTime as Lang.Number = 0;       // 마지막 재연결 시도 시간 (초)
    private var _needsReconnect as Lang.Boolean = false;     // 재연결 필요 플래그
    private const RECONNECT_FAST_INTERVAL = 5;               // 빠른 재연결 간격 (초)
    private const RECONNECT_SLOW_INTERVAL = 60;              // 느린 재연결 간격 (초)
    private const RECONNECT_FAST_MAX = 5;                    // 빠른 재연결 최대 횟수
    // 앱 버전은 source/AppVersion.mc 의 AppVersion.VALUE 사용 (build.sh 가 manifest.xml 에서 자동 생성·동기화).

    // ✅ Pairing 타임아웃 (Connecting 상태 멈춤 방지)
    // System.getTimer() 사용 - 액티비티 시작 전에도 동작
    private var _pairingStartTime as Lang.Number = 0;        // 페어링 시작 시간 (ms, System.getTimer())
    private var _pairingRetryCount as Lang.Number = 0;       // 페어링 재시도 횟수
    private const PAIRING_TIMEOUT_MS = 3000;                 // 3초 타임아웃 (ms)
    private const PAIRING_MAX_RETRIES = 3;                   // 최대 3회 재시도

    // === 사이클/러닝 모드 분기 (Strategy 패턴) ===
    private var _strategy as MetricStrategy or Null = null;
    private var _metricValues as MetricValues or Null = null;
    // 스캔 타임아웃: 2-retry + 새 기기 등록 모드
    private var _scanStartTime as Lang.Number = 0;           // 스캔 시작 시간 (ms)
    private var _savedDeviceScanAttempts as Lang.Number = 0; // 저장된 기기 탐색 시도 횟수
    private const SCAN_TIMEOUT_MS_IQ = 3000;                 // 스캔 타임아웃 (ms)

    //! FR55 호환성: Profile을 lazy 생성 (파일 로드 시 BLE API 호출 방지)
    private function getExerciseProfile() as Lang.Dictionary {
        return {
            :uuid => BluetoothLowEnergy.stringToUuid("4b329cf2-3816-498c-8453-ee8798502a08"),
            :characteristics => [
                { :uuid => BluetoothLowEnergy.stringToUuid("c259c1bd-18d3-c348-b88d-5447aea1b615") }
            ]
        };
    }

    //! Constructor
    function initialize() {
        DataField.initialize();

        // BLE Delegate 설정 (별도 클래스 필요 - DataField는 BleDelegate 상속 불가)
        try {
            var delegate = new $.RunVisionBleDelegate(self);
            BluetoothLowEnergy.setDelegate(delegate);

            // 초기화 시 기존 bonding 정보 삭제 (iLens는 multi-bonding 미지원)
            // FR55 호환성: has 연산자로 API 존재 여부 확인
            if (BluetoothLowEnergy has :getPairedDevices) {
                try {
                    var paired = BluetoothLowEnergy.getPairedDevices();
                    var dev = paired.next() as BluetoothLowEnergy.Device;
                    while (dev != null) {
                        BluetoothLowEnergy.unpairDevice(dev);
                        dev = paired.next() as BluetoothLowEnergy.Device;
                    }
                } catch (ex2) {
                    // 무시
                }
            }

            _scanStatus = "INIT_OK";
        } catch (ex) {
            _scanStatus = "INIT_ERR";
        }

        _metricValues = new MetricValues();
    }

    //! Check for already paired devices (Passive Connection)
    //! iLens는 multi-bonding 미지원 → 항상 새로 스캔/페어링
    private function checkPairedDevices() as Void {
        try {
            // 기존 페어링 정보 삭제 (iLens가 다른 기기와 페어링되었을 수 있음)
            // FR55 호환성: has 연산자로 API 존재 여부 확인
            if (BluetoothLowEnergy has :getPairedDevices) {
                var pairedDevices = BluetoothLowEnergy.getPairedDevices();
                var device = pairedDevices.next() as BluetoothLowEnergy.Device;
                while (device != null) {
                    try {
                        BluetoothLowEnergy.unpairDevice(device);
                    } catch (ex) {
                        // 무시
                    }
                    device = pairedDevices.next() as BluetoothLowEnergy.Device;
                }
            }

            // 항상 새로 스캔 (iLens는 multi-bonding 미지원)
            try {
                BluetoothLowEnergy.registerProfile(getExerciseProfile());
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
                _scanStatus = "SCANNING";
            } catch (ex) {
                _scanStatus = "SCAN_ERR";
            }
        } catch (ex) {
            _scanStatus = "ERR:init";
        }
    }

    //! Called when activity is started
    function onTimerStart() as Void {
        // DFLogger.reset();
        // DFLogger.log("=== Activity Started ===");

        // Passive Connection: 페어링된 기기 확인
        if (!_isConnected) {
            checkPairedDevices();
        }

        WatchUi.requestUpdate();
    }

    //! Called when activity is stopped
    function onTimerStop() as Void {
        // Stop scanning (BLE Scanner 방식)
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
    }

    //! Called when activity is paused
    function onTimerPause() as Void {
        // Timer paused
    }

    //! Called when activity is resumed
    function onTimerResume() as Void {
        // Timer resumed
    }

    //! Called when lap button is pressed
    function onTimerLap() as Void {
        // Lap recorded
    }

    //! Called when activity is reset
    function onTimerReset() as Void {
        _paceLabel = "--:--";
        _distanceLabel = "0.00";
        _timeLabel = "0:00";
        _speedLabel = "---";
        _hrLabel = "---";
        _cadenceLabel = "---";
        _altitudeLabel = "---";
        _devicesFound = 0;
        _elapsedSeconds = 0;  // ✅ 경과 시간 초기화
        // 세션 경계: 전략(사이클 HR 30초 락 등 누적 상태)·회전 인덱스를 폐기해 다음 세션이
        // 이전 라이드 결정을 상속하지 않도록. _strategy=null → 다음 compute 의 실시간 판정이 새로 생성.
        _strategy = null;
        _computeCount = 0;
        // 진행 중이던 write/큐 폐기 → 리셋 중 in-flight 콜백이 이전 세션 패킷을 새 세션에 흘리지 않게.
        // (disconnect 경로와 동일 처리. 페이싱이라 큐는 보통 ≤1.)
        _writeQueue = [] as Lang.Array<Lang.ByteArray>;
        _isWriting = false;
    }

    //! Called each second to compute and display values (DataField)
    //! @param info Activity.Info object
    function compute(info as Activity.Info) as Void {
        // Passive Connection 타임아웃 (3초)
        if (_scanStatus.equals("PASSIVE") && !_isConnected && _elapsedSeconds >= 3) {
            try {
                // FR55 호환성: has 연산자로 API 존재 여부 확인
                if (_connectedDevice != null && (BluetoothLowEnergy has :unpairDevice)) {
                    BluetoothLowEnergy.unpairDevice(_connectedDevice);
                }
                _connectedDevice = null;
                _profileRegistered = false;
                BluetoothLowEnergy.registerProfile(getExerciseProfile());
                _scanStatus = "RESCAN";
            } catch (ex) {
            }
        }

        // ✅ Pairing 타임아웃 (Connecting 상태 멈춤 방지)
        // System.getTimer() 사용 - 액티비티 시작 전에도 동작
        if (_pairingStartTime > 0 && !_isConnected) {
            var pairingDuration = System.getTimer() - _pairingStartTime;
            if (pairingDuration >= PAIRING_TIMEOUT_MS) {
                _pairingRetryCount++;
                _pairingStartTime = 0;

                try {
                    if (_connectedDevice != null && (BluetoothLowEnergy has :unpairDevice)) {
                        BluetoothLowEnergy.unpairDevice(_connectedDevice);
                    }
                    _connectedDevice = null;
                    _isReconnecting = false;
                } catch (ex) {
                    // 무시
                }

                if (_pairingRetryCount >= PAIRING_MAX_RETRIES) {
                    // 3회 실패 → CONN_ERR
                    _scanStatus = "CONN_ERR";
                    _pairingRetryCount = 0;
                } else {
                    // 재시도: 즉시 다시 pairing
                    _scanStatus = "RETRY " + _pairingRetryCount;
                    if (_lastScanResult != null) {
                        try {
                            _pairingStartTime = System.getTimer();
                            _connectedDevice = BluetoothLowEnergy.pairDevice(_lastScanResult);
                            if (_connectedDevice == null) {
                                _pairingStartTime = 0;
                            }
                        } catch (ex) {
                            _pairingStartTime = 0;
                        }
                    }
                }
            }
        }

        // 스캔 타임아웃: 2-retry + 새 기기 등록 모드
        // 저장된 기기 3s×2 미발견 → savedRLensName 삭제 후 any rLens 스캔 3s×2
        if ((_scanStatus.equals("SCANNING") || _scanStatus.equals("NEW_DEV")) && _scanStartTime > 0 && !_isConnected) {
            var scanElapsed = System.getTimer() - _scanStartTime;
            if (scanElapsed >= SCAN_TIMEOUT_MS_IQ) {
                try {
                    _scanStartTime = 0;
                    _savedDeviceScanAttempts++;

                    var savedDevice = Application.Storage.getValue("savedRLensName");

                    if (savedDevice != null && _savedDeviceScanAttempts >= 2) {
                        // 저장된 기기 2회 실패 → 새 기기 등록 모드
                        if (Application.Storage has :deleteValue) {
                            Application.Storage.deleteValue("savedRLensName");
                        } else {
                            Application.Storage.setValue("savedRLensName", null);
                        }
                        _savedDeviceScanAttempts = 0;
                        _scanStartTime = System.getTimer();  // 새 타임아웃 윈도우
                        _scanStatus = "NEW_DEV";
                    } else if (savedDevice == null && _savedDeviceScanAttempts >= 2) {
                        // 새 기기 등록 모드 또는 최초 실행 2회 실패 → 에러
                        _scanStatus = "SCAN_FAIL";
                        _savedDeviceScanAttempts = 0;
                    } else {
                        // 1차 실패 → 재시도 (스캔 계속 유지)
                        _scanStartTime = System.getTimer();
                    }

                    WatchUi.requestUpdate();
                } catch (ex) {
                    _scanStartTime = 0;
                    _savedDeviceScanAttempts = 0;
                }
            }
        }

        // Auto-reconnect (연결 끊김 시)
        // 전략: 1-5회는 5초 간격 단순 재연결, 6회째 unpair 후 재스캔, 이후 1분마다 재스캔
        if (_needsReconnect && !_isConnected && !_isReconnecting) {
            var timeSinceLastTry = _elapsedSeconds - _lastReconnectTime;
            var shouldTry = false;
            var interval = 0;

            if (_reconnectAttempts < RECONNECT_FAST_MAX) {
                // 1-5회: 5초 간격
                interval = RECONNECT_FAST_INTERVAL;
                shouldTry = (timeSinceLastTry >= interval);
            } else {
                // 6회 이후: 1분 간격
                interval = RECONNECT_SLOW_INTERVAL;
                shouldTry = (timeSinceLastTry >= interval);
            }

            if (shouldTry) {
                _reconnectAttempts++;
                _lastReconnectTime = _elapsedSeconds;
                _isReconnecting = true;

                if (_reconnectAttempts <= RECONNECT_FAST_MAX && _lastScanResult != null) {
                    // 1-5회: 단순 재연결 시도 (빠름)
                    _scanStatus = "RECONN " + _reconnectAttempts;
                    try {
                        _pairingStartTime = System.getTimer();  // ✅ 타임아웃 추적 시작
                        _connectedDevice = BluetoothLowEnergy.pairDevice(_lastScanResult);
                        if (_connectedDevice == null) {
                            _isReconnecting = false;
                            _pairingStartTime = 0;  // 실패 시 리셋
                        }
                    } catch (ex) {
                        _isReconnecting = false;
                        _pairingStartTime = 0;  // 실패 시 리셋
                    }
                } else {
                    // 6회 이후: unpair 후 새로 스캔
                    _scanStatus = "RESCAN";
                    try {
                        // 기존 bonding 삭제 (FR55 호환성: has 연산자로 확인)
                        if (BluetoothLowEnergy has :getPairedDevices) {
                            var paired = BluetoothLowEnergy.getPairedDevices();
                            var dev = paired.next() as BluetoothLowEnergy.Device;
                            while (dev != null) {
                                BluetoothLowEnergy.unpairDevice(dev);
                                dev = paired.next() as BluetoothLowEnergy.Device;
                            }
                        }
                        // 새로 스캔 시작
                        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
                        _isReconnecting = false;
                    } catch (ex) {
                        _isReconnecting = false;
                    }
                }
            }
        }

        // ✅ Lazy Loading: Characteristic 필요할 때 획득 (매초 1회 시도)
        if (_isConnected && _connectedDevice != null && _exerciseCharacteristic == null) {
            try {
                _exerciseCharacteristic = tryGetServiceCharacteristic(
                    ILensProtocol.EXERCISE_SERVICE_UUID,
                    ILensProtocol.EXERCISE_DATA_UUID,
                    3  // 3번 동기 재시도
                );
                _charRetryCount = 0;  // 성공 시 리셋
                _scanStatus = "READY";
            } catch (ex) {
                _charRetryCount++;
                if (_charRetryCount >= 10) {
                    // 10회 실패 → 재연결 트리거 (5초 임계값은 정상 RF 환경에서도 false-positive 유발)
                    _charRetryCount = 0;
                    _isConnected = false;
                    _connectedDevice = null;
                    _scanStatus = "RECONN...";
                    // ❗ 재연결 게이트(line ~375)는 _needsReconnect를 요구함. disconnect 핸들러와
                    //    동일하게 arming하지 않으면 _needsReconnect=false라 재연결이 영영 안 돌고
                    //    영구 disconnect 상태로 고착됨.
                    if (_autoReconnectEnabled) {
                        _needsReconnect = true;
                        _lastReconnectTime = _elapsedSeconds;
                        _isReconnecting = false;
                    }
                } else {
                    // 실패 횟수 표시 (1~4) - 사용자가 이상 상태 인지 가능
                    _scanStatus = "CHAR_FAIL(" + _charRetryCount + ")";
                }
            }
        }

        // ========== 데이터 수집 (라벨 업데이트) ==========
        // ActiveLook 패턴: has 체크 + false 체크

        // Get current speed (m/s -> km/h)
        var speedMs = info != null && info has :currentSpeed ? info.currentSpeed : null;
        var speedKmh = 0.0;  // Float — 사이클 모드 0x07 × 60 트릭에서 소수점 정밀도 보존
        var paceSeconds = 0;  // ← Pace를 초 단위로 저장 (iLens 전송용)
        // 전송 여부: 센서값 존재(0=정지 포함)면 전송, null(no-data/재연결)만 skip.
        // 과거 `&& > 0` 은 정지(실제 0)까지 skip → rLens 직전값 고착 + velocity 갭 후 펌웨어 latch 회귀.
        var speedValid = metricPresent(speedMs);
        // 계산 가드: pace = 60/(speed) 0 나눗셈 방지 위해 양수일 때만 계산. 정지면 pace/speed=0 유지(→ 0 전송).
        var speedMoving = speedMs != null && speedMs > 0;

        if (speedMoving) {
            speedKmh = speedMs * 3.6;  // Float 유지 (사이클 precision)
            _speedLabel = ((speedKmh + 0.5).toNumber()).format("%d");  // 표시는 정수 km/h

            // Calculate pace (min/km) - 러너들은 Pace에 익숙
            var paceMinPerKm = 60.0 / (speedMs * 3.6);
            var paceMin = paceMinPerKm.toNumber();
            var paceSec = ((paceMinPerKm - paceMin) * 60).toNumber();
            _paceLabel = paceMin.format("%d") + ":" + paceSec.format("%02d");

            // iLens 전송용: Pace를 총 초로 변환 (예: 4:25 → 265초)
            // iLens 펌웨어가 60으로 나눠서 표시: 265 / 60 = 4.42
            paceSeconds = paceMin * 60 + paceSec;
        } else {
            _speedLabel = "0";
            _paceLabel = "--:--";
        }

        // Get current heart rate (ActiveLook 패턴)
        var hr = info != null && info has :currentHeartRate ? info.currentHeartRate : null;
        var hrValid = hr != null && hr > 0;
        if (hrValid) {
            _hrLabel = hr.format("%d");
        } else {
            _hrLabel = "---";
            hr = 0;
        }

        // Get current cadence (ActiveLook 패턴)
        var cadence = info != null && info has :currentCadence ? info.currentCadence : null;
        var cadenceValid = metricPresent(cadence);  // 0(정지)=전송, null(미지원)=skip
        if (cadenceValid) {
            _cadenceLabel = cadence.format("%d");
        } else {
            _cadenceLabel = "---";
            cadence = 0;
        }

        // Get elapsed distance (meters) - Running Power 계산에 필요
        var distance = info != null && info has :elapsedDistance ? info.elapsedDistance : null;
        var distanceValid = distance != null && distance > 0;
        if (distanceValid) {
            var distanceKm = distance / 1000.0;
            _distanceLabel = distanceKm.format("%.2f");
        } else {
            _distanceLabel = "0.00";
            distance = 0;
        }

        // ========== Running Power 계산 ==========
        // Power Meter 대신 GPS 데이터로 Running Power 추정
        // Formula: Power = Weight × Speed × (1 + |Grade|/100) × k
        //   - Weight: 체중 (kg)
        //   - Speed: 속도 (m/s)
        //   - Grade: 경사도 (%)
        //   - k: 보정 상수 (≈1.8, Garmin/Stryd 기준)

        var power = 0;

        // 1. UserProfile에서 체중 가져오기 (처음 한 번만)
        if (!_weightInitialized) {
            try {
                var profile = UserProfile.getProfile();
                if (profile != null && profile has :weight) {
                    var profileWeight = profile.weight;  // grams
                    if (profileWeight != null && profileWeight > 0) {
                        _userWeight = profileWeight / 1000.0;  // g → kg
                        // DFLogger.log("[POWER] User weight: " + _userWeight.format("%.1f") + " kg");
                    }
                }
            } catch (ex) {
                // DFLogger.logError("POWER", "Failed to get user weight");
            }
            _weightInitialized = true;
        }

        // 2. 고도 가져오기
        var altitude = info != null && info has :altitude ? info.altitude : null;
        // 워치 표시용 고도 라벨 (글래스 전송값 altitudeM = roundFloat(altitude)와 동일 반올림)
        if (altitude != null) { _altitudeLabel = roundFloat(altitude).format("%d"); } else { _altitudeLabel = "---"; }

        // 3. Running Power 계산 (속도와 거리가 유효할 때만)
        if (speedMoving && distanceValid && altitude != null) {  // 파워는 이동 중에만(기존 동작 보존)
            // 경사도 계산 (최근 구간의 고도 변화)
            var grade = 0.0;
            var distanceDelta = distance - _previousDistance;

            if (distanceDelta > 10.0) {  // 10m 이상 이동했을 때만 경사도 계산
                var altitudeDelta = altitude - _previousAltitude;
                grade = (altitudeDelta / distanceDelta) * 100.0;  // % 단위

                // 경사도 범위 제한 (-30% ~ +30%)
                if (grade < -30.0) { grade = -30.0; }
                if (grade > 30.0) { grade = 30.0; }

                // 다음 계산을 위해 저장
                _previousAltitude = altitude;
                _previousDistance = distance;
            }

            // Running Power 계산
            // Power = Weight × Speed × (1 + |Grade|/100) × 1.8
            var gradeFactor = 1.0 + (grade > 0 ? grade : -grade) / 100.0;  // |Grade|/100
            power = (_userWeight * speedMs * gradeFactor * 1.8).toNumber();

            // 파워 범위 제한 (0-999 watts, 일반 러너 범위)
            if (power < 0) { power = 0; }
            if (power > 999) { power = 999; }
        }

        // ✅ Activity.Info에서 실제 경과 시간 사용 (timerTime = milliseconds)
        // compute()는 1초마다 호출되지 않을 수 있으므로 timerTime 사용이 정확함
        if (info != null && info has :timerTime && info.timerTime != null) {
            _elapsedSeconds = (info.timerTime / 1000).toNumber();  // ms → seconds
        } else {
            // Fallback: 수동 카운터 (timerTime 미지원 기기)
            _elapsedSeconds += 1;
        }
        var minutes = _elapsedSeconds / 60;
        var secs = _elapsedSeconds % 60;
        _timeLabel = minutes.format("%d") + ":" + secs.format("%02d");

        // ========== iLens 전송: Queue 방식 ==========
        // 주기마다 모든 메트릭을 queue에 추가 → 순차 전송
        // iLens는 write 완료 콜백 기반으로 다음 패킷을 이어 보낸다.
        _computeCount++;
        // 전송 전략을 매 compute 실시간 sport 로 재판정(drawMetricGrid 화면 판정과 동일 기준).
        // 과거: 첫 compute 1회만 검출해 영구 고정 → 첫 프레임에 sport 미확정(느린 fr55 에서 흔함)이면
        //       러닝으로 잠겨, 사이클인데도 0x07=페이스·0x0e=cadence(자전거 센서 없음→0) 를 보냄
        //       → 글래스에 페이스가 뜨고 고도=0. (fr165 는 레이스를 이겨 가려졌던 기존 버그.)
        // sport 클래스가 바뀔 때만 인스턴스 교체 → CyclingStrategy HR-lock 등 상태 보존.
        // profile==null(전이적) 이면 현재 전략 유지(thrash 방지).
        var profile = Activity.getProfileInfo();
        if (profile != null) {
            if (profile.sport == Activity.SPORT_CYCLING) {
                if (_strategy == null || !(_strategy instanceof CyclingStrategy)) {
                    _strategy = new CyclingStrategy();
                }
            } else {
                if (_strategy == null || !(_strategy instanceof RunningStrategy)) {
                    _strategy = new RunningStrategy();
                }
            }
        }
        if (_strategy == null) {
            _strategy = new RunningStrategy();  // 최초 프레임 profile==null 안전장치
        }

        // 전략의 세션 상태(사이클 HR 30초 락 등)는 BLE 전송 자격(_isWriting)과 무관하게 매 compute 갱신.
        // (전송이 skip 되는 tick 에도 HR 관측이 누락되지 않도록 — 스펙 §2 "매 compute".)
        (_strategy as MetricStrategy).onComputeTick((hr != null) ? hr : 0, _elapsedSeconds);

        // 페이싱 전송: 매 compute(1Hz)마다 메트릭 1개씩 균등 라운드로빈으로 전송.
        // burst(5패킷 동시)는 느린 기기(FR55)에서 HR/cad 가 글래스에 15~20초 간격으로만 도달 → freeze.
        // 1패킷/tick → 평균 1 write/초(= 기존 5초모드 배터리), burst 과부하 없음, 기기 판별 불필요.
        // 각 메트릭은 (유효 메트릭 수)초마다 갱신(전부 유효 시 ~5초). buildPackets 가 유효 메트릭만
        // 순서대로 주므로 그 중 _computeCount 로 회전 → invalid 슬롯에 빈 tick 낭비 없음.
        // _isWriting 가드 유지 → 큐 ≤ 1 (무가드 write·큐 무한증가·OOM 없음).
        if (_isConnected && _exerciseCharacteristic != null && !_isWriting) {
            try {
                // MetricValues 채우기 (compute() 내에서 이미 계산된 값들 복사)
                _metricValues.elapsedSeconds = _elapsedSeconds;
                _metricValues.paceSeconds = paceSeconds;
                _metricValues.speedKmh = speedKmh;
                _metricValues.hr = (hr != null) ? hr : 0;
                _metricValues.cadence = cadence;
                // Float → Int 변환은 encodeUINT32() 와 동일하게 반올림 (truncate 시 ~0.5m 편차 발생)
                _metricValues.distance = (distance != null) ? roundFloat(distance) : 0;
                _metricValues.altitudeM = (altitude != null) ? roundFloat(altitude) : 0;
                _metricValues.totalAscent = (info != null && info has :totalAscent && info.totalAscent != null) ? roundFloat(info.totalAscent) : 0;

                // *Valid 플래그: stale 0 패킷을 iLens 로 보내지 않기 위한 packet-level skip 신호.
                _metricValues.speedValid = speedValid;
                _metricValues.hrValid = hrValid;
                _metricValues.cadenceValid = cadenceValid;
                _metricValues.distanceValid = distanceValid;
                _metricValues.altitudeValid = (altitude != null);
                _metricValues.totalAscentValid = (info != null && info has :totalAscent && info.totalAscent != null);

                // 이번 tick 에 보낼 패킷을 전략이 결정 (러닝·사이클 모두 1개/tick 균등 회전 — buildTickPackets 기본).
                var packets = (_strategy as MetricStrategy).buildTickPackets(_metricValues, _computeCount);
                if (packets.size() > 0) {
                    _writeQueue = packets;
                    processWriteQueue();
                }
            } catch (ex) {
                // DFLogger.logError("QUEUE", "Queue error");
            }
        }
    }

    //! Draw the data field
    //! @param dc Device context
    function onUpdate(dc as Graphics.Dc) as Void {
        try {
            // 연결됨 + 화면이 그리드를 수용할 폭이면 그리드, 아니면 status-only(작은 기기는
            // 메트릭을 글래스로 — 워치엔 상태만). gridFitsScreen 으로 런타임 분기(빌드 1개 전 기기 적응).
            if (_isConnected && gridFitsScreen(dc.getWidth())) {
                drawMetricGrid(dc);
            } else {
                drawStatusScreen(dc);
            }
        } catch (ex) {
            // Hardcoded coords — dc.getWidth() can throw if dc is broken
            try { dc.drawText(120, 50, Graphics.FONT_SMALL, "ERR", Graphics.TEXT_JUSTIFY_CENTER); } catch (ex2) {}
        }
    }

    //! 연결 전 화면: 로고 + 상태 + 버전 (기존 동작 그대로)
    private function drawStatusScreen(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;
        var centerY = height / 2;

        // instinct은 데이터필드를 메인(156/176) + 보조창(54px) 두 번 렌더한다. 보조창(폭<100)은 너무
        // 좁아 식별자 "RV"만. 메인(instinct2s 156 포함)은 아래의 RunVision+상태+버전 블록을 그린다.
        if (width < 100) {
            dc.drawText(centerX, centerY, Graphics.FONT_LARGE, "RV",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // 타이틀(텍스트) — 모든 기기에서 로고 비트맵 대신 사용.
        // 로고(176x37 RGBA ≈26KB)는 작은 기기(fr55/instinct2s 등)의 DataField 메모리 예산을
        // 초과해 onUpdate 에서 OOM 크래시 → 텍스트 타이틀로 통일(메모리·기기 호환성 확보).
        //
        // 타이틀·상태·버전 3줄을 '폰트 높이 기반'으로 세로 중앙 정렬. 픽셀 하드코딩(centerY±30) 금지 —
        // 큰 기기는 타이틀 폰트가 커서 상태와 겹쳤음(40-titleH<0). gap=titleH/2 로 타이틀↔상태 숨구멍
        // (폰트 비례 → 기기 무관, 사용자 요청). 작은 기기(instinct2 176/fr55 208)도 블록이 화면에 fit.
        var titleFont = Graphics.FONT_MEDIUM;
        var titleH = dc.getFontHeight(titleFont);
        var statusH = dc.getFontHeight(Graphics.FONT_SMALL);
        var versionH = dc.getFontHeight(Graphics.FONT_XTINY);
        var gap = titleH / 2;   // 타이틀↔상태 갭
        var vGap = 4;           // 상태↔버전 (작게)
        var blockH = titleH + gap + statusH + vGap + versionH;
        // instinct(보조창, 폭<200)은 우상단 보조창이 중앙 정렬된 와이드 타이틀의 오른쪽 끝을 가림 →
        // 블록을 보조창 아래(0.42h부터)로 내림. 그 외 기기는 세로 중앙 정렬.
        var subWindow = (width < 200);
        var topY = subWindow ? (height * 0.42).toNumber() : (centerY - blockH / 2);

        dc.drawText(centerX, topY, titleFont, "RunVision", Graphics.TEXT_JUSTIFY_CENTER);

        // 상태 텍스트
        var statusText = _isConnected ? "Connected" : _scanStatus;
        var statusY = topY + titleH + gap;
        dc.drawText(centerX, statusY, Graphics.FONT_SMALL, statusText, Graphics.TEXT_JUSTIFY_CENTER);

        // 앱 버전 (상태 바로 아래, 작고 흐리게)
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var versionY = statusY + statusH + vGap;
        dc.drawText(centerX, versionY, Graphics.FONT_XTINY, "v" + AppVersion.VALUE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //! 연결 후 화면: 5개 메트릭 1-2-2 그리드 (반응형, 텍스트만 — 비트맵 없음).
    //! 러닝: TIME / PACE·CAD / DIST·HR   사이클: TIME / SPEED·ALT / DIST·HR
    private function drawMetricGrid(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var shape = System.getDeviceSettings().screenShape;
        var isRound = (shape == System.SCREEN_SHAPE_ROUND) || (shape == System.SCREEN_SHAPE_SEMI_ROUND);
        var L = metricGridLayout(w, h, isRound);
        // 사이클 여부는 활동 sport로 직접 판별 — BLE/_strategy 타이밍과 무관(연결 전·초기 프레임에도 정확).
        var profile = Activity.getProfileInfo();
        var isCycling = (profile != null) && (profile.sport == Activity.SPORT_CYCLING);
        var cx = L[:centerX] as Lang.Number;
        var lx = L[:leftX] as Lang.Number;
        var rx = L[:rightX] as Lang.Number;

        // 반응형 값 폰트: 행 간격에 (값 + 라벨XTINY)이 들어가는 '가장 큰' 값 폰트 선택(LARGE→MEDIUM→SMALL).
        // 라벨은 전 기기 XTINY 고정(사용자 결정) — 값 대비 ~절반이라 계층이 선명(큰 폰트끼리는 차이가 작아
        // "같아 보임"). 행을 화면에 넓게 펼쳐 행 간격이 크므로 큰 화면은 값이 LARGE까지 커진다.
        var rowGap = (L[:row1Y] as Lang.Number) - (L[:timeY] as Lang.Number);
        var labelH = dc.getFontHeight(Graphics.FONT_XTINY);
        // 세로로 긴 화면(Edge)은 시스템 FONT_LARGE가 작으므로(edge1040 L=36) 큰 데이터필드 숫자 폰트를
        // 후보에 추가 — 값이 화면 크기에 맞게 커짐. NUMBER 폰트도 대시·콜론·소수점 렌더됨(검증). 그 외
        // 기기는 기존 [LARGE/MEDIUM/SMALL] 그대로(워치 regression 0).
        var tallPortrait = (h * 100 / w) > 138;
        var fonts = tallPortrait
            ? [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
               Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL]
            : [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL];
        var valueFont = Graphics.FONT_SMALL;   // 폴백: 가장 작은 값 폰트
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getFontHeight(fonts[i]) + labelH <= rowGap) {
                valueFont = fonts[i];
                break;
            }
        }

        // 상단: TIME (중앙)
        drawCell(dc, cx, L[:timeY] as Lang.Number, _timeLabel, "TIME", valueFont);
        // 중단: 좌 PACE/SPEED · 우 CAD/ALT
        drawCell(dc, lx, L[:row1Y] as Lang.Number, isCycling ? _speedLabel : _paceLabel, isCycling ? "SPEED" : "PACE", valueFont);
        drawCell(dc, rx, L[:row1Y] as Lang.Number, isCycling ? _altitudeLabel : _cadenceLabel, isCycling ? "ALT" : "CAD", valueFont);
        // 하단: 좌 DIST · 우 HR
        drawCell(dc, lx, L[:row2Y] as Lang.Number, _distanceLabel, "DIST", valueFont);
        drawCell(dc, rx, L[:row2Y] as Lang.Number, _hrLabel, "HR", valueFont);
    }

    //! 셀 1개: 값(큰 숫자 폰트) + 그 아래 라벨(작은 회색). x,y = 값의 중앙정렬 기준(상단).
    //! 값-라벨을 한 단위로 붙여 그려 줄맞춤·간격 일관.
    private function drawCell(dc as Graphics.Dc, x as Lang.Number, y as Lang.Number, value as Lang.String, label as Lang.String, valueFont as Graphics.FontDefinition) as Void {
        // 값: valueFont(반응형 LARGE/MEDIUM/SMALL). 라벨: FONT_XTINY 고정, 값 높이 바로 아래 → 겹침 없음.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, valueFont, value, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + dc.getFontHeight(valueFont), Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    //
    // ILensDelegate interface implementation
    //

    //! Called when characteristic value changes (NOTIFY)
    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        // Not used for iLens (write-only)
    }

    //! Called when characteristic read completes
    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        // Not used for iLens
    }

    //! Called when characteristic write completes (WRITE_WITH_RESPONSE)
    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        _isWriting = false;

        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            _scanStatus = "WRITE_ERR";
            _writeQueue = [] as Lang.Array<Lang.ByteArray>;
            return;
        }

        // 속도 감지 (첫 Write 콜백 시)
        if (!_speedDetected && _writeStartTime > 0) {
            var elapsed = System.getTimer() - _writeStartTime;
            _speedDetected = true;
            _writeStartTime = 0;

            if (elapsed > SLOW_DEVICE_THRESHOLD_MS) {
                // 느린 기기 → DEFAULT 모드로 전환
                _useDefaultWrite = true;
            } else {
                // 빠른 기기 → WITH_RESPONSE 유지
            }
        }

        // 다음 패킷 전송
        processWriteQueue();
    }

    //! Process write queue (순차 전송)
    private function processWriteQueue() as Void {
        if (_isWriting) { return; }
        if (_writeQueue.size() == 0) { return; }

        var packet = _writeQueue[0];
        _writeQueue = _writeQueue.slice(1, null) as Lang.Array<Lang.ByteArray>;

        _isWriting = true;
        sendToILens(packet);
    }

    //! Called when connection state changes (BLE API 콜백 - DataField 방식)
    //! ActiveLook 방식: 연결 시 디바이스만 저장, Service Discovery는 나중에
    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _isConnected = true;
            _connectedDevice = device;
            _connectionStartTime = _elapsedSeconds;
            _pairingStartTime = 0;  // ✅ 타임아웃 추적 종료
            _pairingRetryCount = 0; // ✅ 재시도 카운터 리셋
            _reconnectAttempts = 0;
            _charRetryCount = 0;  // Characteristic 검색 카운터 리셋
            _needsReconnect = false;
            _isReconnecting = false;
            _scanStartTime = 0;           // 스캔 타임아웃 추적 종료
            _savedDeviceScanAttempts = 0; // 스캔 시도 횟수 리셋
            _scanStatus = "CONNECTED";
            // DFLogger.logBle("CONNECTED", "Device connected");
        } else {
            _isConnected = false;
            _connectedDevice = null;
            _exerciseCharacteristic = null;
            _charRetryCount = 0;  // 재시도 카운터 리셋
            _connectionStartTime = 0;
            _pairingStartTime = 0;  // ✅ 타임아웃 추적 종료
            _isWriting = false;  // 진행 중이던 이전 연결 write 상태 폐기
            _writeQueue = [] as Lang.Array<Lang.ByteArray>;  // stale packet이 재연결 후 전송되지 않도록 비움
            // 속도 감지 리셋 (재연결 시 다시 측정)
            _useDefaultWrite = false;
            _writeStartTime = 0;
            _speedDetected = false;
            _scanStatus = "DISCONN";

            // Auto-reconnect 시작
            if (_autoReconnectEnabled) {
                _needsReconnect = true;
                _lastReconnectTime = _elapsedSeconds;
                _isReconnecting = false;
            }
        }

        WatchUi.requestUpdate();
    }

    //! Try and retry to get a characteristic from a service (ActiveLook 패턴 완전 복제)
    //! @param serviceUuid Service UUID
    //! @param characteristicUuid Characteristic UUID
    //! @param nbRetry Number of retries (권장: 5)
    //! @return Characteristic
    //! @throws InvalidValueException if not found after retries
    private function tryGetServiceCharacteristic(
        serviceUuid as BluetoothLowEnergy.Uuid,
        characteristicUuid as BluetoothLowEnergy.Uuid,
        nbRetry as Lang.Number
    ) as BluetoothLowEnergy.Characteristic {
        if (_connectedDevice == null) {
            throw new Lang.InvalidValueException("(E) Not connected");
        }

        var dev = _connectedDevice as BluetoothLowEnergy.Device;
        var service = dev.getService(serviceUuid);

        // ✅ RETRY PATTERN: nbRetry번 재시도 (ActiveLook 방식)
        for (var i = 0; i < nbRetry; i++) {
            if (service == null) {
                service = dev.getService(serviceUuid);  // ← Service 재시도
                if (service == null) {
                } else {
                }
            } else {
                var characteristic = service.getCharacteristic(characteristicUuid);
                if (characteristic != null) {
                    // ✅ 성공 시 즉시 리턴
                    return characteristic;
                } else {
                }
            }
        }

        // ✅ nbRetry번 실패 시 예외 발생
        if (service == null) {
            throw new Lang.InvalidValueException(
                "(E) Could not get service after " + nbRetry + " retries"
            );
        }
        throw new Lang.InvalidValueException(
            "(E) Could not get characteristic after " + nbRetry + " retries"
        );
    }

    //! Send data to iLens (WRITE_WITH_RESPONSE only)
    //! Send data to iLens with auto-detected Write Type
    //! - 빠른 기기: WRITE_WITH_RESPONSE (안정적, ~80ms)
    //! - 느린 기기: WRITE_TYPE_DEFAULT (빠름, FR55용)
    private function sendToILens(packet as Lang.ByteArray) as Void {
        if (_exerciseCharacteristic == null) {
            _isWriting = false;
            return;
        }

        try {
            // 속도 측정 시작 (첫 Write 시)
            if (!_speedDetected && _writeStartTime == 0) {
                _writeStartTime = System.getTimer();
            }

            // Write Type 선택
            var writeType = BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE;
            if (_useDefaultWrite) {
                writeType = BluetoothLowEnergy.WRITE_TYPE_DEFAULT;
            }

            _exerciseCharacteristic.requestWrite(packet, {:writeType => writeType});
        } catch (ex) {
            _isWriting = false;
        }
    }

    //! Called when descriptor read completes
    function onDescriptorRead(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        // Not used
    }

    //! Called when descriptor write completes
    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        // Not used
    }

    //! Called when profile registration completes
    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            _profileRegistered = true;
            _scanStatus = "PROF_OK";

            try {
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            } catch (ex) {
                _scanStatus = "SCAN_ERR";
            }
        } else {
            _scanStatus = "PROF_FAIL";
        }

        WatchUi.requestUpdate();
    }

    //! Called when rLens device is found during scanning
    function onScanResult(scanResult as BluetoothLowEnergy.ScanResult) as Void {
        try {

            // Save device name on first connection (device name = serial number)
            if (Application.Storage.getValue("savedRLensName") == null) {
                var raw = scanResult.getRawData();
                if (raw != null) {
                    var rawStr = "";
                    for (var i = 0; i < raw.size(); i++) {
                        var c = raw[i];
                        if (c >= 0x20 && c <= 0x7E) { rawStr += c.toChar(); }
                    }
                    // Extract device name: find "rlens" and read until whitespace
                    // NOTE: Monkey C String.find() returns null (not -1) when not found
                    var lowerStr = rawStr.toLower();
                    var idx = lowerStr.find("rlens");
                    if (idx != null) {
                        var nameEnd = idx;
                        while (nameEnd < rawStr.length()) {
                            var ch = rawStr.substring(nameEnd, nameEnd + 1);
                            if (ch.equals(" ")) { break; }
                            nameEnd++;
                        }
                        var deviceName = rawStr.substring(idx, nameEnd);
                        Application.Storage.setValue("savedRLensName", deviceName);
                    }
                }
            }

            // Auto-connect
            if (!_isConnected && _connectedDevice == null) {
                _devicesFound++;
                _lastScanResult = scanResult;

                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

                _pairingStartTime = System.getTimer();
                _connectedDevice = BluetoothLowEnergy.pairDevice(scanResult);

                if (_connectedDevice == null) {
                    _scanStatus = "PAIR_FAIL";
                    _pairingStartTime = 0;
                } else {
                    _scanStatus = "PAIRING";
                }
            }

            WatchUi.requestUpdate();
        } catch (ex) {
        }
    }

    //! Called when scan state changes
    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
                _scanStatus = "SCANNING";
                _scanStartTime = System.getTimer();  // 타임아웃 추적 시작
            } else {
                _scanStatus = "SCAN_ERR";
                _scanStartTime = 0;
            }
        } else if (scanState == BluetoothLowEnergy.SCAN_STATE_OFF) {
            // 스캔 중지 = 기기 찾음, 연결 시도 중
            _scanStatus = "Connecting...";
            _scanStartTime = 0;  // 스캔 종료 — 타임아웃 추적 불필요
        }

        WatchUi.requestUpdate();
    }

    //! Called when there's a passive connection (already paired)
    function onPassiveConnection(device as BluetoothLowEnergy.Device) as Void {
        _isConnected = true;
        _scanStatus = "PASSIVE";
        WatchUi.requestUpdate();
    }

    //! Legacy callbacks for ILens.mc compatibility (not used in Passive Connection)
    function profileRegistrationStart() as Void {}
    function profileRegistrationComplete() as Void {}
    function onBleError(exception as Lang.Exception) as Void {}

    //! Float을 Int로 반올림 (encodeUINT32 와 동일 로직).
    //! 양수: +0.5 후 truncate. 음수: -0.5 후 truncate.
    //! 단순 .toNumber()는 truncate이므로 1m 미만 편차 발생 → 회귀 원인.
    private function roundFloat(value as Lang.Number or Lang.Float or Lang.Double) as Lang.Number {
        if (value >= 0) {
            return (value + 0.5).toNumber();
        } else {
            return (value - 0.5).toNumber();
        }
    }

}

//! BLE Delegate - 별도 클래스 (DataField는 다중 상속 불가)
class RunVisionBleDelegate extends BluetoothLowEnergy.BleDelegate {
    private var _view;

    function initialize(view) {
        BleDelegate.initialize();
        _view = view;
        // System.println("RunVisionBleDelegate initialized");
    }

    //! rLens 기기 식별: 이름 전체 매칭 (기기명=시리얼번호, e.g. "rlens-e70b4")
    //! 저장된 기기명이 있으면 해당 기기만 연결 (다른 사람 기기 연결 방지)
    function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
        try {
            var savedDevice = Application.Storage.getValue("savedRLensName");
            var r = results.next() as BluetoothLowEnergy.ScanResult;
            while (r != null) {
                var raw = r.getRawData();

                if (raw != null) {
                    // Raw data 전체를 소문자 문자열로 변환
                    var rawStr = "";
                    for (var i = 0; i < raw.size(); i++) {
                        var c = raw[i];
                        if (c >= 0x20 && c <= 0x7E) {
                            rawStr += c.toChar();
                        }
                    }

                    var lowerStr = rawStr.toLower();
                    // NOTE: Monkey C String.find() returns null (not -1) when not found
                    if (lowerStr.find("rlens") != null) {
                        if (savedDevice != null) {
                            // 저장된 기기명과 정확히 일치하는 경우만 연결
                            if (rawStr.find(savedDevice) != null) {
                                _view.onScanResult(r);
                                return;
                            }
                            // 불일치: 다른 사람의 rLens, 스킵
                        } else {
                            // 최초 실행: 처음 발견된 rLens에 연결
                            _view.onScanResult(r);
                            return;
                        }
                    }
                }

                r = results.next() as BluetoothLowEnergy.ScanResult;
            }
        } catch (ex) {
        }
    }

    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        // System.println("onScanStateChange: state=" + scanState + " status=" + status);
        _view.onScanStateChange(scanState, status);
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        _view.onConnectedStateChanged(device, state);
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        // System.println("onProfileRegister: status=" + status);
        _view.onProfileRegister(uuid, status);
    }

    function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        // System.println("onCharacteristicWrite: status=" + status);
        _view.onCharacteristicWrite(characteristic, status);
    }

    //! Characteristic Changed 콜백 (NOTIFY용, iLens는 미사용)
    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        _view.onCharacteristicChanged(characteristic, value);
    }

    //! Characteristic Read 콜백 (iLens는 미사용)
    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        _view.onCharacteristicRead(characteristic, status, value);
    }

    //! Descriptor Read 콜백 (iLens는 미사용)
    function onDescriptorRead(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        _view.onDescriptorRead(descriptor, status, value);
    }

    //! Descriptor Write 콜백 (iLens는 미사용)
    function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        _view.onDescriptorWrite(descriptor, status);
    }
}
