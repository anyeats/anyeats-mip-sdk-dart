import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:gs805serial/gs805serial.dart';

part 'panels/channel_panel.dart';
part 'panels/payment_panel.dart';
part 'panels/maintenance_panel.dart';
part 'panels/extended_panel.dart';
part 'panels/settings_panel.dart';
part 'panels/debug_panel.dart';
part 'panels/system_panel.dart';

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

  // Debug panel fields
  final _uartChannel = const MethodChannel('gs805serial/uart');
  final List<String> _debugLog = [];
  final TextEditingController _shellCmdController = TextEditingController();
  final TextEditingController _pidController = TextEditingController();

  // System panel fields
  static const _updateServerUrl = 'http://192.168.0.140:8000';
  bool _updateAvailable = false;
  bool _checkingUpdate = false;
  bool _downloading = false;
  String _systemLog = '';
  String _apkDownloadUrl = '';

  // Drink status polling
  bool _drinkPolling = false;

  // Event log expanded state
  bool _eventLogExpanded = true;

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

  // ─── Drink Status Polling ───

  /// makeDrink 호출 후 상태 변화 폴링 시작 (2초 간격, 최대 3분)
  Future<void> _startDrinkStatusPolling() async {
    if (_drinkPolling) return;
    _drinkPolling = true;
    _addEventLog('--- STATUS POLL START ---');

    String? prevMachine;
    String? prevResult;
    bool? prevWaitRet;
    bool? prevCupPlaced;
    int? prevStep;
    bool? prevSuccess;

    final stopwatch = Stopwatch()..start();
    while (_drinkPolling && stopwatch.elapsed.inSeconds < 180) {
      await Future.delayed(const Duration(seconds: 2));
      if (!_isConnected || !_drinkPolling) break;

      try {
        // getMachineStatus
        final ms = await _gs805.getMachineStatus();
        final msStr = '${ms.message}(0x${ms.code.toRadixString(16)})';

        // getDrinkStatus
        final ds = await _gs805.getDrinkStatus();
        final resultStr = '${ds.result}';
        final stepStr = '${ds.currentStep}/${ds.totalSteps}';
        final progress = '${(ds.progress * 100).toStringAsFixed(0)}%';

        // 변화 감지 — 바뀐 것만 로그
        final changes = <String>[];
        if (msStr != prevMachine) {
          changes.add('Machine:$msStr');
          prevMachine = msStr;
        }
        if (resultStr != prevResult) {
          changes.add('Result:$resultStr');
          prevResult = resultStr;
        }
        if (ds.currentStep != prevStep) {
          changes.add('Step:$stepStr($progress)');
          prevStep = ds.currentStep;
        }
        if (ds.isWaitingForRetrieval != prevWaitRet) {
          changes.add('WaitRetrieval:${ds.isWaitingForRetrieval}');
          prevWaitRet = ds.isWaitingForRetrieval;
        }
        if (ds.isCupPlaced != prevCupPlaced) {
          changes.add('CupPlaced:${ds.isCupPlaced}');
          prevCupPlaced = ds.isCupPlaced;
        }
        if (ds.isSuccess != prevSuccess) {
          changes.add('isSuccess:${ds.isSuccess}');
          prevSuccess = ds.isSuccess;
        }

        if (changes.isNotEmpty) {
          _addEventLog('[POLL] ${changes.join(' | ')}');
        }

        // Ready 상태 복귀 시 폴링 종료
        if (ms.isReady && (ds.isSuccess || ds.isFailed)) {
          _addEventLog('--- STATUS POLL END (${stopwatch.elapsed.inSeconds}s) ---');
          break;
        }
      } catch (e) {
        _addEventLog('[POLL] error: $e');
      }
    }

    stopwatch.stop();
    _drinkPolling = false;
  }

  void _stopDrinkStatusPolling() {
    _drinkPolling = false;
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
