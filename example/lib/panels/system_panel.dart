part of '../main.dart';

/// System tab (app update)
extension SystemPanelBuilder on _CoffeeMachineScreenState {

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _systemLog = 'Checking for update...';
    });
    try {
      const serverUrl = _CoffeeMachineScreenState._updateServerUrl;
      final result = await _uartChannel.invokeMethod('httpGet', {
        'url': '$serverUrl/'
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
          _apkDownloadUrl = href.startsWith('http') ? href : '$serverUrl/$href';
          setState(() {
            _updateAvailable = true;
            _systemLog = 'Update available: $href';
          });
        } else if (body.contains('app-debug.apk')) {
          _apkDownloadUrl = '$serverUrl/app-debug.apk';
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
                Text('Server: ${_CoffeeMachineScreenState._updateServerUrl}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
}
