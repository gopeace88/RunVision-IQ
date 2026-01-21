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

    // Debug logs - BLE와 TX 분리 (각 4줄)
    // ✅ DEBUG MODE: 로그 배열 크기 8로 증가 (4→8)
    private var _bleDebugLogs as Lang.Array<Lang.String> = ["", "", "", "", "", "", "", ""];
    private var _txDebugLogs as Lang.Array<Lang.String> = ["", "", "", "", "", "", "", ""];
    private var _bleLogIndex as Lang.Number = 0;
    private var _txLogIndex as Lang.Number = 0;

    // Display labels
    private var _speedLabel as Lang.String = "---";
    private var _hrLabel as Lang.String = "---";
    private var _cadenceLabel as Lang.String = "---";
    private var _distanceLabel as Lang.String = "0.00";
    private var _timeLabel as Lang.String = "0:00";
    private var _paceLabel as Lang.String = "--:--";

    // Statistics tracking
    private var _totalSpeed as Lang.Float = 0.0;
    private var _speedSamples as Lang.Number = 0;
    private var _avgSpeedLabel as Lang.String = "---";
    private var _maxHeartRate as Lang.Number = 0;
    private var _maxHrLabel as Lang.String = "---";

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

    // Write Queue (Flutter 방식: 1초마다 모든 메트릭 순차 전송)
    private var _writeQueue as Lang.Array<Lang.ByteArray> = [] as Lang.Array<Lang.ByteArray>;
    private var _isWriting as Lang.Boolean = false;  // Write 진행 중 플래그

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

    // ✅ Pairing 타임아웃 (Connecting 상태 멈춤 방지)
    private var _pairingStartTime as Lang.Number = 0;        // 페어링 시작 시간 (초)
    private var _pairingRetryCount as Lang.Number = 0;       // 페어링 재시도 횟수
    private const PAIRING_TIMEOUT_SEC = 3;                   // 3초 타임아웃
    private const PAIRING_MAX_RETRIES = 3;                   // 최대 3회 재시도

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
            addBleLog("READY");
        } catch (ex) {
            _scanStatus = "INIT_ERR";
            addBleLog("ERR:init");
        }
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
                        addBleLog("UNPAIR");
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
                addBleLog("SCAN");
            } catch (ex) {
                _scanStatus = "SCAN_ERR";
                addBleLog("ERR:scan");
            }
        } catch (ex) {
            _scanStatus = "ERR:init";
            addBleLog("ERR:init");
        }
    }

    //! Add BLE debug log (최대 8줄, 순환) - DEBUG MODE
    public function addBleLog(msg as Lang.String) as Void {
        _bleDebugLogs[_bleLogIndex] = msg;
        _bleLogIndex = (_bleLogIndex + 1) % 8;
        try {
            WatchUi.requestUpdate();
        } catch (e) {
            // UI가 아직 준비되지 않았을 수 있음
        }
    }

    //! Add TX debug log (최대 8줄, 순환) - DEBUG MODE
    private function addTxLog(msg as Lang.String) as Void {
        _txDebugLogs[_txLogIndex] = msg;
        _txLogIndex = (_txLogIndex + 1) % 8;
        try {
            WatchUi.requestUpdate();
        } catch (e) {
            // UI가 아직 준비되지 않았을 수 있음
        }
    }

    //! Called when activity is started
    function onTimerStart() as Void {
        // DFLogger.reset();
        // DFLogger.log("=== Activity Started ===");

        addBleLog("START");

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
        addBleLog("STOP");
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
        // Reset statistics
        _totalSpeed = 0.0;
        _speedSamples = 0;
        _maxHeartRate = 0;
        _avgSpeedLabel = "---";
        _maxHrLabel = "---";
        _paceLabel = "--:--";
        _distanceLabel = "0.00";
        _timeLabel = "0:00";
        _speedLabel = "---";
        _hrLabel = "---";
        _cadenceLabel = "---";
        _devicesFound = 0;
        _elapsedSeconds = 0;  // ✅ 경과 시간 초기화
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
                addBleLog("RESCAN");
            } catch (ex) {
                addBleLog("ERR:rescan");
            }
        }

        // ✅ Pairing 타임아웃 (Connecting 상태 멈춤 방지)
        // iLens가 다른 기기에 연결되었다가 올 때 연결이 안 되는 문제 해결
        if (_pairingStartTime > 0 && !_isConnected) {
            var pairingDuration = _elapsedSeconds - _pairingStartTime;
            if (pairingDuration >= PAIRING_TIMEOUT_SEC) {
                _pairingRetryCount++;
                addBleLog("PAIR_TO:" + _pairingRetryCount);  // Pairing Timeout + retry count
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
                    addBleLog("CONN_ERR");
                } else {
                    // 재시도: 즉시 다시 pairing
                    _scanStatus = "RETRY " + _pairingRetryCount;
                    if (_lastScanResult != null) {
                        try {
                            _pairingStartTime = _elapsedSeconds;
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
                    addBleLog("RE:" + _reconnectAttempts);
                    _scanStatus = "RECONN " + _reconnectAttempts;
                    try {
                        _pairingStartTime = _elapsedSeconds;  // ✅ 타임아웃 추적 시작
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
                    addBleLog("RESCAN:" + _reconnectAttempts);
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
                addBleLog("CHAR OK");
                _scanStatus = "READY";
            } catch (ex) {
                _charRetryCount++;
                if (_charRetryCount >= 5) {
                    // 5회 실패 → 재연결 트리거
                    _charRetryCount = 0;
                    _isConnected = false;
                    _connectedDevice = null;
                    _scanStatus = "RECONN...";
                    addBleLog("RECONN");
                    // → auto-reconnect 로직이 다음 compute에서 동작
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
        var speedKmh = 0;
        var paceSeconds = 0;  // ← Pace를 초 단위로 저장 (iLens 전송용)
        var speedValid = speedMs != null && speedMs > 0;

        if (speedValid) {
            speedKmh = ((speedMs * 3.6) + 0.5).toNumber();  // ✅ 반올림
            _speedLabel = speedKmh.format("%d");

            // Calculate pace (min/km) - 러너들은 Pace에 익숙
            var paceMinPerKm = 60.0 / (speedMs * 3.6);
            var paceMin = paceMinPerKm.toNumber();
            var paceSec = ((paceMinPerKm - paceMin) * 60).toNumber();
            _paceLabel = paceMin.format("%d") + ":" + paceSec.format("%02d");

            // iLens 전송용: Pace를 총 초로 변환 (예: 4:25 → 265초)
            // iLens 펌웨어가 60으로 나눠서 표시: 265 / 60 = 4.42
            paceSeconds = paceMin * 60 + paceSec;

            // Update average speed
            _totalSpeed += speedMs * 3.6;
            _speedSamples++;
            var avgSpeed = (_totalSpeed / _speedSamples).toNumber();
            _avgSpeedLabel = avgSpeed.format("%d");
        } else {
            _speedLabel = "0";
            _paceLabel = "--:--";
        }

        // Get current heart rate (ActiveLook 패턴)
        var hr = info != null && info has :currentHeartRate ? info.currentHeartRate : null;
        var hrValid = hr != null && hr > 0;
        if (hrValid) {
            _hrLabel = hr.format("%d");

            // Track max heart rate
            if (hr > _maxHeartRate) {
                _maxHeartRate = hr;
                _maxHrLabel = hr.format("%d");
            }
        } else {
            _hrLabel = "---";
            hr = 0;
        }

        // Get current cadence (ActiveLook 패턴)
        var cadence = info != null && info has :currentCadence ? info.currentCadence : null;
        var cadenceValid = cadence != null && cadence > 0;
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

        // 3. Running Power 계산 (속도와 거리가 유효할 때만)
        if (speedValid && distanceValid && altitude != null) {
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

        // ========== iLens 전송: Queue 방식 (Flutter와 동일) ==========
        // 1초마다 모든 메트릭을 queue에 추가 → 순차 전송
        // iLens는 WRITE_WITH_RESPONSE만 지원 → onCharacteristicWrite() callback에서 다음 패킷 전송
        if (_isConnected && _exerciseCharacteristic != null) {
            try {
                // 1. Write 진행 중이 아닐 때만 queue 초기화
                if (!_isWriting) {
                    _writeQueue = [] as Lang.Array<Lang.ByteArray>;

                    // Queue에 5개 메트릭 추가 (v1.0.2: Sport Time 사용, Power/Current Time 제거)
                    _writeQueue.add(ILensProtocol.createExerciseTimePacket(_elapsedSeconds));  // ⭐ Sport Time (0x03)
                    _writeQueue.add(ILensProtocol.createVelocityPacket(paceSeconds));          // Pace
                    _writeQueue.add(ILensProtocol.createHeartRatePacket(hr));                  // Heart Rate
                    _writeQueue.add(ILensProtocol.createCadencePacket(cadence));              // Cadence
                    _writeQueue.add(ILensProtocol.createDistancePacket(distance != null ? distance : 0));  // Distance

                    // DFLogger.log("[TX] pace=" + paceSeconds + " hr=" + hr + " cad=" + cadence + " pwr=" + power);

                    // 화면에 핵심 메트릭만 표시
                    addTxLog("P:" + _paceLabel + " T:" + _timeLabel);

                    processWriteQueue();
                }
            } catch (ex) {
                addTxLog("q:err");
                // DFLogger.logError("QUEUE", "Queue error");
            }
        }
    }

    //! Draw the data field
    //! @param dc Device context
    function onUpdate(dc as Graphics.Dc) as Void {
        // Set background color
        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        try {
            var width = dc.getWidth();
            var height = dc.getHeight();
            var centerX = width / 2;
            var centerY = height / 2;

            // 로고 표시 (중앙, 176x37)
            var logo = WatchUi.loadResource(Rez.Drawables.RunVisionLogo);
            dc.drawBitmap(centerX - 88, centerY - 40, logo);

            // 상태 텍스트 (로고 아래)
            var statusText = _isConnected ? "Connected" : _scanStatus;
            dc.drawText(centerX, centerY + 10, Graphics.FONT_SMALL, statusText, Graphics.TEXT_JUSTIFY_CENTER);

        } catch (ex) {
            dc.drawText(dc.getWidth() / 2, 50, Graphics.FONT_SMALL, "ERROR", Graphics.TEXT_JUSTIFY_CENTER);
        }
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
            addTxLog("ERR:wr");
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
                addBleLog("MODE:DEFAULT");
            } else {
                // 빠른 기기 → WITH_RESPONSE 유지
                addBleLog("MODE:RESPONSE");
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
            _scanStatus = "CONNECTED";
            addBleLog("CONN OK");
            // DFLogger.logBle("CONNECTED", "Device connected");
        } else {
            _isConnected = false;
            _connectedDevice = null;
            _exerciseCharacteristic = null;
            _charRetryCount = 0;  // 재시도 카운터 리셋
            _connectionStartTime = 0;
            _pairingStartTime = 0;  // ✅ 타임아웃 추적 종료
            // 속도 감지 리셋 (재연결 시 다시 측정)
            _useDefaultWrite = false;
            _writeStartTime = 0;
            _speedDetected = false;
            _scanStatus = "DISCONN";
            addBleLog("DISCONN");

            // Auto-reconnect 시작
            if (_autoReconnectEnabled) {
                _needsReconnect = true;
                _lastReconnectTime = _elapsedSeconds;
                _isReconnecting = false;
                addBleLog("RECONN..");
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
                    System.println("[RETRY " + i + "] Service still null");
                } else {
                    System.println("[RETRY " + i + "] Service found!");
                }
            } else {
                var characteristic = service.getCharacteristic(characteristicUuid);
                if (characteristic != null) {
                    // ✅ 성공 시 즉시 리턴
                    System.println("tryGetServiceCharacteristic: success at retry " + i);
                    return characteristic;
                } else {
                    System.println("[RETRY " + i + "] Service OK but Char null");
                }
            }
        }

        // ✅ nbRetry번 실패 시 예외 발생
        if (service == null) {
            System.println("FINAL: Service is NULL");
            throw new Lang.InvalidValueException(
                "(E) Could not get service after " + nbRetry + " retries"
            );
        }
        System.println("FINAL: Service OK but Characteristic is NULL");
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
            addTxLog("ERR:tx");
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
                addBleLog("SCANNING");
            } catch (ex) {
                _scanStatus = "SCAN_ERR";
            }
        } else {
            _scanStatus = "PROF_FAIL";
        }

        WatchUi.requestUpdate();
    }

    //! Called when iLens device is found during scanning
    function onScanResult(scanResult as BluetoothLowEnergy.ScanResult) as Void {
        addBleLog("FOUND");
        System.println("iLens found, RSSI=" + scanResult.getRssi());

        // Auto-connect
        if (!_isConnected && _connectedDevice == null) {
            _devicesFound++;
            _lastScanResult = scanResult;

            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

            addBleLog("PAIRING");
            _pairingStartTime = _elapsedSeconds;  // ✅ 타임아웃 추적 시작
            _connectedDevice = BluetoothLowEnergy.pairDevice(scanResult);

            if (_connectedDevice == null) {
                _scanStatus = "PAIR_FAIL";
                _pairingStartTime = 0;  // 실패 시 리셋
            } else {
                _scanStatus = "PAIRING";
            }
        }

        WatchUi.requestUpdate();
    }

    //! Called when scan state changes
    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
            if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
                _scanStatus = "SCANNING";
            } else {
                _scanStatus = "SCAN_ERR";
            }
        } else if (scanState == BluetoothLowEnergy.SCAN_STATE_OFF) {
            // 스캔 중지 = 기기 찾음, 연결 시도 중
            _scanStatus = "Connecting...";
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

}

//! BLE Delegate - 별도 클래스 (DataField는 다중 상속 불가)
class RunVisionBleDelegate extends BluetoothLowEnergy.BleDelegate {
    private var _view;

    function initialize(view) {
        BleDelegate.initialize();
        _view = view;
        // System.println("RunVisionBleDelegate initialized");
    }

    //! iLens 기기 식별: raw data 전체에서 "ilens" 검색 (case-insensitive)
    function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
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

                // "ilens" 또는 "rlens" 포함 시 인식 (case-insensitive, 하위호환)
                // FIX: find()는 못 찾으면 -1 반환 (null 아님!)
                var lowerStr = rawStr.toLower();
                if (lowerStr.find("ilens") != -1 || lowerStr.find("rlens") != -1) {
                    _view.onScanResult(r);
                    return;  // 찾으면 즉시 종료
                }
            }

            r = results.next() as BluetoothLowEnergy.ScanResult;
        }
    }

    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        // System.println("onScanStateChange: state=" + scanState + " status=" + status);
        _view.onScanStateChange(scanState, status);
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        _view.addBleLog("ST:" + state);
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
