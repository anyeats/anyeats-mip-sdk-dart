# GS805 Serial Communication Plugin 구현 계획

## 프로젝트 개요
GS805 커피 머신의 시리얼 통신 프로토콜을 구현하는 Flutter 플러그인

### 프로토콜 사양
- **통신 방식**: UART 시리얼 포트 (RS232 레벨)
- **보드레이트**: 9600 baud
- **데이터 형식**: 8 데이터 비트, 1 스톱 비트, 패리티 없음 (8N1)
- **타임아웃**: 100ms (재전송 메커니즘)
- **바이트 순서**: Big Endian

---

## 단계별 구현 계획

### ✅ 1단계: 프로젝트 구조 및 기본 상수 정의
**목표**: 프로토콜의 기본 상수와 구조체 정의

**작업 내용**:
- [x] 프로토콜 상수 클래스 작성 (`lib/src/protocol/gs805_constants.dart`)
  - FLAG1: 0xAA55 (명령 헤더)
  - FLAG2: 0xA55A (응답 헤더)
  - 명령 코드 (COMND) 정의
  - 응답 상태 코드 (STA) 정의
- [x] 디렉토리 구조 설정
  ```
  lib/
  ├── src/
  │   ├── protocol/
  │   │   ├── gs805_constants.dart
  │   │   ├── gs805_protocol.dart
  │   │   └── gs805_message.dart
  │   ├── serial/
  │   │   ├── serial_connection.dart (추상 인터페이스)
  │   │   └── usb_serial_connection.dart (usb_serial 구현체)
  │   ├── models/
  │   │   ├── drink_info.dart
  │   │   ├── machine_status.dart
  │   │   └── error_code.dart
  │   └── exceptions/
  │       └── gs805_exception.dart
  └── gs805serial.dart
  ```

---

### ✅ 2단계: 프로토콜 메시지 인코딩/디코딩
**목표**: 바이트 스트림 생성 및 파싱 로직 구현

**작업 내용**:
- [x] 메시지 클래스 작성 (`lib/src/protocol/gs805_message.dart`)
  - `CommandMessage` 클래스 (명령 메시지)
  - `ResponseMessage` 클래스 (응답 메시지)
- [x] 프로토콜 인코더/디코더 작성 (`lib/src/protocol/gs805_protocol.dart`)
  - 체크섬(SUM) 계산 함수
  - 명령 메시지 인코딩 (바이트 배열 생성)
  - 응답 메시지 디코딩 (바이트 배열 파싱)
  - Big Endian 변환 유틸리티
- [x] 단위 테스트 작성 (`test/protocol_test.dart`)

---

### ✅ 3단계: 데이터 모델 정의
**목표**: 주요 데이터 구조체 및 Enum 정의

**작업 내용**:
- [x] 음료 정보 모델 (`lib/src/models/drink_info.dart`)
  - 음료 번호 (DrinkNumber enum)
  - 온도 설정
  - 가격 정보
  - 판매 통계
- [x] 기기 상태 모델 (`lib/src/models/machine_status.dart`)
  - 상태 enum (대기/제조중/오류 등)
  - 온도 정보
  - 잔액 정보
- [x] 오류 코드 모델 (`lib/src/models/error_code.dart`)
  - 오류 비트 플래그
  - 오류 메시지 매핑
- [x] 예외 클래스 (`lib/src/exceptions/gs805_exception.dart`)

---

### ✅ 4단계: USB Serial 패키지 통합
**목표**: Flutter USB Serial 패키지를 이용한 통신 레이어 구현

**작업 내용**:
- [x] `pubspec.yaml`에 의존성 추가
  ```yaml
  dependencies:
    usb_serial: ^0.5.2
  ```
- [x] 시리얼 통신 래퍼 클래스 작성
  - `serial_connection.dart` - 추상 인터페이스
  - `usb_serial_connection.dart` - USB Serial 구현체
  - USB 디바이스 검색 및 선택
  - 포트 열기/닫기
  - 보드레이트 설정 (9600, 8N1)
  - 데이터 송수신
  - 수신 데이터 스트림 관리
- [x] Android 권한 설정
  - `example/android/app/src/main/AndroidManifest.xml`에 USB 권한 추가
  - USB 디바이스 필터 설정 (device_filter.xml)
  - USB_DEVICE_ATTACHED intent filter 추가
- [x] 설정 가이드 작성 (`SERIAL_SETUP.md`)

**참고**:
- `usb_serial` 패키지는 Android의 USB Serial 통신을 Flutter에서 직접 사용 가능
- FTDI, CP210x, CH34x, CDC ACM 등 주요 칩셋 모두 지원
- 네이티브 코드 작성 불필요

---

### ✅ 5단계: 시리얼 통신 추상화 레이어
**목표**: 프로토콜과 통신 레이어 분리

**작업 내용**:
- [x] 통신 인터페이스 정의 (`lib/src/serial/serial_connection.dart`)
  - 추상 클래스로 통신 메서드 정의
  - 향후 다른 통신 방식(Bluetooth, TCP) 확장 가능
- [x] USB Serial 구현체 작성 (`lib/src/serial/usb_serial_connection.dart`)
  - `SerialConnection` 인터페이스 구현
  - `usb_serial` 패키지 래핑
  - 연결 상태 관리
- [x] 재연결 로직 (`lib/src/serial/reconnect_manager.dart`)
  - 4가지 재연결 전략 (never, immediate, exponential backoff, fixed interval)
  - 재연결 이벤트 스트림
  - SerialManager 통합
- [x] 수신 버퍼 및 파싱 로직 (`lib/src/serial/message_parser.dart`)
  - 바이트 스트림을 완전한 메시지로 조립
  - FLAG 헤더 감지 및 메시지 경계 구분
  - 불완전한 메시지 처리
- [x] 고수준 Serial Manager (`lib/src/serial/serial_manager.dart`)
  - 연결 관리 + 메시지 파싱 통합
  - `sendCommand()` - 명령 전송 및 응답 대기
  - 타임아웃 및 재전송 로직

**Note**: 일부 엣지 케이스 테스트는 추후 개선 예정

---

### ✅ 6단계: 고수준 API 구현 (주요 명령어)
**목표**: 사용하기 쉬운 고수준 API 제공

**작업 내용**:
- [x] `GS805Serial` 클래스 구현 (`lib/gs805serial.dart`)
  - 연결 관리
    - `connect(SerialDevice device)` - 시리얼 포트 연결
    - `connectToFirstDevice()` - 첫 번째 디바이스 연결
    - `connectByVidPid(int vid, int pid)` - VID/PID로 연결
    - `disconnect()` - 연결 해제
    - `isConnected` - 연결 상태
    - `connectedDevice` - 연결된 디바이스 정보
  - 음료 제조
    - `makeDrink(DrinkNumber drink, {bool useLocalBalance = false})` - 0x01
  - 온도 설정
    - `setHotTemperature(int upperLimit, int lowerLimit)` - 0x04
    - `setColdTemperature(int upperLimit, int lowerLimit)` - 0x05
  - 정보 조회
    - `getSalesCount(DrinkNumber drink)` - 0x06 (DrinkSalesCount 반환)
    - `getMachineStatus()` - 0x0B (MachineStatus 반환)
    - `getErrorCode()` - 0x0C (MachineError 반환)
    - `getErrorInfo()` - 0x0C (ErrorInfo with recovery suggestions)
    - `getBalance()` - 0x0F (MachineBalance 반환)
  - 기기 제어
    - `setCupDropMode(CupDropModeEnum mode)` - 0x07
    - `testCupDrop()` - 0x08
    - `autoInspection()` - 0x09
    - `cleanAllPipes()` - 0x0A
    - `cleanSpecificPipe(int pipeNumber)` - 0x12
    - `returnChange()` - 0x10 (ChangerStatus 반환)
    - `setDrinkPrice(DrinkNumber drink, int price)` - 0x0E
  - 이벤트 스트림
    - `messageStream` - 모든 수신 메시지
    - `eventStream` - 기기 이벤트 (active reports)
    - `connectionStateStream` - 연결 상태 변경
    - `reconnectEventStream` - 재연결 이벤트
  - 유틸리티
    - `bufferSize` - 현재 버퍼 크기
    - `clearBuffer()` - 버퍼 초기화
    - `reconnect()` - 수동 재연결
    - `dispose()` - 리소스 정리
- [x] 응답 타임아웃 및 재전송 로직 (SerialManager에 구현됨)
- [x] 에러 핸들링 (커스텀 예외 클래스 사용)

---

### ✅ 7단계: 이벤트 스트림 구현
**목표**: 기기에서 능동적으로 전송하는 메시지 처리

**작업 내용**:
- [x] 이벤트 스트림 구현 (6단계에서 완료)
  - 컵 배출 성공 (0x0C 05) - `MachineEventType.cupDropSuccess`
  - 음료 준비 완료 (0x0C 10) - `MachineEventType.drinkComplete`
  - 아이스 투입 완료 (0x0C 06) - `MachineEventType.iceDropComplete`
  - 오류 발생 이벤트 - `MachineEventType.trackObstacle`
- [x] 콜백/스트림 API 제공
  - `Stream<MachineEvent> get eventStream` - 구현됨
  - `Stream<ResponseMessage> get messageStream` - 모든 메시지
  - `Stream<bool> get connectionStateStream` - 연결 상태
  - `Stream<ReconnectEvent> get reconnectEventStream` - 재연결 이벤트

---

### ✅ 8단계: 예제 앱 작성
**목표**: 플러그인 사용 예제 제공

**작업 내용**:
- [x] `example/lib/main.dart` 종합 샘플 앱 작성 (550+ 라인)
  - 시리얼 포트 선택 UI (드롭다운 + 새로고침)
  - 연결/해제 버튼 (상태 표시 포함)
  - 음료 제조 버튼 (Hot/Cold 탭으로 분리, 총 14개 음료)
  - 상태 모니터링 화면 (기기 상태 + 잔액 표시)
  - 이벤트 로그 (타임스탬프 포함, 최대 50개)
  - 유지보수 탭 (컵 드롭 테스트, 파이프 청소, 자동 검사)
  - 재연결 상태 표시 (AppBar 로딩 인디케이터)
  - 스낵바로 성공/실패 알림
- [x] 이벤트 스트림 통합
  - `connectionStateStream` - 연결 상태 모니터링
  - `eventStream` - 기기 이벤트 리스닝
  - `reconnectEventStream` - 재연결 진행 상황 표시

---

### ✅ 9단계: 테스트 및 문서화
**목표**: 안정성 확보 및 사용 가이드 작성

**작업 내용**:
- [x] 단위 테스트 작성 (97/101 통과)
  - 프로토콜 인코딩/디코딩 테스트 (31개)
  - 체크섬 계산 테스트 (완료)
  - 모델 테스트 (40개)
  - 시리얼 테스트 (6개 통과, 3개 TODO)
  - 재연결 테스트 (9개)
  - API 테스트 (11개, 1개 하드웨어 의존)
- [x] API 문서 작성
  - README.md 전체 업데이트 (460+ 라인)
    - 기능 소개 및 플랫폼 지원
    - 설치 및 Android 설정 가이드
    - Quick Start 예제
    - 상세 사용 예제 (연결, 음료, 온도, 상태, 유지보수, 이벤트)
    - API Reference (메서드 및 스트림)
    - 프로토콜 상세 정보
    - 아키텍처 다이어그램
    - 트러블슈팅 가이드
  - CHANGELOG.md 업데이트 (Stage 1-6 완료 내용)
  - 기존 가이드 문서 유지
    - SERIAL_SETUP.md (USB Serial 설정)
    - RECONNECT_GUIDE.md (재연결 설정)
- [ ] 통합 테스트 (실제 기기 필요 - 사용자 환경에서 수행)

---

### ⬜ 10단계: 추가 기능 (부분 완료)
**목표**: 고급 기능 구현

**작업 내용**:
- [x] 나머지 명령어 구현 (6단계에서 완료)
  - 0x09: 자동 전체 검사 (`autoInspection()`)
  - 0x0E: 가격 설정 (`setDrinkPrice()`)
  - 0x12: 지정 파이프라인 청소 (`cleanSpecificPipe()`)
- [x] 재연결 로직 (5단계에서 완료 - ReconnectManager)
  - 4가지 재연결 전략 (never, immediate, exponentialBackoff, fixedInterval)
  - 재연결 이벤트 스트림
  - 자동/수동 재연결
- [x] 로깅 기능
  - `GS805Logger` 싱글톤 클래스
  - 5가지 로그 레벨 지원
  - 로그 히스토리 및 필터링
  - 실시간 로그 스트림
  - 12개 테스트 통과
- [x] 명령 큐 관리
  - `CommandQueue` 클래스
  - 순차 실행 및 자동 재시도
  - 큐 제어 (pause/resume/clear)
  - 큐 이벤트 스트림
  - 16개 테스트 통과
- [ ] 다른 통신 방식 지원 (미구현 - 필요시)
  - Bluetooth Serial (flutter_bluetooth_serial)
  - TCP/IP 소켓 통신
  - 추상화 레이어 덕분에 쉽게 확장 가능
- [ ] iOS 지원 (미구현 - USB Serial 제한)

---

## 현재 상태
- ✅ 프로젝트 초기 설정 완료
- ✅ 문서 분석 완료
- ✅ 기술 스택 결정 (usb_serial 패키지 사용)
- ✅ 1단계 완료: 프로젝트 구조 및 상수 정의
- ✅ 2단계 완료: 프로토콜 메시지 인코딩/디코딩 (31개 테스트 통과)
- ✅ 3단계 완료: 데이터 모델 정의 (40개 테스트 통과)
- ✅ 4단계 완료: USB Serial 패키지 통합 및 Android 권한 설정
- ✅ 5단계 완료: 시리얼 통신 추상화 및 메시지 파싱 (재연결 로직 포함)
- ✅ 6단계 완료: 고수준 API 구현 (97개 테스트 통과)
  - GS805Serial 클래스: 20+ 메서드 구현
  - 연결 관리, 음료 제조, 온도 설정, 정보 조회, 기기 제어
  - 이벤트 스트림 (messageStream, eventStream, connectionStateStream, reconnectEventStream)
  - USB Serial 연결 버그 수정 (onStatusChange 제거)
- ✅ 7단계 완료: 이벤트 스트림 (6단계에서 함께 완료)
- ✅ 8단계 완료: 예제 앱 작성 (550+ 라인 종합 앱)
- ✅ 9단계 완료: 테스트 및 문서화
  - README.md 전체 업데이트 (460+ 라인)
  - CHANGELOG.md 업데이트
  - 97/101 테스트 통과
- ✅ 10단계 부분 완료: 로깅 & 명령 큐
  - 로깅 시스템 구현 (12개 테스트)
  - 명령 큐 관리 구현 (16개 테스트)
  - GS805Serial 통합 완료
  - 총 125/129 테스트 통과

## 기술 스택
- **언어**: Dart (Flutter)
- **플랫폼**: Android (우선)
- **시리얼 통신**: usb_serial ^0.5.0
- **아키텍처**: 레이어드 아키텍처 (Protocol Layer / Serial Layer / API Layer)

## 참고사항
- 문서: `document.pdf`
- 프로토콜 버전: GS805 (3계열 멀티스레드)
- 플랫폼: Android 우선 (iOS는 추후 고려)
- 시리얼 통신: `usb_serial` 패키지 사용 (네이티브 코드 불필요)
- 연결 방식: USB-Serial (RS232)

---

## 다음 단계
**1단계부터 순차적으로 진행**
- 각 단계 완료 후 체크박스를 ✅로 변경
- 문제 발생 시 해당 단계에 이슈 기록
