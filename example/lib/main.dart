import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:gs805serial/gs805serial.dart';

void main() {
  runApp(const GS805ExampleApp());
}

class GS805ExampleApp extends StatelessWidget {
  const GS805ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GS805 Serial Control',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        useMaterial3: true,
      ),
      home: const CoffeeMachineScreen(),
    );
  }
}

class CoffeeMachineScreen extends StatefulWidget {
  const CoffeeMachineScreen({super.key});

  @override
  State<CoffeeMachineScreen> createState() => _CoffeeMachineScreenState();
}

class _CoffeeMachineScreenState extends State<CoffeeMachineScreen> {
  final GS805Serial _gs805 = GS805Serial(
    connection: UartSerialConnection(),
    reconnectConfig: ReconnectConfig.exponentialBackoff,
  );

  // --- MDB Cashless ---
  final MdbCashless _mdbCashless = MdbCashless(
    connection: UartSerialConnection(),
  );

  List<SerialDevice> _devices = [];
  SerialDevice? _selectedDevice;
  bool _isConnected = false;
  bool _isReconnecting = false;
  String _statusMessage = 'Not connected';
  String _appVersion = '';
  MachineStatus? _machineStatus;
  int? _balance;
  final List<String> _eventLog = [];

  // MDB state
  List<SerialDevice> _mdbDevices = [];
  SerialDevice? _selectedMdbDevice;
  bool _mdbConnected = false;
  CashlessState _cashlessState = CashlessState.inactive;
  int _vendPrice = 100;

  StreamSubscription<bool>? _connectionStateSub;
  StreamSubscription<MachineEvent>? _eventSub;
  StreamSubscription<ReconnectEvent>? _reconnectSub;
  StreamSubscription<CashlessEvent>? _cashlessEventSub;
  StreamSubscription<bool>? _mdbConnectionSub;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _loadDevices();
    _loadMdbDevices();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final result = await _uartChannel.invokeMethod('shellCommand', {
        'command': 'dumpsys package kr.co.anyeats.gs805serial_example | grep versionName'
      });
      if (result != null) {
        final info = Map<String, dynamic>.from(result as Map);
        final stdout = (info['stdout'] as String?)?.trim() ?? '';
        final match = RegExp(r'versionName=(\S+)').firstMatch(stdout);
        if (match != null) {
          setState(() => _appVersion = match.group(1)!);
          return;
        }
      }
    } catch (_) {}
    // Fallback: read from shell
    try {
      final result = await _uartChannel.invokeMethod('shellCommand', {
        'command': 'su 0 dumpsys package kr.co.anyeats.gs805serial_example | grep -E "versionCode|versionName"'
      });
      if (result != null) {
        final info = Map<String, dynamic>.from(result as Map);
        final stdout = (info['stdout'] as String?)?.trim() ?? '';
        final nameMatch = RegExp(r'versionName=(\S+)').firstMatch(stdout);
        final codeMatch = RegExp(r'versionCode=(\d+)').firstMatch(stdout);
        if (nameMatch != null) {
          final name = nameMatch.group(1)!;
          final code = codeMatch?.group(1) ?? '';
          setState(() => _appVersion = code.isNotEmpty ? '$name ($code)' : name);
        }
      }
    } catch (_) {}
  }

  void _setupStreams() {
    // Monitor connection state
    _connectionStateSub = _gs805.connectionStateStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
        _statusMessage = isConnected ? 'Connected' : 'Disconnected';
      });
      if (isConnected) {
        _refreshStatus();
      }
    });

    // Monitor machine events
    _eventSub = _gs805.eventStream.listen((event) {
      _addEventLog('Event: ${event.type.description}');
      if (event.isSuccess) {
        _showSnackBar(event.type.description, Colors.green);
      } else if (event.isError) {
        _showSnackBar(event.type.description, Colors.red);
      }
    });

    // Monitor reconnection
    _reconnectSub = _gs805.reconnectEventStream.listen((event) {
      setState(() {
        _isReconnecting = event.state == ReconnectState.connecting ||
            event.state == ReconnectState.waiting;
      });

      switch (event.state) {
        case ReconnectState.waiting:
          _addEventLog(
              'Reconnecting in ${event.nextAttemptDelay?.inMilliseconds}ms...');
          break;
        case ReconnectState.connecting:
          _addEventLog('Reconnecting (attempt ${event.attempt + 1})...');
          break;
        case ReconnectState.connected:
          _addEventLog('Reconnected successfully!');
          _showSnackBar('Reconnected!', Colors.green);
          break;
        case ReconnectState.failed:
          _addEventLog('Reconnection failed after ${event.attempt} attempts');
          _showSnackBar('Reconnection failed', Colors.red);
          break;
        default:
          break;
      }
    });

    // Monitor MDB Cashless events
    _cashlessEventSub = _mdbCashless.eventStream.listen(_onCashlessEvent);
    _mdbConnectionSub = _mdbCashless.connectionStateStream.listen((connected) {
      setState(() {
        _mdbConnected = connected;
      });
    });
  }

  void _onCashlessEvent(CashlessEvent event) {
    setState(() {
      _cashlessState = event.state;
    });

    switch (event.type) {
      case CashlessEventType.stateChanged:
        _addEventLog('[MDB] State: ${event.state.displayName}');
        break;
      case CashlessEventType.cardDetected:
        final funds = event.availableFunds;
        _addEventLog('[MDB] Card detected${funds != null ? ' (funds: $funds)' : ''}');
        _showSnackBar('Card detected! Ready for payment.', Colors.green);
        break;
      case CashlessEventType.vendApproved:
        final amount = event.approvedAmount;
        _addEventLog('[MDB] Vend approved${amount != null ? ' (amount: $amount)' : ''}');
        _showSnackBar('Payment approved!', Colors.green);
        break;
      case CashlessEventType.vendDenied:
        _addEventLog('[MDB] Vend denied');
        _showSnackBar('Payment denied', Colors.red);
        break;
      case CashlessEventType.sessionCancelled:
        _addEventLog('[MDB] Session cancelled');
        _showSnackBar('Session cancelled', Colors.orange);
        break;
      case CashlessEventType.sessionCompleted:
        _addEventLog('[MDB] Session completed');
        break;
      case CashlessEventType.configReceived:
        _addEventLog('[MDB] Config: ${event.data['config']}');
        break;
      case CashlessEventType.commandSent:
        _addEventLog('[MDB] TX: ${event.rawHex}');
        break;
      case CashlessEventType.rawData:
        _addEventLog('[MDB] RX: ${event.rawHex}');
        break;
      case CashlessEventType.ackReceived:
        _addEventLog('[MDB] ACK');
        break;
      case CashlessEventType.readerIdReceived:
        _addEventLog('[MDB] Reader ID: ${event.data['id']}');
        break;
      case CashlessEventType.error:
        _addEventLog('[MDB] Error: ${event.errorMessage}');
        _showSnackBar('MDB Error: ${event.errorMessage}', Colors.red);
        break;
    }
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _gs805.listDevices();
      setState(() {
        _devices = devices;
        // Default to ttyS7 if available
        _selectedDevice = devices.cast<SerialDevice?>().firstWhere(
          (d) => d!.name.contains('ttyS7'),
          orElse: () => devices.isNotEmpty ? devices.first : null,
        );
      });
    } catch (e) {
      _showSnackBar('Failed to load devices: $e', Colors.red);
    }
  }

  Future<void> _loadMdbDevices() async {
    try {
      final devices = await _mdbCashless.listDevices();
      setState(() {
        _mdbDevices = devices;
        // Default to ttyS9 (Payment Serial Port)
        _selectedMdbDevice = devices.cast<SerialDevice?>().firstWhere(
          (d) => d!.name.contains('ttyS9'),
          orElse: () => devices.isNotEmpty ? devices.first : null,
        );
      });
    } catch (e) {
      _showSnackBar('Failed to load MDB devices: $e', Colors.red);
    }
  }

  Future<void> _connect() async {
    if (_selectedDevice == null) {
      _showSnackBar('Please select a device', Colors.orange);
      return;
    }

    try {
      await _gs805.connect(_selectedDevice!);
      _addEventLog('Connected to ${_selectedDevice!.name}');
    } catch (e) {
      _addEventLog('Connection failed: $e');
      _showErrorDialog(
        'Connection Failed',
        'Unable to connect to ${_selectedDevice!.name}.\n\n'
        'Please check:\n'
        '- Device is properly connected\n'
        '- USB permissions are granted\n'
        '- Device is not in use by another app',
        error: e,
      );
    }
  }

  Future<void> _disconnect() async {
    try {
      await _gs805.disconnect();
      _addEventLog('Disconnected');
      setState(() {
        _machineStatus = null;
        _balance = null;
      });
    } catch (e) {
      _addEventLog('Disconnect failed: $e');
      _showErrorDialog(
        'Disconnect Failed',
        'Unable to disconnect from the device properly.',
        error: e,
      );
    }
  }

  Future<void> _refreshStatus() async {
    if (!_isConnected) return;

    try {
      final status = await _gs805.getMachineStatus();
      final balance = await _gs805.getBalance();

      setState(() {
        _machineStatus = status;
        _balance = balance.balance;
        _statusMessage = status.message;
      });
    } catch (e) {
      _showSnackBar('Failed to get status: $e', Colors.red);
    }
  }



  Future<void> _testCupDrop() async {
    if (!_isConnected) return;

    try {
      await _gs805.testCupDrop();
      _addEventLog('Testing cup drop...');
    } catch (e) {
      _showSnackBar('Cup drop test failed: $e', Colors.red);
    }
  }

  Future<void> _cleanAllPipes() async {
    if (!_isConnected) return;

    try {
      await _gs805.cleanAllPipes();
      _addEventLog('Cleaning all pipes...');
      _showSnackBar('Cleaning all pipes...', Colors.blue);
    } catch (e) {
      _showSnackBar('Clean failed: $e', Colors.red);
    }
  }

  // ========== Maintenance Actions ==========

  Future<void> _cleanSpecificPipe(int pipeNumber) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.cleanSpecificPipe(pipeNumber);
      _addEventLog('Cleaning pipe #$pipeNumber...');
      _showSnackBar('Cleaning pipe #$pipeNumber...', Colors.blue);
    } catch (e) {
      _showSnackBar('Clean pipe failed: $e', Colors.red);
    }
  }

  Future<void> _getErrorCode() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final error = await _gs805.getErrorCode();
      _addEventLog('Error code: $error');
    } catch (e) {
      _showSnackBar('Get error code failed: $e', Colors.red);
    }
  }

  Future<void> _getErrorInfo() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final info = await _gs805.getErrorInfo();
      _addEventLog('Error info: $info');
    } catch (e) {
      _showSnackBar('Get error info failed: $e', Colors.red);
    }
  }

  Future<void> _returnChange() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.returnChange();
      _addEventLog('Change return: $status');
    } catch (e) {
      _showSnackBar('Return change failed: $e', Colors.red);
    }
  }

  Future<void> _setHotTemperature() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.setHotTemperature(65, 60);
      _addEventLog('Hot temp set: upper=65, lower=60');
      _showSnackBar('Hot temperature set (65/60)', Colors.green);
    } catch (e) {
      _showSnackBar('Set hot temp failed: $e', Colors.red);
    }
  }

  Future<void> _setColdTemperature() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.setColdTemperature(10, 5);
      _addEventLog('Cold temp set: upper=10, lower=5');
      _showSnackBar('Cold temperature set (10/5)', Colors.green);
    } catch (e) {
      _showSnackBar('Set cold temp failed: $e', Colors.red);
    }
  }

  Future<void> _setCupDropMode(CupDropModeEnum mode) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.setCupDropMode(mode);
      _addEventLog('Cup drop mode set: ${mode.displayName}');
      _showSnackBar('Cup drop mode: ${mode.displayName}', Colors.green);
    } catch (e) {
      _showSnackBar('Set cup drop mode failed: $e', Colors.red);
    }
  }

  Future<void> _setDrinkPrice() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.setDrinkPrice(DrinkNumber.hotDrink1, 10);
      _addEventLog('Drink price set: Hot Drink 1 = 10 tokens');
      _showSnackBar('Price set: Hot Drink 1 = 10', Colors.green);
    } catch (e) {
      _showSnackBar('Set drink price failed: $e', Colors.red);
    }
  }

  Future<void> _getSalesCount() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final count = await _gs805.getSalesCount(DrinkNumber.hotDrink1);
      _addEventLog('Sales count: $count');
    } catch (e) {
      _showSnackBar('Get sales count failed: $e', Colors.red);
    }
  }

  // ========== Extended Actions ==========

  Future<void> _unitFunctionTest() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.unitFunctionTest(1, 0, 0, 0);
      _addEventLog('Unit function test (dispensing) started');
      _showSnackBar('Dispensing test started', Colors.blue);
    } catch (e) {
      _showSnackBar('Unit test failed: $e', Colors.red);
    }
  }

  Future<void> _lockDoor() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.lockDoor();
      _addEventLog('Lock door: $status');
    } catch (e) {
      _showSnackBar('Lock door failed: $e', Colors.red);
    }
  }

  Future<void> _unlockDoor() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.unlockDoor();
      _addEventLog('Unlock door: $status');
    } catch (e) {
      _showSnackBar('Unlock door failed: $e', Colors.red);
    }
  }

  Future<void> _getLockStatus() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.getLockStatus();
      _addEventLog('Lock status: $status');
    } catch (e) {
      _showSnackBar('Get lock status failed: $e', Colors.red);
    }
  }

  Future<void> _waterRefill() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.waterRefill();
      _addEventLog('Water refill triggered');
      _showSnackBar('Water refill started', Colors.blue);
    } catch (e) {
      _showSnackBar('Water refill failed: $e', Colors.red);
    }
  }

  Future<void> _getControllerStatus() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.getControllerStatus();
      _addEventLog('Controller status: $status');
    } catch (e) {
      _showSnackBar('Get controller status failed: $e', Colors.red);
    }
  }

  Future<void> _getDrinkStatus() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final status = await _gs805.getDrinkStatus();
      _addEventLog('Drink status: $status');
    } catch (e) {
      _showSnackBar('Get drink status failed: $e', Colors.red);
    }
  }

  Future<void> _getObjectException() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final info = await _gs805.getObjectException(ObjectType.pump);
      _addEventLog('Object exception (pump): $info');
    } catch (e) {
      _showSnackBar('Get object exception failed: $e', Colors.red);
    }
  }

  Future<void> _forceStopDrinkProcess() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.forceStopDrinkProcess();
      _addEventLog('Force stop drink process sent');
      _showSnackBar('Drink process stopped', Colors.orange);
    } catch (e) {
      _showSnackBar('Force stop failed: $e', Colors.red);
    }
  }

  Future<void> _forceStopCupDelivery() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.forceStopCupDelivery();
      _addEventLog('Force stop cup delivery sent');
      _showSnackBar('Cup delivery stopped', Colors.orange);
    } catch (e) {
      _showSnackBar('Force stop cup delivery failed: $e', Colors.red);
    }
  }

  Future<void> _cupDelivery() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.cupDelivery(30);
      _addEventLog('Cup delivery started (30s timeout)');
      _showSnackBar('Cup delivery started', Colors.blue);
    } catch (e) {
      _showSnackBar('Cup delivery failed: $e', Colors.red);
    }
  }

  Future<void> _setDrinkRecipeProcess() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final steps = [
        RecipeStep.cupDispense(dispenser: 1),
        RecipeStep.instantChannel(
          channel: 0,
          waterType: WaterType.hot,
          materialDuration: 1000,
          waterAmount: 2000,
          materialSpeed: 50,
          mixSpeed: 30,
        ),
      ];
      await _gs805.setDrinkRecipeProcess(DrinkNumber.hotDrink1, steps);
      _addEventLog('Recipe set for Hot Drink 1 (${steps.length} steps)');
      _showSnackBar('Recipe set successfully', Colors.green);
    } catch (e) {
      _showSnackBar('Set recipe failed: $e', Colors.red);
    }
  }

  Future<void> _executeChannel() async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      await _gs805.executeChannel(
        channel: 0,
        waterType: WaterType.hot,
        materialDuration: 1000,
        waterAmount: 2000,
        materialSpeed: 50,
      );
      _addEventLog('Execute channel 0 (hot, mat=1000, water=2000, speed=50)');
      _showSnackBar('Channel executed', Colors.blue);
    } catch (e) {
      _showSnackBar('Execute channel failed: $e', Colors.red);
    }
  }

  // ========== MDB Cashless Actions ==========

  Future<void> _mdbConnect() async {
    if (_selectedMdbDevice == null) {
      _showSnackBar('Select MDB device first', Colors.orange);
      return;
    }
    try {
      await _mdbCashless.connect(_selectedMdbDevice!);
      _addEventLog('[MDB] Connected to ${_selectedMdbDevice!.name}');
    } catch (e) {
      _addEventLog('[MDB] Connection failed: $e');
      _showSnackBar('MDB connection failed: $e', Colors.red);
    }
  }

  Future<void> _mdbDisconnect() async {
    try {
      await _mdbCashless.disconnect();
      _addEventLog('[MDB] Disconnected');
    } catch (e) {
      _showSnackBar('MDB disconnect failed: $e', Colors.red);
    }
  }

  Future<void> _mdbSetup() async {
    try {
      await _mdbCashless.setup();
      _addEventLog('[MDB] Setup completed');
    } catch (e) {
      _showSnackBar('MDB setup failed: $e', Colors.red);
    }
  }

  Future<void> _mdbEnable() async {
    try {
      await _mdbCashless.enable();
      _addEventLog('[MDB] Reader enabled');
    } catch (e) {
      _showSnackBar('MDB enable failed: $e', Colors.red);
    }
  }

  Future<void> _mdbDisable() async {
    try {
      await _mdbCashless.disable();
      _addEventLog('[MDB] Reader disabled');
    } catch (e) {
      _showSnackBar('MDB disable failed: $e', Colors.red);
    }
  }

  Future<void> _mdbRequestVend() async {
    try {
      await _mdbCashless.requestVend(price: _vendPrice, itemNumber: 1);
      _addEventLog('[MDB] Vend requested: price=$_vendPrice');
    } catch (e) {
      _showSnackBar('$e', Colors.red);
    }
  }

  Future<void> _mdbVendSuccess() async {
    try {
      await _mdbCashless.vendSuccess(itemNumber: 1);
      _addEventLog('[MDB] Vend success sent');

      // End session
      await Future.delayed(const Duration(milliseconds: 200));
      await _mdbCashless.sessionComplete();
    } catch (e) {
      _showSnackBar('$e', Colors.red);
    }
  }

  Future<void> _mdbVendCancel() async {
    try {
      await _mdbCashless.vendCancel();
      _addEventLog('[MDB] Vend cancelled');
    } catch (e) {
      _showSnackBar('$e', Colors.red);
    }
  }

  Future<void> _mdbRequestId() async {
    try {
      await _mdbCashless.requestId();
    } catch (e) {
      _showSnackBar('$e', Colors.red);
    }
  }

  Future<void> _mdbCashSale() async {
    try {
      await _mdbCashless.cashSale(price: _vendPrice, itemNumber: 1);
      _addEventLog('[MDB] Cash sale reported: price=$_vendPrice');
    } catch (e) {
      _showSnackBar('$e', Colors.red);
    }
  }

  void _addEventLog(String message) {
    setState(() {
      _eventLog.insert(0, '${DateTime.now().toString().substring(11, 19)} $message');
      if (_eventLog.length > 50) {
        _eventLog.removeLast();
      }
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: message));
          },
          child: Text(message),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorDialog(String title, String message, {Object? error}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (error != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Technical Details:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    error.toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _connectionStateSub?.cancel();
    _eventSub?.cancel();
    _reconnectSub?.cancel();
    _cashlessEventSub?.cancel();
    _mdbConnectionSub?.cancel();
    _gs805.dispose();
    _mdbCashless.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GS805 Coffee Machine${_appVersion.isNotEmpty ? '  v$_appVersion' : ''}'),
        actions: [
          if (_isReconnecting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection Bar
          _buildConnectionBar(),

          // Tabs
          Expanded(
            child: DefaultTabController(
              length: _isConnected ? 8 : 2,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: [
                      if (_isConnected) ...[
                        const Tab(text: 'Channel'),
                        const Tab(text: 'Recipe'),
                        const Tab(text: 'Payment'),
                        const Tab(text: 'Maint.'),
                        const Tab(text: 'Extended'),
                        const Tab(text: 'Settings'),
                      ],
                      const Tab(text: 'Debug'),
                      const Tab(text: 'System'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        if (_isConnected) ...[
                          _buildChannelPanel(),
                          _buildRecipePanel(),
                          _buildPaymentPanel(),
                          _buildMaintenancePanel(),
                          _buildExtendedPanel(),
                          _buildSettingsPanel(),
                        ],
                        _buildDebugPanel(),
                        _buildSystemPanel(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Event Log
          _buildEventLog(),
        ],
      ),
    );
  }

  Widget _buildConnectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: _isConnected ? Colors.green[50] : Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<SerialDevice>(
              value: _selectedDevice,
              hint: const Text('Select device'),
              isExpanded: true,
              isDense: true,
              items: _devices.map((device) {
                return DropdownMenuItem(
                  value: device,
                  child: Text(device.name, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _isConnected ? null : (device) {
                setState(() => _selectedDevice = device);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isConnected ? null : _loadDevices,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: _isConnected
                ? ElevatedButton(
                    onPressed: _disconnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[300],
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                  )
                : ElevatedButton(
                    onPressed: _connect,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Connect', style: TextStyle(fontSize: 12)),
                  ),
          ),
          if (_isConnected) ...[
            const SizedBox(width: 8),
            Icon(
              _machineStatus == MachineStatus.ready ? Icons.check_circle : Icons.info,
              color: _machineStatus == MachineStatus.ready ? Colors.green : Colors.orange,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  // ========== Channel Panel (executeChannel 0x25) ==========

  Widget _buildChannelPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('executeChannel (0x25) - 직접 실행', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        _buildChannelButton('Make 1 (1번통)', '1번 채널 단독, 온수', [0], WaterType.hot),
        const Divider(),
        _buildChannelButton('Make 1&2 (1+2번통)', '1번→2번 배출 후 교반, 온수', [0, 1], WaterType.hot),
        const Divider(),
        _buildChannelButton('Make 3&2 (3+2번통)', '3번→2번 배출 후 교반, 온수', [2, 1], WaterType.hot),
        const Divider(height: 24, thickness: 2),
        _buildChannelButton('Make 1 Cold (1번통)', '1번 채널 단독, 냉수', [0], WaterType.cold),
        const Divider(),
        _buildChannelButton('Make 1&2 Cold', '1번→2번 배출 후 교반, 냉수', [0, 1], WaterType.cold),
        const Divider(),
        _buildChannelButton('Make 3&2 Cold', '3번→2번 배출 후 교반, 냉수', [2, 1], WaterType.cold),
      ],
    );
  }

  Widget _buildChannelButton(String title, String subtitle, List<int> channels, WaterType waterType) {
    final isHot = waterType == WaterType.hot;
    return ListTile(
      dense: true,
      leading: Icon(isHot ? Icons.local_cafe : Icons.local_drink, color: isHot ? Colors.red : Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: ElevatedButton(
        onPressed: () => _executeChannels(channels, waterType),
        style: ElevatedButton.styleFrom(backgroundColor: isHot ? Colors.red[100] : Colors.blue[100]),
        child: const Text('Make'),
      ),
    );
  }

  Future<void> _executeChannels(List<int> channels, WaterType waterType) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final chNames = channels.map((c) => '${c + 1}번통').join('+');
      for (int i = 0; i < channels.length; i++) {
        final ch = channels[i];
        final isLast = i == channels.length - 1;
        _addEventLog('Executing ch$ch (${ch + 1}번통)...');
        await _gs805.executeChannel(
          channel: ch,
          waterType: waterType,
          materialDuration: 50,     // 문서 예시값: 5초
          waterAmount: 50,          // 문서 예시값: 5초
          materialSpeed: 0,         // 문서 예시값
          mixSpeed: 0,              // 문서 예시값
        );
      }
      _showSnackBar('$chNames 실행 완료', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed: $e', Colors.red);
    }
  }

  // ========== Recipe Panel (setDrinkRecipeProcess 0x1D + makeDrink 0x01) ==========

  Widget _buildRecipePanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('setDrinkRecipeProcess (0x1D) + makeDrink (0x01)', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        _buildRecipeButton('Recipe 1 (1번통)', 'hotDrink1에 1번 채널 레시피 설정 후 제조', DrinkNumber.hotDrink1, WaterType.hot, [0]),
        const Divider(),
        _buildRecipeButton('Recipe 1&2 (1+2번통)', 'hotDrink2에 1번→2번 레시피 설정 후 제조', DrinkNumber.hotDrink2, WaterType.hot, [0, 1]),
        const Divider(),
        _buildRecipeButton('Recipe 3&2 (3+2번통)', 'hotDrink3에 3번→2번 레시피 설정 후 제조', DrinkNumber.hotDrink3, WaterType.hot, [2, 1]),
        const Divider(height: 24, thickness: 2),
        _buildRecipeButton('Recipe 1 Cold', 'coldDrink1에 레시피 설정', DrinkNumber.coldDrink1, WaterType.cold, [0]),
        const Divider(),
        _buildRecipeButton('Recipe 1&2 Cold', 'coldDrink2에 레시피 설정', DrinkNumber.coldDrink2, WaterType.cold, [0, 1]),
        const Divider(),
        _buildRecipeButton('Recipe 3&2 Cold', 'coldDrink3에 레시피 설정', DrinkNumber.coldDrink3, WaterType.cold, [2, 1]),
        const Divider(height: 24, thickness: 2),
        // --- 0x15 레시피 시간 설정 ---
        ListTile(
          dense: true,
          leading: const Icon(Icons.timer, color: Colors.teal),
          title: const Text('0x15 레시피 시간 설정 → Make'),
          subtitle: const Text('ch1: 재료1초, ch2: 물20초'),
          trailing: ElevatedButton(
            onPressed: () async {
              if (!_isConnected) return;
              try {
                // ch1~8: (material, water) in 0.1s units
                final times = <(int, int)>[
                  (10, 0),      // ch1: 재료만 1초
                  (0, 200),     // ch2: 물만 20초
                  (0, 0),       // ch3
                  (0, 0),       // ch4
                  (0, 0),       // ch5
                  (0, 0),       // ch6
                  (0, 0),       // ch7
                  (0, 0),       // ch8
                ];
                _addEventLog('0x15: ch1(mat=10) ch2(wat=200)...');
                await _gs805.setDrinkRecipeTime(DrinkNumber.hotDrink1, times);
                _addEventLog('0x15 OK. Making...');
                await _gs805.makeDrink(DrinkNumber.hotDrink1);
                _showSnackBar('0x15 → Make 완료', Colors.blue);
              } catch (e) {
                _showSnackBar('Failed: $e', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[100]),
            child: const Text('Run'),
          ),
        ),
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('채널 조합 테스트', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown)),
        ),
        _build015Test('ch1 물만', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch2 물만', [(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch3 물만', [(0,0),(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch1물', [(10,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch2물', [(10,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료 + ch3물', [(10,0),(0,0),(0,100),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1,ch3재료 + ch2물', [(10,0),(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1,ch3재료 + ch4물', [(10,0),(0,0),(10,0),(0,100),(0,0),(0,0),(0,0),(0,0)]),
        // ch1=물 + 다른채널=재료 테스트
        _build015Test('ch1물 + ch2재료', [(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch3재료', [(0,100),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch4재료', [(0,100),(0,0),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물 + ch3,ch4재료', [(0,100),(0,0),(10,0),(10,0),(0,0),(0,0),(0,0),(0,0)]),
        // 1번통(ch1) 재료+물 테스트: 원래 값 유지 시도
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('1번통 재료+물 테스트', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        ),
        _build015Test('ch1(재료10,물100)', [(10,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1재료10만 (VendApp복구후)', [(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('ch1물100만 (VendApp복구후)', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)]),
        _build015Test('전체1: ch1(10,100)나머지(1,1)', [(10,100),(1,1),(1,1),(1,1),(1,1),(1,1),(1,1),(1,1)]),
        // --- 냉음료 (coldDrink1) 테스트 ---
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('냉음료 테스트 (coldDrink1)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
        ),
        _build015Test('Cold: ch1물100만', [(0,100),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1재료10만', [(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch2재료', [(0,100),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch3재료', [(0,100),(0,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
        _build015Test('Cold: ch1물 + ch2,ch3재료', [(0,100),(10,0),(10,0),(0,0),(0,0),(0,0),(0,0),(0,0)], drink: DrinkNumber.coldDrink1),
      ],
    );
  }

    Widget _build015Test(String label, List<(int, int)> times, {DrinkNumber drink = DrinkNumber.hotDrink1}) {
      return ListTile(
        dense: true,
        leading: Icon(Icons.science, color: drink.isHot ? Colors.brown : Colors.blue),
        title: Text(label),
        trailing: ElevatedButton(
          onPressed: () async {
            if (!_isConnected) return;
            try {
              _addEventLog('0x15: $label (${drink.displayName})');
              await _gs805.setDrinkRecipeTime(drink, times);
              await _gs805.makeDrink(drink);
            } catch (e) {
              _showSnackBar('Failed: $e', Colors.red);
            }
          },
          child: const Text('Run'),
        ),
      );
  }

  Widget _buildRecipeButton(String title, String subtitle, DrinkNumber drink, WaterType waterType, List<int> channels) {
    final isHot = waterType == WaterType.hot;
    return ListTile(
      dense: true,
      leading: Icon(isHot ? Icons.local_cafe : Icons.local_drink, color: isHot ? Colors.orange : Colors.cyan),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: ElevatedButton(
        onPressed: () => _setRecipeAndMake(drink, waterType, channels),
        style: ElevatedButton.styleFrom(backgroundColor: isHot ? Colors.orange[100] : Colors.cyan[100]),
        child: const Text('Make'),
      ),
    );
  }

  Future<void> _setRecipeAndMake(DrinkNumber drink, WaterType waterType, List<int> channels) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }
    try {
      final steps = <RecipeStep>[
        RecipeStep.cupDispense(dispenser: 0), // 수동 컵 배치 대기
      ];
      for (final ch in channels) {
        final isLast = ch == channels.last;
        steps.add(RecipeStep.instantChannel(
          channel: ch,
          waterType: waterType,
          materialDuration: 10,
          waterAmount: isLast ? 2000 : 10,  // WD >= MD 필수
          materialSpeed: 50,
          mixSpeed: isLast && channels.length > 1 ? 100 : 0,
        ));
      }

      final chNames = channels.map((c) => '${c + 1}번통').join('+');

      // 디버깅: 보내는 바이트 로그
      final cmdBytes = steps.expand((s) => s.toBytes()).toList();
      final hexStr = cmdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      _addEventLog('Recipe bytes: [${drink.code.toRadixString(16)}] $hexStr');

      _addEventLog('Setting recipe: ${drink.displayName} ($chNames)...');
      try {
        await _gs805.setDrinkRecipeProcess(drink, steps);
        _addEventLog('Recipe set OK (RSTA=0x00)');
      } catch (e) {
        _addEventLog('Recipe set FAILED: $e');
        _showSnackBar('Recipe failed: $e', Colors.red);
        return;
      }
      _addEventLog('Making ${drink.displayName}...');
      await _gs805.makeDrink(drink);
      _showSnackBar('$chNames 제조 시작', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed: $e', Colors.red);
    }
  }

  // ========== Settings Panel ==========

  Widget _buildSettingsPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // --- Status Queries ---
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Status Queries', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.monitor_heart, color: Colors.green),
          title: const Text('Machine Status (0x0B)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final status = await _gs805.getMachineStatus();
                _addEventLog('[0x0B] code: 0x${status.code.toRadixString(16)} | ${status.message}');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.error_outline, color: Colors.orange),
          title: const Text('Error Code (0x0C)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final error = await _gs805.getErrorCode();
                _addEventLog('[0x0C] errorCode: 0x${error.errorCode.toRadixString(16)} (${error.errorCode})');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.info_outline, color: Colors.orange),
          title: const Text('Error Info (상세)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final info = await _gs805.getErrorInfo();
                _addEventLog('[ErrorInfo] error: ${info.error}');
                _addEventLog('  severity: ${info.severity}');
                _addEventLog('  actions: ${info.recoveryActions.join(", ")}');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.dashboard, color: Colors.blue),
          title: const Text('Controller Status (0x1E)'),
          subtitle: const Text('32비트 상세 상태'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final s = await _gs805.getControllerStatus();
                _addEventLog('[0x1E] overall: ${s.overallStatus}');
                _addEventLog('  frontDoor: ${s.isFrontDoorOffline ? "OFFLINE" : "online"}');
                _addEventLog('  iceMaker: ${s.isIceOffline ? "OFFLINE" : "online"}');
                _addEventLog('  grinder: ${s.isGrindingOffline ? "OFFLINE" : "online"}');
                _addEventLog('  cup: ${s.hasNoCup ? "NO CUP" : "present"}');
                _addEventLog('  waterLow: ${s.isWaterTankLow}');
                _addEventLog('  wasteWarning: ${s.isWasteTankWarning}');
                _addEventLog('  rawBits: 0x${s.rawValue.toRadixString(16).padLeft(8, '0')}');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.local_cafe, color: Colors.brown),
          title: const Text('Drink Status (0x1F)'),
          subtitle: const Text('음료 제작 진행 상태'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final s = await _gs805.getDrinkStatus();
                _addEventLog('[0x1F] result: ${s.result}');
                _addEventLog('  drinkNo: ${s.drinkNumber}');
                _addEventLog('  progress: step ${s.currentStep}/${s.totalSteps}');
                _addEventLog('  failCause: ${s.failureCause}');
                _addEventLog('  rawBits: 0x${s.rawValue.toRadixString(16).padLeft(8, '0')}');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.account_balance_wallet, color: Colors.teal),
          title: const Text('Balance (0x0F)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                final b = await _gs805.getBalance();
                _addEventLog('[0x0F] balance: ${b.balance} tokens');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Query'),
          ),
        ),

        // --- Temperature ---
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Temperature', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo)),
        ),
        ListTile(
          dense: true,
          title: const Text('Set Hot Temp (65/60)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                await _gs805.setHotTemperature(65, 60);
                _addEventLog('Hot temp set: upper=65, lower=60');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Set'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          title: const Text('Set Cold Temp (10/5)'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                await _gs805.setColdTemperature(10, 5);
                _addEventLog('Cold temp set: upper=10, lower=5');
              } catch (e) { _showSnackBar('$e', Colors.red); }
            },
            child: const Text('Set'),
          ),
        ),
      ],
    );
  }

  // ========== Payment Panel (MDB Cashless) ==========

  Widget _buildPaymentPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // MDB Connection
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MDB-RS232 Bridge',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<SerialDevice>(
                        value: _selectedMdbDevice,
                        hint: const Text('Select MDB device'),
                        isExpanded: true,
                        items: _mdbDevices.map((device) {
                          return DropdownMenuItem(
                            value: device,
                            child: Text(
                              '${device.name} (${device.vendorId?.toRadixString(16) ?? ''})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (device) {
                          setState(() {
                            _selectedMdbDevice = device;
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadMdbDevices,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _mdbConnected ? null : _mdbConnect,
                      icon: const Icon(Icons.cable, size: 18),
                      label: const Text('Connect'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _mdbConnected ? _mdbDisconnect : null,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Disconnect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[300],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: _mdbConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _mdbConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        fontSize: 12,
                        color: _mdbConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Cashless State
        Card(
          color: _cashlessStateColor,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(_cashlessStateIcon, size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Card Reader Status',
                        style: TextStyle(fontSize: 12)),
                    Text(
                      _cashlessState.displayName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Setup & Control
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reader Control',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _mdbConnected ? _mdbSetup : null,
                      child: const Text('Setup'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? _mdbEnable : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[100]),
                      child: const Text('Enable'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? _mdbDisable : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[100]),
                      child: const Text('Disable'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? _mdbRequestId : null,
                      child: const Text('Reader ID'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? _mdbCashSale : null,
                      child: const Text('Cash Sale'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Vend Control
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payment',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // Price input
                Row(
                  children: [
                    const Text('Price: '),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        initialValue: _vendPrice.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          _vendPrice = int.tryParse(value) ?? _vendPrice;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(0x${_vendPrice.toRadixString(16).toUpperCase()})',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Vend actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          (_mdbConnected && _cashlessState == CashlessState.sessionIdle)
                              ? _mdbRequestVend
                              : null,
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Request Vend'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[100]),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          (_mdbConnected && _cashlessState == CashlessState.vending)
                              ? _mdbVendSuccess
                              : null,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Vend Success'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[100]),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          (_mdbConnected &&
                                  (_cashlessState == CashlessState.vendRequested ||
                                      _cashlessState == CashlessState.vending))
                              ? _mdbVendCancel
                              : null,
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('Vend Cancel'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[100]),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Flow guide
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment Flow:',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        '1. Setup > Enable\n'
                        '2. Wait for card tap (Card Detected)\n'
                        '3. Request Vend (send price)\n'
                        '4. Wait for approval\n'
                        '5. Dispense product > Vend Success',
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color get _cashlessStateColor {
    switch (_cashlessState) {
      case CashlessState.inactive:
        return Colors.grey[200]!;
      case CashlessState.disabled:
        return Colors.orange[50]!;
      case CashlessState.enabled:
        return Colors.blue[50]!;
      case CashlessState.sessionIdle:
        return Colors.green[50]!;
      case CashlessState.vendRequested:
        return Colors.amber[50]!;
      case CashlessState.vending:
        return Colors.green[100]!;
      case CashlessState.error:
        return Colors.red[50]!;
    }
  }

  IconData get _cashlessStateIcon {
    switch (_cashlessState) {
      case CashlessState.inactive:
        return Icons.power_off;
      case CashlessState.disabled:
        return Icons.block;
      case CashlessState.enabled:
        return Icons.contactless;
      case CashlessState.sessionIdle:
        return Icons.credit_card;
      case CashlessState.vendRequested:
        return Icons.hourglass_top;
      case CashlessState.vending:
        return Icons.check_circle;
      case CashlessState.error:
        return Icons.error;
    }
  }

  Widget _buildMaintenancePanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // --- Front Door Control ---
        ListTile(
          dense: true,
          leading: const Icon(Icons.door_front_door),
          title: const Text('Front Door (0x1A testCmd=3)'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _gs805.unitFunctionTest(3, 4, 0, 0);
                    _addEventLog('Door: open (cmd=3, data1=4, data2=0)');
                  } catch (e) {
                    _showSnackBar('Door failed: $e', Colors.red);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                child: const Text('Open'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _gs805.unitFunctionTest(3, 4, 1, 0);
                    _addEventLog('Door: close (cmd=3, data1=4, data2=1)');
                  } catch (e) {
                    _showSnackBar('Door failed: $e', Colors.red);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.coffee_maker),
          title: const Text('Test Cup Drop'),
          subtitle: const Text('Test the cup dispensing mechanism'),
          trailing: ElevatedButton(
            onPressed: _testCupDrop,
            child: const Text('Test'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cleaning_services),
          title: const Text('Clean All Pipes'),
          subtitle: const Text('Clean all instant coffee pipes'),
          trailing: ElevatedButton(
            onPressed: _cleanAllPipes,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[300],
            ),
            child: const Text('Clean'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clean Specific Pipe'),
          subtitle: const Text('Clean pipe #1'),
          trailing: ElevatedButton(
            onPressed: () => _cleanSpecificPipe(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[200],
            ),
            child: const Text('Clean #1'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.build),
          title: const Text('Auto Inspection'),
          subtitle: const Text('Run automatic system inspection'),
          trailing: ElevatedButton(
            onPressed: () async {
              try {
                await _gs805.autoInspection();
                _addEventLog('Auto inspection started');
              } catch (e) {
                _showSnackBar('Inspection failed: $e', Colors.red);
              }
            },
            child: const Text('Inspect'),
          ),
        ),

        // --- Error Info ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Diagnostics',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Get Error Code'),
          subtitle: const Text('Query current machine error code'),
          trailing: ElevatedButton(
            onPressed: _getErrorCode,
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Get Error Info'),
          subtitle: const Text('Detailed error with recovery actions'),
          trailing: ElevatedButton(
            onPressed: _getErrorInfo,
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.money_off),
          title: const Text('Return Change'),
          subtitle: const Text('Trigger coin changer to return change'),
          trailing: ElevatedButton(
            onPressed: _returnChange,
            child: const Text('Return'),
          ),
        ),

        // --- Temperature & Settings ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Temperature & Settings',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.thermostat, color: Colors.red),
          title: const Text('Set Hot Temperature'),
          subtitle: const Text('Upper: 65, Lower: 60'),
          trailing: ElevatedButton(
            onPressed: _setHotTemperature,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[100],
            ),
            child: const Text('Set'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.thermostat, color: Colors.blue),
          title: const Text('Set Cold Temperature'),
          subtitle: const Text('Upper: 10, Lower: 5'),
          trailing: ElevatedButton(
            onPressed: _setColdTemperature,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[100],
            ),
            child: const Text('Set'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.coffee),
          title: const Text('Cup Drop Mode'),
          subtitle: const Text('Set automatic or manual cup drop'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => _setCupDropMode(CupDropModeEnum.automatic),
                child: const Text('Auto'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _setCupDropMode(CupDropModeEnum.manual),
                child: const Text('Manual'),
              ),
            ],
          ),
        ),

        // --- Pricing & Sales ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Pricing & Sales',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.attach_money),
          title: const Text('Set Drink Price'),
          subtitle: const Text('Hot Drink 1 = 10 tokens'),
          trailing: ElevatedButton(
            onPressed: _setDrinkPrice,
            child: const Text('Set'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: const Text('Get Sales Count'),
          subtitle: const Text('Query Hot Drink 1 sales statistics'),
          trailing: ElevatedButton(
            onPressed: _getSalesCount,
            child: const Text('Query'),
          ),
        ),
      ],
    );
  }

  // ========== Extended Panel (R-Series Commands) ==========

  Widget _buildExtendedPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // --- Controller & Status ---
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Status Queries',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.developer_board),
          title: const Text('Get Controller Status'),
          subtitle: const Text('Query main controller status (R series)'),
          trailing: ElevatedButton(
            onPressed: _getControllerStatus,
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.local_cafe),
          title: const Text('Get Drink Status'),
          subtitle: const Text('Query drink preparation progress'),
          trailing: ElevatedButton(
            onPressed: _getDrinkStatus,
            child: const Text('Query'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.warning_amber),
          title: const Text('Get Object Exception'),
          subtitle: const Text('Query pump exception info'),
          trailing: ElevatedButton(
            onPressed: _getObjectException,
            child: const Text('Query'),
          ),
        ),

        // --- Door Lock ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Door Lock Control',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.lock),
          title: const Text('Lock Door'),
          subtitle: const Text('Lock the electronic door lock'),
          trailing: ElevatedButton(
            onPressed: _lockDoor,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[100],
            ),
            child: const Text('Lock'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.lock_open),
          title: const Text('Unlock Door'),
          subtitle: const Text('Unlock the electronic door lock'),
          trailing: ElevatedButton(
            onPressed: _unlockDoor,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[100],
            ),
            child: const Text('Unlock'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.lock_clock),
          title: const Text('Get Lock Status'),
          subtitle: const Text('Query current lock state'),
          trailing: ElevatedButton(
            onPressed: _getLockStatus,
            child: const Text('Query'),
          ),
        ),

        // --- Machine Control ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Machine Control',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.science),
          title: const Text('Unit Function Test'),
          subtitle: const Text('Run dispensing test (cmd=1)'),
          trailing: ElevatedButton(
            onPressed: _unitFunctionTest,
            child: const Text('Test'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.water_drop),
          title: const Text('Water Refill'),
          subtitle: const Text('Trigger water tank refill'),
          trailing: ElevatedButton(
            onPressed: _waterRefill,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[100],
            ),
            child: const Text('Refill'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.coffee_maker),
          title: const Text('Cup Delivery'),
          subtitle: const Text('Deliver cup to holder (30s timeout)'),
          trailing: ElevatedButton(
            onPressed: _cupDelivery,
            child: const Text('Deliver'),
          ),
        ),

        // --- Force Stop ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Force Stop',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.stop_circle, color: Colors.red),
          title: const Text('Force Stop Drink Process'),
          subtitle: const Text('Immediately stop current drink making'),
          trailing: ElevatedButton(
            onPressed: _forceStopDrinkProcess,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[300],
            ),
            child: const Text('Stop'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.stop_circle_outlined, color: Colors.red),
          title: const Text('Force Stop Cup Delivery'),
          subtitle: const Text('Immediately stop cup delivery'),
          trailing: ElevatedButton(
            onPressed: _forceStopCupDelivery,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[200],
            ),
            child: const Text('Stop'),
          ),
        ),

        // --- Recipe Commands ---
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Recipe Commands',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long),
          title: const Text('Set Drink Recipe'),
          subtitle: const Text('Set Hot Drink 1 recipe (cup + instant channel)'),
          trailing: ElevatedButton(
            onPressed: _setDrinkRecipeProcess,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[100],
            ),
            child: const Text('Set'),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.play_circle),
          title: const Text('Execute Channel'),
          subtitle: const Text('Ch0, hot, mat=1000, water=2000, speed=50'),
          trailing: ElevatedButton(
            onPressed: _executeChannel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[100],
            ),
            child: const Text('Execute'),
          ),
        ),
      ],
    );
  }

  // ========== Debug Panel ==========

  final _uartChannel = const MethodChannel('gs805serial/uart');
  final List<String> _debugLog = [];
  final TextEditingController _shellCmdController = TextEditingController();
  final TextEditingController _pidController = TextEditingController();

  Future<void> _checkPortInfo(String port) async {
    try {
      final result = await _uartChannel.invokeMethod('portInfo', {'path': port});
      if (result != null) {
        final info = Map<String, dynamic>.from(result as Map);
        setState(() {
          _debugLog.insert(0, '--- $port ---');
          _debugLog.insert(1, 'exists: ${info['exists']}, readable: ${info['readable']}, writable: ${info['writable']}');
          _debugLog.insert(2, 'ls: ${info['ls'] ?? 'N/A'}');
          _debugLog.insert(3, 'pids: ${info['pids']?.toString().trim().isEmpty == true ? 'none' : info['pids']}');
          if (_debugLog.length > 100) _debugLog.removeRange(100, _debugLog.length);
        });
      } else {
        setState(() => _debugLog.insert(0, '[$port] No result returned'));
      }
    } catch (e) {
      setState(() => _debugLog.insert(0, 'portInfo error: $e'));
    }
  }

  Future<void> _runShellCmd(String command) async {
    if (command.isEmpty) return;
    setState(() => _debugLog.insert(0, '[sending] \$ $command'));
    try {
      final result = await _uartChannel.invokeMethod('shellCommand', {'command': command}).timeout(const Duration(seconds: 10));
      setState(() {
        _debugLog.insert(0, '\$ $command');
        if (result != null) {
          final info = Map<String, dynamic>.from(result as Map);
          final stdout = (info['stdout'] as String?)?.trim() ?? '';
          final stderr = (info['stderr'] as String?)?.trim() ?? '';
          if (stdout.isNotEmpty) {
            for (final line in stdout.split('\n').reversed) {
              _debugLog.insert(1, line);
            }
          }
          if (stderr.isNotEmpty) _debugLog.insert(1, '[err] $stderr');
        } else {
          _debugLog.insert(1, '(no output)');
        }
        if (_debugLog.length > 200) _debugLog.removeRange(200, _debugLog.length);
      });
    } catch (e) {
      setState(() {
        _debugLog.insert(0, '\$ $command');
        _debugLog.insert(1, 'ERROR: $e');
      });
    }
  }

  Future<void> _killPid(int pid) async {
    try {
      final result = await _uartChannel.invokeMethod('killProcess', {'pid': pid});
      setState(() {
        if (result != null) {
          final info = Map<String, dynamic>.from(result as Map);
          _debugLog.insert(0, 'kill -9 $pid: ${info['success'] == true ? 'SUCCESS' : 'FAILED'}');
          final stderr = (info['stderr'] as String?)?.trim() ?? '';
          if (stderr.isNotEmpty) _debugLog.insert(1, stderr);
        } else {
          _debugLog.insert(0, 'kill -9 $pid: no result');
        }
      });
    } catch (e) {
      setState(() => _debugLog.insert(0, 'Kill error: $e'));
    }
  }

  Widget _buildDebugPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // Port Info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Port Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final port in ['/dev/ttyS2', '/dev/ttyS6', '/dev/ttyS0', '/dev/ttyS1', '/dev/ttyS3'])
                      ElevatedButton(
                        onPressed: () => _checkPortInfo(port),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (port == '/dev/ttyS2' || port == '/dev/ttyS6')
                              ? Colors.orange[100]
                              : null,
                        ),
                        child: Text(port.replaceAll('/dev/', ''), style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Kill Process
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kill Process', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('PID: '),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _pidController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                          hintText: 'PID',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final pid = int.tryParse(_pidController.text);
                        if (pid != null) _killPid(pid);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
                      child: const Text('Kill'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Shell Command
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Shell Command', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _shellCmdController,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                          hintText: 'ls -la /dev/ttyS*',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _runShellCmd(_shellCmdController.text),
                      child: const Text('Run'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _shellPreset('su 0 am force-stop com.yj.coffeemachines'),
                    _shellPreset('su 0 sh -c "timeout 15 cat /dev/ttyS7 > /data/local/tmp/ttyS7.bin &"'),
                    _shellPreset('su 0 am start -n com.yj.coffeemachines/.MainActivity'),
                    _shellPreset('su 0 xxd /data/local/tmp/ttyS7.bin'),
                    _shellPreset('su 0 sh -c "strace -p \$(pidof com.yj.coffeemachines) -e write -s 256 -x 2>/data/local/tmp/strace.log &"'),
                    _shellPreset('su 0 sh -c "cat /data/local/tmp/strace.log | grep ttyS7 | tail -30"'),
                    _shellPreset('su 0 sh -c "cat /data/local/tmp/strace.log | grep -i aa55 | tail -20"'),
                    _shellPreset('su 0 sh -c "cat /data/local/tmp/strace.log | tail -50"'),
                    _shellPreset('su 0 sh -c "echo AA55020B0C | xxd -r -p > /dev/ttyS7 & timeout 1 cat /dev/ttyS7 | xxd"'),
                    _shellPreset('su 0 sh -c "echo AA55121D01010D010000320032 0000FF00000000A1 | xxd -r -p > /dev/ttyS7 & timeout 1 cat /dev/ttyS7 | xxd"'),
                    _shellPreset('curl -s --connect-timeout 3 http://192.168.0.140:8000/ 2>/dev/null'),
                    _shellPreset('curl http://192.168.0.140:8000/ 2>&1'),
                    _shellPreset('wget -q -O - http://192.168.0.140:8000/ 2>&1'),
                    _shellPreset('ping -c 1 192.168.0.140'),
                    _shellPreset('which curl'),
                    _shellPreset('which wget'),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Debug Log
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Output', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        final text = _debugLog.join('\n');
                        Clipboard.setData(ClipboardData(text: text));
                        _showSnackBar('Copied to clipboard', Colors.green);
                      },
                      child: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _debugLog.clear()),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Container(
                  height: 250,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: _debugLog.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _debugLog[index],
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.greenAccent),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _shellPreset(String cmd) {
    return InkWell(
      onTap: () {
        _shellCmdController.text = cmd;
        _runShellCmd(cmd);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(cmd, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
      ),
    );
  }

  // ========== System Panel ==========

  static const _updateServerUrl = 'http://192.168.0.140:8000';
  bool _updateAvailable = false;
  bool _checkingUpdate = false;
  bool _downloading = false;
  String _systemLog = '';
  String _apkDownloadUrl = '';

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _systemLog = 'Checking for update...';
    });
    try {
      final result = await _uartChannel.invokeMethod('httpGet', {
        'url': '$_updateServerUrl/'
      });
      if (result != null) {
        final info = Map<String, dynamic>.from(result as Map);
        final body = (info['body'] as String?)?.trim() ?? '';
        final statusCode = info['statusCode'] ?? 0;
        setState(() => _systemLog = 'Server responded: HTTP $statusCode');

        // Find APK link - try href first, then just filename
        final hrefMatch = RegExp(r'href="([^"]*app-debug\.apk[^"]*)"').firstMatch(body);
        if (hrefMatch != null) {
          final href = hrefMatch.group(1)!;
          _apkDownloadUrl = href.startsWith('http') ? href : '$_updateServerUrl/$href';
          setState(() {
            _updateAvailable = true;
            _systemLog = 'Update available: $href';
          });
        } else if (body.contains('app-debug.apk')) {
          _apkDownloadUrl = '$_updateServerUrl/app-debug.apk';
          setState(() {
            _updateAvailable = true;
            _systemLog = 'Update available: app-debug.apk';
          });
        } else {
          setState(() {
            _updateAvailable = false;
            _systemLog = 'No APK found on server';
          });
        }
      }
    } catch (e) {
      setState(() {
        _systemLog = 'Server unreachable: $e';
        _updateAvailable = false;
      });
    } finally {
      setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _systemLog = 'Downloading from $_apkDownloadUrl ...';
    });
    try {
      final savePath = '/sdcard/Download/update.apk';

      // Download APK via native HTTP
      final dlResult = await _uartChannel.invokeMethod('httpDownload', {
        'url': _apkDownloadUrl,
        'savePath': savePath,
      });
      if (dlResult != null) {
        final info = Map<String, dynamic>.from(dlResult as Map);
        final size = info['size'] ?? 0;
        setState(() => _systemLog = 'Downloaded ${(size / 1024 / 1024).toStringAsFixed(1)}MB');
      }

      setState(() => _systemLog = 'Download complete. Ready to install.');

      if (!mounted) return;
      // Show dialog BEFORE install (pm install kills the app)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Downloaded'),
          content: const Text('Install and restart now?\n\nThe app will close and reopen automatically.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _systemLog = 'Installing...');
                // Install only - user reopens manually
                final installResult = await _uartChannel.invokeMethod('shellCommand', {
                  'command': 'su 0 pm install -r -d $savePath 2>&1'
                });
                if (installResult != null) {
                  final info = Map<String, dynamic>.from(installResult as Map);
                  final output = ((info['stdout'] as String?) ?? '').trim();
                  if (output.contains('Success')) {
                    setState(() => _systemLog = 'Install complete!\nPlease reopen the app.');
                  } else {
                    setState(() => _systemLog = 'Install result: $output');
                  }
                }
              },
              child: const Text('Install & Restart'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _systemLog = 'Update failed: $e');
    } finally {
      setState(() => _downloading = false);
    }
  }

  Widget _buildSystemPanel() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        // Auto Update
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App Update', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Server: $_updateServerUrl', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _checkingUpdate ? null : _checkForUpdate,
                      child: _checkingUpdate
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Check Update'),
                    ),
                    const SizedBox(width: 12),
                    if (_updateAvailable)
                      ElevatedButton(
                        onPressed: _downloading ? null : _downloadAndInstall,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                        child: _downloading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Update Now'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_systemLog.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_systemLog, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _eventLogExpanded = true;

  Widget _buildEventLog() {
    return Container(
      height: _eventLogExpanded ? 150 : 30,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _eventLogExpanded = !_eventLogExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Icon(
                    _eventLogExpanded ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                  ),
                  const Text(
                    'Event Log',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const Spacer(),
                  if (_eventLogExpanded) ...[
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _eventLog.join('\n')));
                        _showSnackBar('Event log copied', Colors.green);
                      },
                      child: const Text('Copy', style: TextStyle(fontSize: 12, color: Colors.blue)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _eventLog.clear()),
                      child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.blue)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_eventLogExpanded)
            Expanded(
              child: ListView.builder(
                reverse: false,
                itemCount: _eventLog.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 2.0,
                    ),
                    child: Text(
                      _eventLog[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: _eventLog[index].contains('[MDB]')
                            ? Colors.indigo
                            : Colors.black87,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
