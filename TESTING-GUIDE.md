# RunVision-IQ 테스트 가이드

## ✅ 설치 확인

Connect IQ 앱이 워치에 설치되어 아이콘이 표시되는 것을 확인했습니다!

---

## 📱 테스트 단계

### 1. 러닝 Activity 시작

1. **워치에서 러닝 Activity 시작**
   - "Run" 앱 실행
   - "Start" 버튼 누르기

2. **DataField 추가**
   - Activity 시작 전 또는 중에 "Settings" → "Data Screens" 선택
   - "RunVision-IQ" DataField 추가

### 2. 화면 확인

**예상 화면 구성**:
```
┌─────────────────┐
│  SCAN:INIT      │  ← BLE 상태
│  init:setup     │  ← 디버그 로그
│  init:done      │
│  prof:start     │
│  prof:ok        │
├─────────────────┤
│  Spd    Pace    │
│  ---    --:--   │
├─────────────────┤
│  HR     Cad     │
│  ---    ---     │
├─────────────────┤
│  Dist   Time    │
│  0.00   0:00    │
├─────────────────┤
│  Avg    Max     │
│  ---    ---     │
└─────────────────┘
```

### 3. BLE 연결 확인

**정상 흐름**:
1. `init:setup` → `init:done`
2. `prof:start` → `prof:ok`
3. `scan:starting` → `scan:OK` 또는 `scan:SCANNING`
4. iLens 기기 발견 시: `dev:1` → `connecting...`
5. 연결 성공: `SCAN:CONNECTED` 또는 `iLens:OK`

**에러 상황**:
- `scan:err` → `err:no_prof` (프로필 부족)
- `scan:err` → `err:WRITE_FAIL` (BLE 권한 문제)
- `ble:error` → BLE 에러 발생

### 4. iLens 연결 확인

**iLens 기기 준비**:
- iLens AR 글래스 전원 켜기
- BLE 페어링 모드 활성화
- 기기 이름이 "iLens-XXXX" 형식인지 확인

**연결 확인**:
- 화면에 `SCAN:CONNECTED` 또는 `iLens:OK` 표시
- 디버그 로그에 `conn:ok` 표시

### 5. 데이터 전송 확인

**러닝 시작 후**:
- 속도, 심박수, 케이던스 등이 화면에 표시됨
- iLens 화면에도 동일한 데이터가 표시되어야 함
- 1초마다 업데이트됨

---

## 🐛 문제 해결

### 문제 1: "SCAN:SCAN_ERR" 계속 표시

**원인**: 프로필 등록 실패 또는 BLE 권한 문제

**해결**:
1. 워치 재시작
2. Connect IQ 앱 재설치
3. BLE 권한 확인 (Settings → Apps → RunVision-IQ)

### 문제 2: "SCAN:SCANNING"이지만 기기 발견 안 됨

**원인**: iLens 기기가 스캔 범위 밖이거나 전원이 꺼져 있음

**해결**:
1. iLens 기기 전원 확인
2. 워치와 iLens 거리 확인 (1m 이내 권장)
3. iLens 기기 이름이 "iLens-XXXX" 형식인지 확인

### 문제 3: 연결은 되지만 데이터가 전송 안 됨

**원인**: Characteristic 발견 실패 또는 전송 에러

**해결**:
1. 디버그 로그에서 `write:fail` 확인
2. iLens 기기 재시작
3. 워치에서 연결 해제 후 재연결

### 문제 4: 속도/심박수 등이 "---"로 표시됨

**원인**: Activity가 시작되지 않았거나 센서 데이터가 없음

**해결**:
1. Activity가 실제로 시작되었는지 확인
2. GPS 신호 확인 (실외에서 테스트)
3. 심박수 센서 착용 확인

---

## 📊 예상 동작

### 정상 동작 시퀀스

```
1. Activity 시작
   → onTimerStart() 호출
   → "timer:start" 로그

2. 프로필 등록 (약 1-2초)
   → "prof:start" → "prof:ok"

3. BLE 스캔 시작
   → "scan:starting" → "scan:OK"
   → "SCAN:SCANNING" 상태

4. iLens 기기 발견 (약 5-10초)
   → "dev:1" → 기기 이름 표시
   → "connecting..."

5. 연결 완료
   → "conn:ok"
   → "SCAN:CONNECTED" 또는 "iLens:OK"

6. 데이터 전송 시작
   → 1초마다 속도, 심박수, 케이던스 전송
   → 화면에 실시간 데이터 표시
```

---

## 🔍 디버그 로그 해석

| 로그 메시지     | 의미             | 다음 단계                                |
| --------------- | ---------------- | ---------------------------------------- |
| `init:setup`    | 초기화 시작      | 대기                                     |
| `init:done`     | 초기화 완료      | 대기                                     |
| `prof:start`    | 프로필 등록 시작 | 대기                                     |
| `prof:ok`       | 프로필 등록 완료 | 스캔 시작 예정                           |
| `scan:starting` | 스캔 시작 시도   | 대기                                     |
| `scan:OK`       | 스캔 성공        | 기기 발견 대기                           |
| `scan:err`      | 스캔 에러        | `err:no_prof` 또는 `err:WRITE_FAIL` 확인 |
| `dev:1`         | 기기 발견        | 연결 시도 예정                           |
| `connecting...` | 연결 시도 중     | 대기                                     |
| `conn:ok`       | 연결 성공        | 데이터 전송 시작                         |
| `write:fail`    | 전송 실패        | 재연결 시도                              |

---

## ✅ 체크리스트

테스트 전 확인:
- [ ] Connect IQ 앱이 워치에 설치됨
- [ ] iLens AR 글래스 전원 켜짐
- [ ] 워치와 iLens 거리 1m 이내
- [ ] 러닝 Activity 준비됨

테스트 중 확인:
- [ ] 프로필 등록 완료 (`prof:ok`)
- [ ] BLE 스캔 시작 (`scan:OK`)
- [ ] iLens 기기 발견 (`dev:1`)
- [ ] 연결 성공 (`conn:ok`)
- [ ] 데이터 전송 중 (화면 업데이트)

---

## 📝 테스트 결과 기록

테스트 후 다음 정보를 기록하세요:

1. **연결 시간**: Activity 시작부터 연결 완료까지 시간
2. **발견된 기기 수**: `dev:X`에서 X 값
3. **에러 발생 여부**: 에러 메시지 기록
4. **데이터 전송 확인**: iLens 화면에 데이터 표시 여부
5. **안정성**: 연결 유지 시간 및 끊김 발생 여부

---

## 🎯 다음 단계

테스트가 성공하면:
1. 실제 러닝 테스트 (실외 GPS)
2. 장시간 테스트 (배터리 소모 확인)
3. 다양한 조건 테스트 (실내/실외, 다양한 속도)

문제가 발생하면:
1. 디버그 로그 메시지 확인
2. 위의 "문제 해결" 섹션 참고
3. 필요시 코드 수정 및 재빌드

