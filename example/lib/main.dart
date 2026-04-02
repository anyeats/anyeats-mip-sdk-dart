import 'package:flutter/material.dart';
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
        if (devices.isNotEmpty) {
          _selectedDevice = devices.first;
        }
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
        if (devices.isNotEmpty && _selectedMdbDevice == null) {
          _selectedMdbDevice = devices.first;
        }
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

  Future<void> _makeDrink(DrinkNumber drink) async {
    if (!_isConnected) {
      _showSnackBar('Not connected', Colors.orange);
      return;
    }

    try {
      await _gs805.makeDrink(drink);
      _addEventLog('Making ${drink.displayName}...');
      _showSnackBar('Making ${drink.displayName}...', Colors.blue);
    } catch (e) {
      _showSnackBar('Failed to make drink: $e', Colors.red);
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
      await _gs805.setHotTemperature(90, 70);
      _addEventLog('Hot temp set: upper=90, lower=70');
      _showSnackBar('Hot temperature set (90/70)', Colors.green);
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
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
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
        title: const Text('GS805 Coffee Machine'),
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
          // Connection Panel
          _buildConnectionPanel(),

          // Status Panel
          if (_isConnected) _buildStatusPanel(),

          // Tabs
          if (_isConnected)
            Expanded(
              child: DefaultTabController(
                length: 5,
                child: Column(
                  children: [
                    const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: 'Hot'),
                        Tab(text: 'Cold'),
                        Tab(text: 'Payment'),
                        Tab(text: 'Maint.'),
                        Tab(text: 'Extended'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildDrinkGrid(DrinkNumber.hotDrinks),
                          _buildDrinkGrid(DrinkNumber.coldDrinks),
                          _buildPaymentPanel(),
                          _buildMaintenancePanel(),
                          _buildExtendedPanel(),
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

  Widget _buildConnectionPanel() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<SerialDevice>(
                    value: _selectedDevice,
                    hint: const Text('Select device'),
                    isExpanded: true,
                    items: _devices.map((device) {
                      return DropdownMenuItem(
                        value: device,
                        child: Text(
                          '${device.name} (VID: ${device.vendorId?.toRadixString(16) ?? 'N/A'}, '
                          'PID: ${device.productId?.toRadixString(16) ?? 'N/A'})',
                        ),
                      );
                    }).toList(),
                    onChanged: (device) {
                      setState(() {
                        _selectedDevice = device;
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadDevices,
                  tooltip: 'Refresh devices',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isConnected ? null : _connect,
                  icon: const Icon(Icons.usb),
                  label: const Text('Connect'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _disconnect : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Disconnect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[300],
                  ),
                ),
                const SizedBox(width: 16),
                if (_isConnected)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshStatus,
                    tooltip: 'Refresh status',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      color: _machineStatus == MachineStatus.ready
          ? Colors.green[50]
          : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              _machineStatus == MachineStatus.ready
                  ? Icons.check_circle
                  : Icons.info,
              color: _machineStatus == MachineStatus.ready
                  ? Colors.green
                  : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status: $_statusMessage',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_balance != null)
                    Text(
                      'Balance: $_balance tokens',
                      style: const TextStyle(fontSize: 14),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrinkGrid(List<DrinkNumber> drinks) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: drinks.length,
      itemBuilder: (context, index) {
        final drink = drinks[index];
        return ElevatedButton(
          onPressed: () => _makeDrink(drink),
          style: ElevatedButton.styleFrom(
            backgroundColor: drink.isHot ? Colors.red[100] : Colors.blue[100],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                drink.isHot ? Icons.local_cafe : Icons.local_drink,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                drink.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
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
        // --- Existing maintenance items ---
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
          subtitle: const Text('Upper: 90, Lower: 70'),
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

  Widget _buildEventLog() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text(
                  'Event Log',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _eventLog.clear();
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
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
