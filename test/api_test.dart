import 'package:flutter_test/flutter_test.dart';
import 'package:gs805serial/gs805serial.dart';

void main() {
  group('GS805Serial API', () {
    test('creates instance', () {
      final gs805 = GS805Serial();
      expect(gs805, isNotNull);
      expect(gs805.isConnected, isFalse);
    });

    test('creates with reconnect config', () {
      final gs805 = GS805Serial(
        reconnectConfig: ReconnectConfig.exponentialBackoff,
      );
      expect(gs805, isNotNull);
    });

    test('list devices returns list', () async {
      final gs805 = GS805Serial();
      final devices = await gs805.listDevices();
      expect(devices, isA<List<SerialDevice>>());
    });

    test('throws when not connected', () {
      final gs805 = GS805Serial();

      expect(
        () => gs805.getMachineStatus(),
        throwsA(isA<NotConnectedException>()),
      );

      expect(
        () => gs805.makeDrink(DrinkNumber.hotDrink1),
        throwsA(isA<NotConnectedException>()),
      );

      expect(
        () => gs805.getBalance(),
        throwsA(isA<NotConnectedException>()),
      );
    });

    test('exposes connection state', () {
      final gs805 = GS805Serial();
      expect(gs805.isConnected, isFalse);
      expect(gs805.connectedDevice, isNull);
      expect(gs805.isReconnecting, isFalse);
    });

    test('exposes streams', () {
      final gs805 = GS805Serial();
      expect(gs805.messageStream, isA<Stream<ResponseMessage>>());
      expect(gs805.eventStream, isA<Stream<MachineEvent>>());
      expect(gs805.connectionStateStream, isA<Stream<bool>>());
      expect(gs805.reconnectEventStream, isA<Stream<ReconnectEvent>>());
    });

    test('can dispose', () async {
      final gs805 = GS805Serial();
      await gs805.dispose();
      // Should not throw
    });
  });

  group('Public API Exports', () {
    test('DrinkNumber is exported', () {
      expect(DrinkNumber.values.length, equals(14));
      expect(DrinkNumber.hotDrinks.length, equals(7));
      expect(DrinkNumber.coldDrinks.length, equals(7));
    });

    test('TemperatureSettings is exported', () {
      final temp = TemperatureSettings.hot(
        upperLimit: 85,
        lowerLimit: 75,
      );
      expect(temp.upperLimit, equals(85));
      expect(temp.isHot, isTrue);
    });

    test('MachineStatus is exported', () {
      final status = MachineStatus.fromCode(0x00);
      expect(status, equals(MachineStatus.ready));
    });

    test('SerialConfig is exported', () {
      const config = SerialConfig.gs805;
      expect(config.baudRate, equals(9600));
    });

    test('ReconnectConfig is exported', () {
      expect(ReconnectConfig.exponentialBackoff.strategy,
          equals(ReconnectStrategy.exponentialBackoff));
    });
  });
}
