part of '../main.dart';

/// Payment tab (MDB Cashless)
extension PaymentPanelBuilder on _CoffeeMachineScreenState {

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
                      onPressed: _mdbConnected ? () async {
                        try {
                          _addEventLog('[MDB] Setup V2 (Level 2/3 + Expansion)...');
                          await _mdbCashless.setupV2();
                          _addEventLog('[MDB] Setup V2 complete');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[100]),
                      child: const Text('Setup V2'),
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
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          await _mdbCashless.sessionComplete();
                          _addEventLog('[MDB] Session Complete sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[100]),
                      child: const Text('Session Complete'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          await _mdbCashless.cancel();
                          _addEventLog('[MDB] Cancel sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          _addEventLog('[MDB] 1. Reset (0x10)...');
                          await _mdbCashless.sendRawHex([0x10]);
                          _addEventLog('[MDB] Reset sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
                      child: const Text('1.Reset'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          _addEventLog('[MDB] 2. Config (Setup)...');
                          await _mdbCashless.setup();
                          _addEventLog('[MDB] Config sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      child: const Text('2.Config'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          _addEventLog('[MDB] 3. Enable...');
                          await _mdbCashless.enable();
                          _addEventLog('[MDB] Enable sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100]),
                      child: const Text('3.Enable'),
                    ),
                    ElevatedButton(
                      onPressed: _mdbConnected ? () async {
                        try {
                          _addEventLog('[MDB] Set Price (1101FFFF0000)...');
                          await _mdbCashless.sendRawHex([0x11, 0x01, 0xFF, 0xFF, 0x00, 0x00]);
                          _addEventLog('[MDB] Set Price sent');
                        } catch (e) { _showSnackBar('$e', Colors.red); }
                      } : null,
                      child: const Text('Set Price'),
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
                      onPressed: _mdbConnected ? _mdbRequestVend : null,
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
}
