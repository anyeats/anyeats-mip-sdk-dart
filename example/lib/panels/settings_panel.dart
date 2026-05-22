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
          title: const Text('[All] Machine Status (0x0B)'),
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
          title: const Text('[All] Error Code (0x0C)'),
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
          title: const Text('[All] Error Info (상세, 0x0C)'),
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
          title: const Text('[3/R] Controller Status (0x1E)'),
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
          title: const Text('[3/R] Drink Status (0x1F)'),
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
          title: const Text('[All] Balance (0x0F)'),
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
          title: const Text('[All] Set Hot Temp (65/60, 0x04)'),
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
          title: const Text('[All] Set Cold Temp (10/5, 0x05)'),
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

        // --- Raw Diagnostic ---
        const Divider(height: 24, thickness: 2),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Raw Diagnostic',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 4, left: 8, right: 8),
          child: Text(
            'SDK 정상 파싱과 무관하게 1.5초간 raw bytes를 캡처해 hex 출력.\n'
            'GS801 / GS805 비교로 응답 포맷 차이 확인.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.bug_report, color: Colors.deepOrange),
          title: const Text('Diag 0x0B (MachineStatus)'),
          subtitle: const Text('명령: AA 55 02 0B 12'),
          trailing: ElevatedButton(
            onPressed: () => _runRawDiagnostic(
              label: '0x0B MachineStatus',
              command: GS805Protocol.getMachineStatusCommand(),
            ),
            child: const Text('Capture'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.bug_report, color: Colors.deepOrange),
          title: const Text('Diag 0x1F (DrinkStatus)'),
          subtitle: const Text('명령: AA 55 03 1F 20 47'),
          trailing: ElevatedButton(
            onPressed: () => _runRawDiagnostic(
              label: '0x1F DrinkStatus',
              command: GS805Protocol.getDrinkStatusCommand(),
            ),
            child: const Text('Capture'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.bug_report, color: Colors.green),
          title: const Text('Diag 0x1E (ControllerStatus, 정상 비교용)'),
          subtitle: const Text('명령: AA 55 03 1E 1F 45'),
          trailing: ElevatedButton(
            onPressed: () => _runRawDiagnostic(
              label: '0x1E ControllerStatus',
              command: GS805Protocol.getControllerStatusCommand(),
            ),
            child: const Text('Capture'),
          ),
        ),
        const Divider(),
        ListTile(
          dense: true,
          leading: const Icon(Icons.playlist_play, color: Colors.deepOrange),
          title: const Text('Diag ALL (0x0B → 0x1F → 0x1E)'),
          subtitle: const Text('세 명령 순차 캡처'),
          trailing: ElevatedButton(
            onPressed: () async {
              await _runRawDiagnostic(
                label: '0x0B MachineStatus',
                command: GS805Protocol.getMachineStatusCommand(),
              );
              await _runRawDiagnostic(
                label: '0x1F DrinkStatus',
                command: GS805Protocol.getDrinkStatusCommand(),
              );
              await _runRawDiagnostic(
                label: '0x1E ControllerStatus',
                command: GS805Protocol.getControllerStatusCommand(),
              );
              _addEventLog('=== Diag ALL 완료 ===');
            },
            child: const Text('Run All'),
          ),
        ),
      ],
    );
  }

  Future<void> _runRawDiagnostic({
    required String label,
    required CommandMessage command,
  }) async {
    try {
      _addEventLog('--- $label 캡처 시작 ---');
      final tx = command.toBytes();
      _addEventLog('  TX: ${_hex(tx)}');
      final stopwatch = Stopwatch()..start();
      final rx = await _gs805.diagnoseRaw(command);
      stopwatch.stop();
      if (rx.isEmpty) {
        _addEventLog('  RX: (no bytes, ${stopwatch.elapsedMilliseconds}ms)');
      } else {
        _addEventLog('  RX (${rx.length}B, ${stopwatch.elapsedMilliseconds}ms): ${_hex(rx)}');
      }
    } catch (e) {
      _addEventLog('  ERROR: $e');
    }
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}
