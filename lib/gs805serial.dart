/// GS805 Serial Communication Library
///
/// High-level API for communicating with GS805 coffee machines.

library gs805serial;

// Export all public APIs
export 'src/models/models.dart';
export 'src/protocol/protocol.dart';
export 'src/serial/serial.dart';
export 'src/exceptions/exceptions.dart';
export 'src/utils/gs805_logger.dart';
export 'src/utils/command_queue.dart';
export 'src/mdb/mdb.dart';

import 'dart:async';
import 'src/serial/usb_serial_connection.dart';
import 'src/serial/serial_manager.dart';
import 'src/serial/serial_connection.dart';
import 'src/serial/reconnect_manager.dart';
import 'src/protocol/gs805_protocol.dart';
import 'src/protocol/gs805_message.dart';
import 'src/models/drink_info.dart';
import 'src/models/machine_status.dart';
import 'src/models/error_code.dart';
import 'src/models/recipe_step.dart';
import 'src/models/controller_models.dart';
import 'src/exceptions/gs805_exception.dart';
import 'src/utils/gs805_logger.dart';
import 'src/utils/command_queue.dart';

/// High-level GS805 coffee machine controller
///
/// This class provides a simple, easy-to-use interface for controlling
/// GS805 coffee machines via serial communication.
///
/// Example:
/// ```dart
/// final gs805 = GS805Serial();
///
/// // List available devices
/// final devices = await gs805.listDevices();
///
/// // Connect
/// await gs805.connect(devices.first);
///
/// // Make a drink
/// await gs805.makeDrink(DrinkNumber.hotDrink1);
///
/// // Disconnect
/// await gs805.disconnect();
/// ```
class GS805Serial {
  SerialManager? _manager;
  final SerialConnection _connection;
  final ReconnectConfig? _reconnectConfig;
  final GS805Logger _logger;
  CommandQueue? _commandQueue;
  final bool _enableLogging;
  final bool _enableCommandQueue;

  /// Create a GS805 serial controller
  ///
  /// [connection] - Serial connection implementation (defaults to USB)
  /// [reconnectConfig] - Optional reconnection configuration
  /// [enableLogging] - Enable logging (default: false)
  /// [enableCommandQueue] - Enable command queue (default: false)
  /// [logger] - Custom logger instance (optional)
  GS805Serial({
    SerialConnection? connection,
    ReconnectConfig? reconnectConfig,
    bool enableLogging = false,
    bool enableCommandQueue = false,
    GS805Logger? logger,
  })  : _connection = connection ?? UsbSerialConnection(),
        _reconnectConfig = reconnectConfig,
        _enableLogging = enableLogging,
        _enableCommandQueue = enableCommandQueue,
        _logger = logger ?? GS805Logger() {
    _manager = SerialManager(_connection, reconnectConfig: reconnectConfig);

    // Initialize logger
    if (_enableLogging) {
      _logger.info('GS805Serial', 'Logger initialized');
    }

    // Initialize command queue
    if (_enableCommandQueue) {
      _commandQueue = CommandQueue(
        sendFunction: (cmd) => _manager!.sendCommand(cmd),
      );
      if (_enableLogging) {
        _logger.info('GS805Serial', 'Command queue initialized');
      }
    }
  }

  // ========== Connection Management ==========

  /// List available serial devices
  Future<List<SerialDevice>> listDevices() async {
    return await _connection.listDevices();
  }

  /// Connect to a device
  ///
  /// [device] - Device to connect to
  /// [config] - Optional serial configuration (defaults to GS805 config)
  Future<void> connect(
    SerialDevice device, {
    SerialConfig? config,
  }) async {
    if (_enableLogging) {
      _logger.info('Connection', 'Connecting to ${device.name}...');
    }
    try {
      await _manager!.connect(device, config ?? SerialConfig.gs805);
      if (_enableLogging) {
        _logger.info('Connection', 'Connected successfully to ${device.name}');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Connection', 'Failed to connect to ${device.name}',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Connect to the first available device
  Future<void> connectToFirstDevice({SerialConfig? config}) async {
    final devices = await listDevices();
    if (devices.isEmpty) {
      throw ConnectionException('No devices found');
    }
    await connect(devices.first, config: config);
  }

  /// Connect to a device by vendor/product ID
  Future<void> connectByVidPid(
    int vendorId,
    int productId, {
    SerialConfig? config,
  }) async {
    final devices = await listDevices();
    final device = devices.where((d) =>
        d.vendorId == vendorId && d.productId == productId).firstOrNull;

    if (device == null) {
      throw ConnectionException(
        'Device not found: VID=${vendorId.toRadixString(16)}, '
        'PID=${productId.toRadixString(16)}',
      );
    }

    await connect(device, config: config);
  }

  /// Disconnect from device
  Future<void> disconnect({bool clearReconnection = true}) async {
    if (_enableLogging) {
      _logger.info('Connection', 'Disconnecting...');
    }
    await _manager?.disconnect(clearReconnection: clearReconnection);
    if (_enableLogging) {
      _logger.info('Connection', 'Disconnected');
    }
  }

  /// Check if currently connected
  bool get isConnected => _manager?.isConnected ?? false;

  /// Get currently connected device
  SerialDevice? get connectedDevice => _manager?.connectedDevice;

  /// Check if currently reconnecting
  bool get isReconnecting => _manager?.isReconnecting ?? false;

  // ========== Drink Making ==========

  /// Make a specified drink
  ///
  /// [drink] - Drink number to make
  /// [useLocalBalance] - If true, use machine's local balance
  /// [timeout] - Command timeout (default: 100ms)
  Future<void> makeDrink(
    DrinkNumber drink, {
    bool useLocalBalance = false,
    Duration timeout = const Duration(milliseconds: 100),
  }) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Drink', 'Making ${drink.displayName}...');
    }

    final command = GS805Protocol.makeDrinkCommand(
      drink.code,
      useLocalBalance: useLocalBalance,
    );

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command, timeout: timeout);
      } else {
        await _manager!.sendCommand(command, timeout: timeout);
      }
      if (_enableLogging) {
        _logger.info('Drink', '${drink.displayName} command sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Drink', 'Failed to make ${drink.displayName}',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Set drink recipe process configuration (R series only)
  ///
  /// Defines a custom multi-step recipe for a drink number.
  /// After setting, call [makeDrink] with the same drink number to execute.
  ///
  /// Set drink recipe time (0x15, Series 3 format)
  ///
  /// Sets material duration and water amount for each channel.
  /// [drink] - Drink number
  /// [channelTimes] - 8 pairs of (materialDuration, waterAmount) in 0.1s units
  Future<void> setDrinkRecipeTime(
    DrinkNumber drink,
    List<(int material, int water)> channelTimes,
  ) async {
    _ensureConnected();

    final command = GS805Protocol.setDrinkRecipeTimeCommand(drink.code, channelTimes);
    await _manager!.sendCommand(command);
  }

  /// [drink] - Drink number to configure
  /// [steps] - List of recipe steps (max 32)
  Future<void> setDrinkRecipeProcess(
    DrinkNumber drink,
    List<RecipeStep> steps,
  ) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Recipe', 'Setting recipe for ${drink.displayName} with ${steps.length} steps...');
    }

    final command = GS805Protocol.setDrinkRecipeProcessCommand(drink.code, steps);

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Recipe', 'Recipe set successfully for ${drink.displayName}');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Recipe', 'Failed to set recipe for ${drink.displayName}',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Execute a single channel immediately (R series only)
  ///
  /// Directly controls a single dispensing channel without saving a recipe.
  /// Useful for one-time operations or dynamic drink composition.
  ///
  /// [channel] - Channel number (0-based, 0 = 1st channel)
  /// [waterType] - Water type (hot or cold)
  /// [materialDuration] - Material dispensing time in 0.1s units (0-999)
  /// [waterAmount] - Water amount in 0.1mL units (0-999)
  /// [materialSpeed] - Material speed 0-100%
  /// [mixSpeed] - Mixing speed 0-100%
  /// [subChannel] - Sub channel (-1 to 127, -1 = none)
  /// [subMaterialDuration] - Sub material time in 0.1s units (0-999)
  /// [subMaterialSpeed] - Sub material speed 0-100%
  /// [endWaitTime] - Wait time after completion in seconds (0-255)
  /// [removeParamLimits] - If true, removes default parameter range limits
  Future<void> executeChannel({
    required int channel,
    WaterType waterType = WaterType.hot,
    int materialDuration = 0,
    int waterAmount = 0,
    int materialSpeed = 50,
    int mixSpeed = 0,
    int subChannel = -1,
    int subMaterialDuration = 0,
    int subMaterialSpeed = 0,
    int endWaitTime = 0,
    bool removeParamLimits = false,
  }) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Channel', 'Executing channel $channel...');
    }

    final command = GS805Protocol.executeChannelCommand(
      channel: channel,
      waterType: waterType.code,
      materialDuration: materialDuration,
      waterAmount: waterAmount,
      materialSpeed: materialSpeed,
      mixSpeed: mixSpeed,
      subChannel: subChannel,
      subMaterialDuration: subMaterialDuration,
      subMaterialSpeed: subMaterialSpeed,
      endWaitTime: endWaitTime,
      removeParamLimits: removeParamLimits,
    );

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Channel', 'Channel $channel executed successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Channel', 'Failed to execute channel $channel',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  // ========== Temperature Control ==========

  /// Set hot drink temperature range
  ///
  /// [upperLimit] - Upper temperature limit (60-99°C)
  /// [lowerLimit] - Lower temperature limit (60-99°C)
  Future<void> setHotTemperature(int upperLimit, int lowerLimit) async {
    _ensureConnected();

    final command = GS805Protocol.setHotTemperatureCommand(
      upperLimit,
      lowerLimit,
    );

    await _manager!.sendCommand(command);
  }

  /// Set cold drink temperature range
  ///
  /// [upperLimit] - Upper temperature limit (2-40°C)
  /// [lowerLimit] - Lower temperature limit (2-40°C)
  Future<void> setColdTemperature(int upperLimit, int lowerLimit) async {
    _ensureConnected();

    final command = GS805Protocol.setColdTemperatureCommand(
      upperLimit,
      lowerLimit,
    );

    await _manager!.sendCommand(command);
  }

  // ========== Information Queries ==========

  /// Get sales count for a drink
  ///
  /// Returns [DrinkSalesCount] with local and command sales statistics
  Future<DrinkSalesCount> getSalesCount(DrinkNumber drink) async {
    _ensureConnected();

    final command = GS805Protocol.getSalesCountCommand(drink.code);
    final response = await _manager!.sendCommand(command);

    // Parse response data
    // DATA: STA + DrinkNo + Local_NUM(4) + Cmd_NUM(4)
    final drinkNo = response.getDataByte(0) ?? 0;
    final localNum = response.getDataDWord(1) ?? 0;
    final cmdNum = response.getDataDWord(5) ?? 0;

    return DrinkSalesCount(
      drink: DrinkNumber.fromCode(drinkNo) ?? DrinkNumber.hotDrink1,
      localSalesCount: localNum,
      commandSalesCount: cmdNum,
    );
  }

  /// Get machine status
  ///
  /// Returns [MachineStatus] indicating the current machine state
  Future<MachineStatus> getMachineStatus() async {
    _ensureConnected();

    final command = GS805Protocol.getMachineStatusCommand();
    final response = await _manager!.sendCommand(command);

    final code = response.statusCode ?? 0;
    return MachineStatus.fromCode(code);
  }

  /// Get error code
  ///
  /// Returns [MachineError] with detailed error information
  Future<MachineError> getErrorCode() async {
    _ensureConnected();

    final command = GS805Protocol.getErrorCodeCommand();
    final response = await _manager!.sendCommand(command);

    // Error code is in the data field (after status)
    final errorCode = response.getDataByte(0) ?? 0;

    return MachineError(errorCode: errorCode);
  }

  /// Get detailed error information with recovery suggestions
  Future<ErrorInfo> getErrorInfo() async {
    final error = await getErrorCode();
    return ErrorInfo.fromError(error);
  }

  /// Get machine balance
  ///
  /// Returns balance in token value (0-99)
  Future<MachineBalance> getBalance() async {
    _ensureConnected();

    final command = GS805Protocol.getBalanceCommand();
    final response = await _manager!.sendCommand(command);

    final balance = response.getDataByte(0) ?? 0;

    return MachineBalance(balance: balance);
  }

  // ========== Machine Control ==========

  /// Set cup drop mode
  ///
  /// [mode] - Cup drop mode (automatic or manual)
  Future<void> setCupDropMode(CupDropModeEnum mode) async {
    _ensureConnected();

    final command = GS805Protocol.setCupDropModeCommand(mode.code);
    await _manager!.sendCommand(command);
  }

  /// Test cup drop function
  Future<void> testCupDrop() async {
    _ensureConnected();

    final command = GS805Protocol.testCupDropCommand();
    await _manager!.sendCommand(command);
  }

  /// Perform automatic inspection
  Future<void> autoInspection() async {
    _ensureConnected();

    final command = GS805Protocol.autoInspectionCommand();
    await _manager!.sendCommand(command);
  }

  /// Clean all instant coffee pipes
  Future<void> cleanAllPipes() async {
    _ensureConnected();

    final command = GS805Protocol.cleanAllPipesCommand();
    await _manager!.sendCommand(command);
  }

  /// Clean specific pipe
  ///
  /// [pipeNumber] - Pipe number to clean
  Future<void> cleanSpecificPipe(int pipeNumber) async {
    _ensureConnected();

    final command = GS805Protocol.cleanSpecificPipeCommand(pipeNumber);
    await _manager!.sendCommand(command);
  }

  /// Return change (for coin dispenser)
  Future<ChangerStatus> returnChange() async {
    _ensureConnected();

    final command = GS805Protocol.returnChangeCommand();
    final response = await _manager!.sendCommand(command);

    // Parse changer status from response
    final statusByte = response.getDataByte(0) ?? 0;

    return ChangerStatus.fromByte(statusByte);
  }

  /// Set drink price
  ///
  /// [drink] - Drink to set price for
  /// [price] - Price in token value (0-99)
  Future<void> setDrinkPrice(DrinkNumber drink, int price) async {
    _ensureConnected();

    final command = GS805Protocol.setDrinkPriceCommand(drink.code, price);
    await _manager!.sendCommand(command);
  }

  // ========== R-Series Commands ==========

  /// Run a unit function test (R series)
  ///
  /// [testCmd] - Test command type (see [UnitTestCommand])
  /// [data1] - Test-specific parameter 1
  /// [data2] - Test-specific parameter 2
  /// [data3] - Test-specific parameter 3
  Future<void> unitFunctionTest(
    int testCmd,
    int data1,
    int data2,
    int data3,
  ) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Test', 'Running unit function test cmd=0x${testCmd.toRadixString(16)}...');
    }

    final command = GS805Protocol.unitFunctionTestCommand(testCmd, data1, data2, data3);

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Test', 'Unit function test command sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Test', 'Failed to run unit function test',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Open the pickup door (front door)
  ///
  /// Physically opens the front door motor for product retrieval.
  /// Not to be confused with [unlockDoor] which only releases the electronic lock.
  Future<void> openPickupDoor() async {
    await unitFunctionTest(3, 4, 0, 0);
  }

  /// Close the pickup door (front door)
  ///
  /// Physically closes the front door motor after product retrieval.
  /// Not to be confused with [lockDoor] which only engages the electronic lock.
  Future<void> closePickupDoor() async {
    await unitFunctionTest(3, 4, 1, 0);
  }

  /// Lock the electronic door lock
  ///
  /// [lockNumber] - Lock device number (default 0x01)
  Future<LockStatus> lockDoor({int lockNumber = 0x01}) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Lock', 'Locking door $lockNumber...');
    }

    final command = GS805Protocol.electronicLockCommand(lockNumber, LockOperation.lock.code);
    final response = await _manager!.sendCommand(command);

    final lockStatus = LockStatus(
      statusCode: response.statusCode ?? 0,
      rawValue: response.getDataByte(0) ?? 0,
    );

    if (_enableLogging) {
      _logger.info('Lock', 'Lock door result: $lockStatus');
    }

    return lockStatus;
  }

  /// Unlock the electronic door lock
  ///
  /// [lockNumber] - Lock device number (default 0x01)
  Future<LockStatus> unlockDoor({int lockNumber = 0x01}) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Lock', 'Unlocking door $lockNumber...');
    }

    final command = GS805Protocol.electronicLockCommand(lockNumber, LockOperation.unlock.code);
    final response = await _manager!.sendCommand(command);

    final lockStatus = LockStatus(
      statusCode: response.statusCode ?? 0,
      rawValue: response.getDataByte(0) ?? 0,
    );

    if (_enableLogging) {
      _logger.info('Lock', 'Unlock door result: $lockStatus');
    }

    return lockStatus;
  }

  /// Query electronic lock status
  ///
  /// [lockNumber] - Lock device number (default 0x01)
  Future<LockStatus> getLockStatus({int lockNumber = 0x01}) async {
    _ensureConnected();

    final command = GS805Protocol.electronicLockCommand(lockNumber, LockOperation.query.code);
    final response = await _manager!.sendCommand(command);

    return LockStatus(
      statusCode: response.statusCode ?? 0,
      rawValue: response.getDataByte(0) ?? 0,
    );
  }

  /// Trigger water refill (R series)
  Future<void> waterRefill() async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Water', 'Triggering water refill...');
    }

    final command = GS805Protocol.waterRefillCommand();

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Water', 'Water refill command sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Water', 'Failed to trigger water refill',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Query main controller status (R series)
  ///
  /// Returns [ControllerStatus] with detailed machine state flags.
  Future<ControllerStatus> getControllerStatus() async {
    _ensureConnected();

    final command = GS805Protocol.getControllerStatusCommand();
    final response = await _manager!.sendCommand(command);

    // Response DATA: ST_INFO(4bytes) + optional DrinkNo(1)
    // 0x1E response has NO STA byte
    final data = response.data;
    if (data.length < 4) {
      throw GS805Exception('Invalid controller status response: insufficient data (${data.length} bytes)');
    }

    final drinkNo = data.length >= 5 ? data[4] : 0;
    return ControllerStatus(
      rawValue: (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3],
      drinkNumber: drinkNo,
    );
  }

  /// Query drink preparation status (R series)
  ///
  /// Returns [DrinkPreparationStatus] with current drink making progress.
  Future<DrinkPreparationStatus> getDrinkStatus() async {
    _ensureConnected();

    final command = GS805Protocol.getDrinkStatusCommand();
    final response = await _manager!.sendCommand(command);

    // Response DATA: DK_INFO(4bytes)
    // 0x1F response has NO STA byte
    final data = response.data;
    if (data.length < 4) {
      throw GS805Exception('Invalid drink status response: insufficient data (${data.length} bytes)');
    }

    return DrinkPreparationStatus.fromBytes(data);
  }

  /// Query object exception information (R series)
  ///
  /// [objectType] - The object type to query
  /// Returns [ObjectExceptionInfo] with detailed exception data.
  Future<ObjectExceptionInfo> getObjectException(ObjectType objectType) async {
    _ensureConnected();

    final command = GS805Protocol.getObjectExceptionCommand(objectType.code);
    final response = await _manager!.sendCommand(command);

    // Response DATA: STA + ST_INFO(4) + OP_INFO(2) + OBJ_NO(2) + INFO_CODE(2) + AUT_INFO(1)
    final data = response.data;
    if (data.length < 12) {
      throw GS805Exception('Invalid object exception response: insufficient data');
    }

    return ObjectExceptionInfo.fromBytes(data);
  }

  /// Force stop the current drink making process (R series)
  Future<void> forceStopDrinkProcess() async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Control', 'Force stopping drink process...');
    }

    final command = GS805Protocol.forceStopCommand(ForceStopTarget.drinkProcess.code);

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Control', 'Force stop drink process sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Control', 'Failed to force stop drink process',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Force stop the current cup delivery (R series)
  Future<void> forceStopCupDelivery() async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Control', 'Force stopping cup delivery...');
    }

    final command = GS805Protocol.forceStopCommand(ForceStopTarget.cupDelivery.code);

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Control', 'Force stop cup delivery sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Control', 'Failed to force stop cup delivery',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  /// Deliver a cup to the holder (R series)
  ///
  /// [waitTimeSeconds] - Wait time in seconds before timeout (1-255)
  Future<void> cupDelivery(int waitTimeSeconds) async {
    _ensureConnected();

    if (_enableLogging) {
      _logger.info('Cup', 'Starting cup delivery (wait=${waitTimeSeconds}s)...');
    }

    final command = GS805Protocol.cupDeliveryCommand(waitTimeSeconds);

    try {
      if (_enableCommandQueue && _commandQueue != null) {
        await _commandQueue!.enqueue(command);
      } else {
        await _manager!.sendCommand(command);
      }
      if (_enableLogging) {
        _logger.info('Cup', 'Cup delivery command sent successfully');
      }
    } catch (e, stackTrace) {
      if (_enableLogging) {
        _logger.error('Cup', 'Failed to start cup delivery',
            error: e, stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  // ========== Event Streams ==========

  /// Stream of received messages
  Stream<ResponseMessage> get messageStream =>
      _manager?.messageStream ?? const Stream.empty();

  /// Stream of machine events (active reports)
  Stream<MachineEvent> get eventStream {
    return messageStream
        .where((msg) => msg.isActiveReport)
        .map((msg) => MachineEvent.fromCode(msg.getDataByte(0) ?? 0));
  }

  /// Send a raw CommandMessage and return the response.
  /// Use for commands not yet wrapped in dedicated methods.
  Future<ResponseMessage> sendRawCommand(CommandMessage command) async {
    _ensureConnected();
    return await _manager!.sendCommand(command);
  }

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream =>
      _manager?.connectionStateStream ?? const Stream.empty();

  /// Stream of reconnection events
  Stream<ReconnectEvent> get reconnectEventStream =>
      _manager?.reconnectEventStream ?? const Stream.empty();

  // ========== Utility Methods ==========

  /// Ensure the device is connected
  void _ensureConnected() {
    if (!isConnected) {
      throw NotConnectedException('Not connected to device');
    }
  }

  /// Get current buffer size (for debugging)
  int get bufferSize => _manager?.bufferSize ?? 0;

  /// Clear message buffer
  void clearBuffer() {
    _manager?.clearBuffer();
  }

  /// Manually trigger reconnection
  Future<void> reconnect() async {
    await _manager?.reconnect();
  }

  // ========== Logging & Queue ==========

  /// Get logger instance
  GS805Logger get logger => _logger;

  /// Whether logging is enabled
  bool get isLoggingEnabled => _enableLogging;

  /// Get command queue (if enabled)
  CommandQueue? get commandQueue => _commandQueue;

  /// Whether command queue is enabled
  bool get isCommandQueueEnabled => _enableCommandQueue;

  /// Stream of log entries (if logging enabled)
  Stream<LogEntry> get logStream => _logger.stream;

  /// Stream of queue events (if queue enabled)
  Stream<QueueEvent> get queueEventStream =>
      _commandQueue?.eventStream ?? const Stream.empty();

  /// Set log level
  void setLogLevel(LogLevel level) {
    _logger.setLevel(level);
  }

  /// Clear log history
  void clearLogs() {
    _logger.clearHistory();
  }

  /// Export logs
  String exportLogs({
    LogLevel? minLevel,
    String? source,
    DateTime? since,
  }) {
    return _logger.exportLogs(
      minLevel: minLevel,
      source: source,
      since: since,
    );
  }

  /// Pause command queue
  void pauseQueue() {
    _commandQueue?.pause();
  }

  /// Resume command queue
  void resumeQueue() {
    _commandQueue?.resume();
  }

  /// Clear command queue
  void clearQueue() {
    _commandQueue?.clear();
  }

  /// Get pending commands in queue
  List<QueuedCommand> getPendingCommands() {
    return _commandQueue?.getPendingCommands() ?? [];
  }

  /// Dispose all resources
  Future<void> dispose() async {
    if (_enableLogging) {
      _logger.info('GS805Serial', 'Disposing resources...');
    }
    _commandQueue?.dispose();
    await _manager?.dispose();
    if (_enableLogging) {
      _logger.info('GS805Serial', 'Resources disposed');
    }
  }
}

/// Extension for null-safe first element
extension _ListFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
