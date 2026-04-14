part of '../main.dart';

/// Debug tab (shell commands, presets, port info, kill process)
extension DebugPanelBuilder on _CoffeeMachineScreenState {

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
                    _shellPreset('su 0 sh -c "timeout 15 cat /dev/ttyS9 > /data/local/tmp/ttyS9.bin &"'),
                    _shellPreset('su 0 xxd /data/local/tmp/ttyS9.bin'),
                    _shellPreset('su 0 sh -c "timeout 30 cat /dev/ttyS9 > /data/local/tmp/ttyS9.bin &"'),
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
}
