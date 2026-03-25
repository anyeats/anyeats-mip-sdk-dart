# MDB Cashless Card Reader Protocol

MDB-RS232 브릿지 보드를 통한 캐시리스 카드 리더 통신 프로토콜 정리.

## 통신 구조

```
Android 보드 ←(RS232/USB 9600-8N1)→ MDB-RS232 브릿지 ←(MDB)→ Cashless Reader
```

### 통신 규칙

| 항목 | 값 |
|------|-----|
| Baud Rate | 9600 |
| Data Bits | 8 |
| Stop Bit | 1 |
| Parity | None |
| PC → 브릿지 | HEX 데이터 |
| 브릿지 → PC | ASCII 데이터 |

- POLL은 MDB-RS232 브릿지가 자동 처리 (PC에서 보낼 필요 없음)
- 결제 장치 이벤트는 자동으로 PC에 전송됨

---

## 카드 리더 상태 (6단계)

```
1. Inactive    → 전원 ON 또는 Reset 후 초기 상태
2. Disable     → Config 수신 후 또는 Disable 명령 수신 시
3. Enable      → Enable 명령 후, 카드 감지 대기
4. Session Idle → 유효한 카드 감지 시, Vend Request 대기
5. Vend Request → VMC로부터 Vend Request 수신 시
6. Vend        → 결제 승인 처리 중
```

---

## 명령어 목록

### VMC → Card Reader (PC에서 전송)

| 명령 | HEX 데이터 | 설명 |
|------|---------|------|
| Config | `110001000000` | 카드 리더 설정 (초기화) |
| Set Max/Min Price | `1101FFFF0000` | 최대/최소 결제 금액 설정 |
| Enable | `1401` | 카드 리더 활성화 (카드 감지 시작) |
| Disable | `1400` | 카드 리더 비활성화 |
| Cancel | `1402` | 현재 작업 취소 |
| Request Vend | `1300{PRICE}{ITEM}` | 결제 요청 (금액 + 상품번호 전송) |
| Vend Success | `1302{ITEM}` | 벤딩 성공 알림 (상품 배출 완료) |
| Vend Cancel | `1301` | 벤딩 취소 |
| Cash Sale | `1305{PRICE}{ITEM}` | 현금 판매 알림 |
| Session Complete | `1304` | 세션 종료 |
| Request Revalue | `1500` | 재충전 요청 |
| Request ID | `1700` | 리더 ID 요청 |

### Card Reader → VMC (PC에서 수신)

| 수신 데이터 | 설명 |
|---------|------|
| `03FFFE` | 유효한 카드 감지, Vend Selection 대기 |
| `05{AMOUNT}` | Vend 승인 확인 (승인 금액 포함) |
| `00` | ACK (명령 수신 확인) |
| `07` | Session Complete ACK |

---

## 결제 플로우 (전체 시퀀스)

### 1단계: 초기 설정 (앱 시작 시 1회)

```
VMC  → 110001000000     # Config: 카드 리더 설정
READER ← 010109720102070D94  # Config 응답 (리더 정보)

VMC  → 1101FFFF0000     # Set Max/Min Price (최대: 0xFFFF, 최소: 0x0000)
READER ← (응답 없음)
```

### 2단계: 카드 리더 활성화

```
VMC  → 1401             # Enable: 카드 감지 시작
```

### 3단계: 카드 감지 → 결제 요청

```
READER ← 03FFFE          # 유효한 카드 감지, Vend Selection 대기 (Session Idle)

VMC  → 1300000A0001     # Request Vend: 금액 0x000A(10), 상품번호 0x0001
READER ← 00              # ACK

READER ← 05000A          # Vend 승인 확인 (승인 금액: 0x000A = 10)
```

### 4단계: 벤딩 완료

```
VMC  → 13020001         # Vend Success: 상품번호 0x0001 배출 완료
READER ← (응답 없음)

VMC  → 1304             # Session Complete: 세션 종료
READER ← 07              # Session Complete ACK
```

### 결제 취소 시

```
VMC  → 1301             # Vend Cancel
```

---

## Request Vend 데이터 형식

```
13 00 {PRICE_H} {PRICE_L} {ITEM_H} {ITEM_L}
```

| 필드 | 바이트 | 설명 |
|------|--------|------|
| `13` | 1 | Vend 명령 그룹 |
| `00` | 1 | Sub-command: Request Vend |
| PRICE | 2 | 결제 금액 (Big Endian, 단위: 설정에 따라 다름) |
| ITEM | 2 | 상품 번호 |

### 예시

| 금액 | 상품번호 | HEX 명령 |
|------|---------|---------|
| 10 | 1 | `1300000A0001` |
| 100 | 2 | `130000640002` |
| 500 | 3 | `130001F40003` |
| 1000 | 1 | `130003E80001` |

---

## Vend Success 데이터 형식

```
13 02 {ITEM_H} {ITEM_L}
```

| 필드 | 바이트 | 설명 |
|------|--------|------|
| `13` | 1 | Vend 명령 그룹 |
| `02` | 1 | Sub-command: Vend Success |
| ITEM | 2 | 배출 완료된 상품 번호 |

---

## 에러/상태 처리

### 카드 리더 비활성 확인

카드 리더가 비활성 상태이면 리더가 주기적으로 상태를 보고함.
`0F05` 명령으로 상태를 읽을 수 있음.

### 명령 응답 없음 처리

MDB-RS232 브릿지 설계상 명령을 결제 장치에 포워딩하지만, 장치가 바쁜 경우 응답이 없을 수 있음.
응답이 없으면 재전송 필요 (실시간 명령이 아니므로 문제 없음).

### 타임아웃

명령 전송 후 응답 대기 타임아웃을 설정해야 함.
일반적으로 100~200ms 이내 응답.

---

## 참고

- 문서 출처: `docs/MDB_RS232_Quick_Start.pdf` (Shanghai Wafer Microelectronics, V2021-V9.2)
- MDB V4.2 프로토콜 기반
- 테스트 환경: Nayax MDB cashless reader
- Nayax 카드 리더 사용 시 원격 서버 연결 필수
