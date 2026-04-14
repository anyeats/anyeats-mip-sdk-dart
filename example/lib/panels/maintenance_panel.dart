part of '../main.dart';

/// Maintenance tab (door open/close, cup drop, clean, inspection)
extension MaintenancePanelBuilder on _CoffeeMachineScreenState {

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
}
