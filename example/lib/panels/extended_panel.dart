part of '../main.dart';

/// Extended tab (unit function test, water refill, controller/drink status, force stop)
extension ExtendedPanelBuilder on _CoffeeMachineScreenState {

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
}
