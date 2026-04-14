part of '../main.dart';

/// Settings tab (status queries, temperature)
extension SettingsPanelBuilder on _CoffeeMachineScreenState {

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
}
