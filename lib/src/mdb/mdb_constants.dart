/// MDB Cashless Card Reader Protocol Constants
///
/// Based on MDB-RS232 bridge adapter (Shanghai Wafer, V2021-V9.2).
/// Bridge handles POLL automatically; PC only sends commands and receives events.

/// MDB Device IDs (first byte of received data)
class MdbDeviceId {
  static const int coinAcceptor = 0x08;
  static const int billValidator = 0x30;

  /// Cashless device IDs range 0x10-0x17
  static const int cashless1 = 0x10;

  static bool isCashless(int id) => id >= 0x10 && id <= 0x17;
  static bool isCoin(int id) => id == coinAcceptor;
  static bool isBill(int id) => id == billValidator;
}

/// Cashless command group bytes
class CashlessCommands {
  // --- VMC → Reader (PC sends) ---

  /// Config card reader: 110001000000
  static const int config = 0x11;
  static const int configSubSetup = 0x00;
  static const int configSubMaxMin = 0x01;

  /// Vend command group
  static const int vend = 0x13;
  static const int vendSubRequest = 0x00;
  static const int vendSubCancel = 0x01;
  static const int vendSubSuccess = 0x02;
  static const int vendSubSessionComplete = 0x04;
  static const int vendSubCashSale = 0x05;

  /// Reader control
  static const int readerControl = 0x14;
  static const int readerSubDisable = 0x00;
  static const int readerSubEnable = 0x01;
  static const int readerSubCancel = 0x02;

  /// Revalue
  static const int revalue = 0x15;
  static const int revalueSubRequest = 0x00;

  /// Expansion
  static const int expansion = 0x17;
  static const int expansionSubRequestId = 0x00;
}

/// Cashless reader response codes
class CashlessResponse {
  /// ACK - command received
  static const int ack = 0x00;

  /// Just Reset
  static const int justReset = 0x00;

  /// Reader config data (response to setup)
  static const int configData = 0x01;

  /// Begin Session (valid card detected)
  static const int beginSession = 0x03;

  /// Session Cancel Request
  static const int sessionCancelRequest = 0x04;

  /// Vend Approved
  static const int vendApproved = 0x05;

  /// Vend Denied
  static const int vendDenied = 0x06;

  /// End Session
  static const int endSession = 0x07;

  /// Cancelled
  static const int cancelled = 0x08;

  /// Peripheral ID
  static const int peripheralId = 0x09;

  /// Diagnostics
  static const int diagnostics = 0x0F;

  /// Command Out of Sequence
  static const int outOfSequence = 0x0B;

  /// Revalue Approved
  static const int revalueApproved = 0x0D;

  /// Revalue Denied
  static const int revalueDenied = 0x0E;
}

/// MDB-RS232 communication config
class MdbConfig {
  static const int baudRate = 9600;
  static const int dataBits = 8;
  static const int stopBits = 1;
  static const int parity = 0;

  /// Default command timeout (ms)
  static const int commandTimeout = 200;

  /// Session timeout (ms) - max wait for vend after card detect
  static const int sessionTimeout = 30000;
}
