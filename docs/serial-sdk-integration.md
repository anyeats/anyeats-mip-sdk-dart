# GS805 Serial SDK 연동 가이드

ShakeBox 키오스크 앱(`shakebox-kiosk-app`)이 실제로 사용하는 형태를 기준으로 정리한
시리얼 SDK 연동 문서입니다. 외부 연동 개발자가 동일한 흐름으로 기기(GS805/GS801) 제어와
MDB 카드 결제를 구현할 수 있도록 작성되었습니다.

- **SDK 패키지**: `gs805serial` (`anyeats-mip-sdk-dart`)
- **언어/런타임**: Dart / Flutter (**Android 전용** — 시리얼 포트 접근)
- **대상 기기**: GS805 / GS801 (대형 Android 디스플레이 자판기)

---

## 1. 하드웨어 / 포트

| 용도 | 기본 포트 | 통신 | SDK 클래스 |
|------|-----------|------|-----------|
| 기기 제어 (Machine) | `/dev/ttyS7` | 9600bps, 8N1 | `GS805Serial` |
| MDB 카드 결제 (Cashless) | `/dev/ttyS9` | MDB-RS232 | `MdbCashless` |

- 두 포트는 **독립된 인스턴스**로 각각 연결/관리합니다.
- `GS805Serial`은 연결 끊김 시 **자동 재연결**을 지원합니다. `MdbCashless`는 **수동 재연결**입니다.

---

## 2. 의존성

```yaml
# pubspec.yaml
dependencies:
  gs805serial:
    git:
      url: https://github.com/anyeats/anyeats-mip-sdk-dart.git
      ref: main
```

```dart
import 'package:gs805serial/gs805serial.dart';
```

---

## 3. 기기 제어 — `GS805Serial`

### 3.1 연결 수명주기

```dart
final gs805 = GS805Serial(/* 옵션 */);

// 1) 포트 목록 조회 후 연결 (키오스크는 첫 디바이스에 연결)
final devices = await gs805.listDevices();
await gs805.connect(devices.first);   // 또는 connectToFirstDevice()

// 2) 상태/이벤트 스트림 구독
gs805.connectionStateStream.listen((connected) { /* 연결 상태 */ });
gs805.eventStream.listen((event) { /* MachineEvent */ });
gs805.reconnectEventStream.listen((event) { /* 재연결 이벤트 */ });

// 3) 종료
await gs805.disconnect();
await gs805.dispose();
```

| 메서드 | 설명 |
|--------|------|
| `listDevices()` | 연결 가능한 시리얼 디바이스 목록 |
| `connect(device)` / `connectToFirstDevice()` | 연결 |
| `disconnect()` / `reconnect()` / `dispose()` | 해제 / 재연결 / 정리 |
| `isConnected` | 연결 여부 |
| `connectionStateStream` | 연결 상태(`bool`) 스트림 |
| `eventStream` | 기기 이벤트(`MachineEvent`) 스트림 |
| `reconnectEventStream` | 자동 재연결 이벤트 스트림 |

### 3.2 음료 제조 (레시피 + 제조)

제조는 **`setDrinkRecipeTime` → (대기) → `makeDrink`** 순서입니다.

```dart
// 8채널 레시피. 각 채널은 (재료시간, 물량) 쌍. 단위: 0.1초(ds).
// 채널0의 물량(두 번째 값)이 물, 각 채널의 첫 값이 파우더 재료.
final channelTimes = <(int material, int water)>[
  (0, waterDs),  // ch0: 물 (+ ch0 재료)
  (0, 0),        // ch1..ch7: 파우더 재료
  (0, 0), (0, 0), (0, 0), (0, 0), (0, 0), (0, 0),
];

await gs805.setDrinkRecipeTime(DrinkNumber.hotDrink1, channelTimes);
await Future.delayed(const Duration(milliseconds: 500)); // ★ 아래 주의 참고
await gs805.makeDrink(DrinkNumber.hotDrink1);
```

- **온수/냉수**: `DrinkNumber.hotDrink1`(0x01) / `coldDrink1`(0x11). (hotDrink1~7, coldDrink1~7)
- **단위 변환 ⚠️**: 상위 시스템(API/레시피)은 **cs(centisecond, 100=1초)**, SDK는 **ds(decisecond, 10=1초)** 입니다.
  → **`ds = cs ÷ 10`**. 예: 레시피 1000cs(10초) → SDK 100.
- **`setDrinkRecipeTime` 직후 `makeDrink`를 곧장 보내면 첫 `makeDrink`가 무시(drop)될 수 있습니다.**
  사이에 **300~500ms 지연**을 둘 것 (펌웨어가 레시피 처리 중 들어온 제조 명령을 무시하는 현상).

### 3.3 제조 진행 추적 (폴링)

WebSocket/푸시가 없으므로 **폴링**으로 진행 상태를 추적합니다.

```dart
// 약 250ms~1s 간격 폴링
final ms = await gs805.getMachineStatus();    // ms.isReady / ms.isError / ms.message
final cs = await gs805.getControllerStatus(); // 컵 센서
// final ds = await gs805.getDrinkStatus();   // ⚠ GS801 만. GS805 는 0x1F 무응답(timeout)

final cupPlaced   = cs.isCupPlaced;    // 픽업대에 컵이 놓임
final cupOnHolder = cs.isCupOnHolder;  // 홀더(제조 위치)에 컵 존재
final noCup       = cs.hasNoCup;       // 컵 없음
```

| 메서드 | 반환 | 주요 필드 |
|--------|------|----------|
| `getMachineStatus()` | `MachineStatus` | `isReady`, `isError`, `code`, `message` |
| `getControllerStatus()` | `ControllerStatus` | `isCupPlaced`, `isCupOnHolder`, `hasNoCup`, `isIdle`, `isBusy` |
| `getDrinkStatus()` | `DrinkPreparationStatus` | `isCupPlaced` 등 (**GS801 전용**) |

> **GS805 vs GS801**: GS805는 `getDrinkStatus`(0x1F)에 응답하지 않아 매번 timeout이 발생합니다.
> GS805에서는 `getDrinkStatus`를 **건너뛰고** `getMachineStatus` + `getControllerStatus`로 판별하세요.

**제조 완료 판별(권장 패턴)**: `isCupPlaced=true`(컵 픽업대 도착) → 사용자에게 "가져가세요" 안내 →
`isCupOnHolder=false`(컵 수령됨) → 완료 처리.

### 3.4 유지보수 / 기타 명령

| 메서드 | 기능 |
|--------|------|
| `cleanAllPipes()` | 전체 배관 세척 (0x0A) |
| `cleanSpecificPipe(pipeNumber)` | 특정 배관 세척 (0x12) |
| `cupDelivery(waitTimeSeconds)` | 컵 픽업대로 재배출 (0x24) |
| `openPickupDoor()` / `closePickupDoor()` | 픽업 도어 제어 |
| `lockDoor()` / `unlockDoor()` / `getLockStatus()` | 전면 도어 잠금 |
| `setHotTemperature(hi, lo)` / `setColdTemperature(hi, lo)` | 온수/냉수 온도 설정 |
| `getErrorCode()` / `getErrorInfo()` | 에러 코드/상세 조회 |
| `forceStopDrinkProcess()` | 제조 사이클 강제 종료 (비상 탈출) |
| `setCupDropMode()` / `testCupDrop()` / `autoInspection()` | 컵 배출 모드 / 테스트 / 자가점검 |

> **물만 배출(테스트)**: 파우더 채널을 모두 0으로 두고 `setDrinkRecipeTime`의 ch0 물량만 채운 뒤
> `makeDrink`하면 물만 배출됩니다. (유지보수 화면에서 사용하는 방식)

---

## 4. MDB 카드 결제 — `MdbCashless`

### 4.1 연결 / 초기화

```dart
final mdb = MdbCashless();

final devices = await mdb.listDevices();
await mdb.connect(devices.first);     // /dev/ttyS9
await mdb.setup();                    // Config + Max/Min Price (enable 아님)

mdb.eventStream.listen((CashlessEvent e) {
  // e.type (CashlessEventType), e.state (CashlessState), e.data
});
```

> **앱 시작 시점**: `connect` → `setup`까지만. **`enable`은 결제 시작 시점에** 호출합니다.

### 4.2 결제(Vend) 흐름

```
enable()                         // 카드 수신 시작 → "카드를 넣어주세요"
  └─ event: cardDetected         // 카드 인식 (잔액 통보) → 세션 시작
requestVend(price, itemNumber)   // 승인 요청
  ├─ event: vendApproved         // 승인 → 제조 진행
  │     └─ vendSuccess(itemNumber)   // 제조/배출 성공 통보
  │     └─ sessionComplete()         // 세션 종료
  └─ event: vendDenied           // 거절 → 세션 정리
취소/실패 시: vendCancel() 또는 resetMdb()
```

| 메서드 | 기능 |
|--------|------|
| `setup({maxPrice, minPrice})` | Config + Max/Min Price 설정 |
| `enable()` / `disable()` | 카드 수신 시작 / 중단 |
| `requestVend({price, itemNumber})` | 승인 요청 |
| `vendSuccess({itemNumber})` | 배출 성공 통보 |
| `vendCancel()` / `cancel()` | 배출 취소 / 현재 작업 강제 취소 |
| `sessionComplete()` | 세션 완료 |
| `sendRawHex(bytes)` | 원시 명령 전송 (reset 등) |

**MDB 초기화(reset)** — 취소/실패/완료 후 확실한 정리:

```dart
try { await mdb.disable(); } catch (_) {}
await mdb.sendRawHex([0x10]);                       // Reset
await Future.delayed(const Duration(milliseconds: 300));
await mdb.setup();                                  // 재초기화 (enable 안 함)
```

### 4.3 이벤트 / 상태

`CashlessEventType`: `stateChanged`, `cardDetected`, `vendApproved`, `vendDenied`,
`sessionCancelled`, `sessionCompleted`, `configReceived`, `readerIdReceived`,
`error`, `rawData`, `commandSent`, `ackReceived`

`CashlessState`: `inactive` → `disabled` → `enabled` → `sessionIdle` → `vendRequested` → `vending` (그 외 `error`)

### 4.4 MDB 프로토콜 (참고 — 원시 HEX)

| 명령 (앱→리더) | HEX | SDK |
|------|-----|-----|
| Config | `11 00 01 00 00 00` | `setup()` 내부 |
| Max/Min Price | `11 01 FF FF 00 00` | `setup()` 내부 |
| Enable | `14 01` | `enable()` |
| Disable | `14 00` | `disable()` |
| Cancel | `14 02` | `cancel()` |
| Request Vend | `13 00 PP PP II II` | `requestVend(price, item)` |
| Vend Success | `13 02 II II` | `vendSuccess(item)` |
| Vend Cancel | `13 01` | `vendCancel()` |
| Session Complete | `13 04` | `sessionComplete()` |
| Reset | `10` | `sendRawHex([0x10])` |

| 응답 (리더→앱) | 코드 | 이벤트 |
|------|------|--------|
| 카드 인식(잔액) | `03 FF FF` | `cardDetected` |
| 승인(금액) | `05 AA AA` | `vendApproved` |
| 거절 | `06` | `vendDenied` |
| 세션 취소 | `07` / `09` | `sessionCancelled` |

---

## 5. 전체 흐름 (카드 결제 + 제조)

```
[결제]
  mdb.enable()                          → "카드를 넣어주세요"
  event cardDetected                    → 상품/금액 표시
  mdb.requestVend(price, item)
  event vendApproved
[제조]
  gs805.setDrinkRecipeTime(drink, times)
  (500ms 대기)
  gs805.makeDrink(drink)
  loop: getMachineStatus + getControllerStatus
        isCupPlaced=true   → "음료를 가져가세요"
        isCupOnHolder=false → 수령 완료
[정산/정리]
  mdb.vendSuccess(item) → mdb 초기화(0x10 + setup)
  (서버 주문/배달 보고)
[취소·실패]
  gs805.forceStopDrinkProcess() (제조 중이면)
  mdb.vendCancel() / resetMdb()
```

---

## 6. 단위 / 규약 요약

- **레시피 시간 단위**: 상위 cs(100=1초) ÷ 10 = SDK ds(10=1초). `setDrinkRecipeTime`은 ds.
- **채널 매핑**: 8채널 `(재료, 물량)` 쌍. **ch0의 물량 = 물**, 각 채널 첫 값 = 파우더.
- **온수/냉수**: `DrinkNumber.hotDrinkN`(0x01~) / `coldDrinkN`(0x11~).
- **`setDrinkRecipeTime` → `makeDrink` 사이 300~500ms 지연 필수.**
- **GS805는 `getDrinkStatus` 미응답** → `getMachineStatus`+`getControllerStatus`로 대체.
- **상태 갱신은 폴링**(WebSocket/푸시 없음).
- **재연결**: GS805 자동 / MDB 수동.

---

## 7. 주의사항

- Android 전용(시리얼 포트 권한 필요). Windows/iOS/Web 미지원.
- 명령은 SDK 내부 큐를 통해 순차 처리됩니다. (`pauseQueue`/`resumeQueue`/`clearQueue` 제공)
- 통신 오류 시 각 명령은 예외를 던지므로 `try/catch`로 감싸고, 결제 흐름에서는 실패 시
  반드시 `resetMdb`로 리더 상태를 정리해 "결제 대기" 잔존을 방지하세요.
- 디버깅: `setLogLevel`, `exportLogs`, `messageStream`(원시 응답), `queueEventStream` 활용.
