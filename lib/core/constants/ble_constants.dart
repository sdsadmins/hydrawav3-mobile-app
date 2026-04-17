class BleConstants {
  BleConstants._();

  /// Normalized UUID (lowercase, hex-only, 8-4-4-4-12 if possible).
  /// This lets us match reliably even if the source contains non-hex suffixes.
  static String normalizeUuid(String input) {
    final lower = input.toLowerCase();
    final b = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final c = lower.codeUnitAt(i);
      final isNum = c >= 0x30 && c <= 0x39; // 0-9
      final isHex = c >= 0x61 && c <= 0x66; // a-f
      if (isNum || isHex) b.writeCharCode(c);
    }
    final hex = b.toString();
    if (hex.length == 32) {
      return '${hex.substring(0, 8)}-'
          '${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-'
          '${hex.substring(16, 20)}-'
          '${hex.substring(20)}';
    }
    // Fallback: return hex-only string (no dashes) for best-effort comparisons.
    return hex;
  }

  // ---------------------------------------------------------------------------
  // Preferred GATT layout
  // ---------------------------------------------------------------------------
  // Set these to the EXACT UUIDs printed by the [GATT DUMP] log after your
  // first connection attempt, then hot-restart the app.
  //
  // ⚠️  The placeholder values below are intentionally null — the old fake
  //     UUIDs (12345678-... / abcdef01-...) were NEVER matching the real
  //     device and silently caused the fallback to grab 0x2A05 (Service
  //     Changed — a Bluetooth system characteristic).  That is the bug.
  //
  // ── Nordic UART Service (NUS) — most common for UART-bridge devices ─────
  // Uncomment these three lines once you have confirmed NUS UUIDs in the log:
  //
  // static const String? preferredServiceUuid =
  //     '6e400001-b5a3-f393-e0a9-e50e24dcca9e';     // NUS service
  // static const String? preferredWriteCharacteristicUuid =
  //     '6e400002-b5a3-f393-e0a9-e50e24dcca9e';     // NUS RX (phone → device)
  // static const String? preferredNotifyCharacteristicUuid =
  //     '6e400003-b5a3-f393-e0a9-e50e24dcca9e';     // NUS TX (device → phone)
  //
  // ── Paste your real UUIDs here after reading the [GATT DUMP] log ─────────
  // ℹ️ If your device uses Nordic NUS (most common for UART bridges):
  static const String? preferredServiceUuid =
      '12345678-1234-5678-1234-56789abcdef0';

  static const String? preferredWriteCharacteristicUuid =
      'abcdef01-1234-5678-1234-56789abcdef1';

  // Dedicated JSON payload channel (web: JSON_CHAR_UUID).
  static const String? preferredJsonCharacteristicUuid =
      '12345607-1234-5678-1234-56789abcdef9';

// ⚠️ YOU MUST FIND THIS FROM LOGS
  static const String? preferredNotifyCharacteristicUuid =
      'abcdef03-1234-5678-1234-56789abcdef9'; // guess → verify

  // ❌ OLD FAKE UUIDs (DO NOT USE):
  // '12345678-1234-5678-1234-56789abcdef0'
  // 'abcdef01-1234-5678-1234-56789abcdef1'
  // 'abcdef02-1234-5678-1234-56789abcdef9'

  /// When true, we ONLY accept the exact UUIDs above.
  /// - Scan results are filtered to devices advertising [preferredServiceUuid]
  /// - Connect fails if we can't find the exact service/write/notify UUIDs
  // TEMP: disable strict matching so we can observe actual discovery/fallback
  // behavior and test the correct WRITE/NOTIFY UUID pairing.
  static const bool strictHydraGattProfile = true;

  // UART write tuning.
  static const bool preferWriteWithoutResponse = false;
  static const bool retryWithOppositeWriteModeOnFailure = true;

  // ---------------------------------------------------------------------------
  // Bluetooth system-characteristic blocklist
  // ---------------------------------------------------------------------------
  // These are well-known Bluetooth SIG «assigned numbers» that belong to the
  // Generic Access / Generic Attribute services.  They must never be used as
  // write or notify channels for application data.
  //
  // Short UUIDs are stored here without dashes so they can be compared with
  // the normalised (hex-only) form produced by _findCharacteristics.
  static const Set<String> systemCharacteristicUuids = {
    '00002a00', // Device Name            (Generic Access)
    '00002a01', // Appearance             (Generic Access)
    '00002a02', // Peripheral Privacy Flag
    '00002a03', // Reconnection Address
    '00002a04', // Peripheral Preferred Connection Parameters
    '00002a05', // ⚠️ Service Changed      (Generic Attribute) — the 2A05 bug
    '00002a06', // Alert Level
    '00002a07', // Tx Power Level
    '2a00', // Short-form aliases (some stacks omit leading zeros)
    '2a01',
    '2a02',
    '2a03',
    '2a04',
    '2a05', // ⚠️ Service Changed — short form
    '2a06',
    '2a07',
  };

  /// Returns true when [uuid] (already normalised / hex-only, lower-case)
  /// is a Bluetooth SIG system characteristic that must be skipped during
  /// fallback discovery.
  static bool isSystemCharacteristic(String normalisedUuid) {
    // Strip all dashes for the comparison.
    final bare = normalisedUuid.replaceAll('-', '');
    // Check both the raw form and the zero-padded 16-bit form.
    return systemCharacteristicUuids.contains(bare) ||
        systemCharacteristicUuids.contains(
          bare.length > 8 ? bare.substring(bare.length - 8) : bare,
        );
  }

  /// Provisioned firmware / cloud id for JSON **`deviceId`**. The BLE address
  /// belongs in **`mac`** only. Sending the MAC as `deviceId` often makes the
  /// bridge ACK the write while the appliance ignores the session.
  // Firmware/cloud "device id" used as the MAP KEY in the session payload.
  // Web app sends it with base64 padding ('==').
  static const String firmwareSessionDeviceId = '64FdReiBHN0EKPVxwn8myQ==';

  /// RS232/UART bridges often expect CRLF after each JSON line. If the device
  /// mis-parses frames, try `'\n'` instead.
  static const String sessionJsonLineSuffix = '\n';

  /// JSON `deviceId` sent to firmware (constant). [bleTransportId] / GATT args
  /// are ignored but kept for call-site clarity.
  static String jsonDeviceIdForSession({
    required String bleTransportId,
    String? discoveredWriteCharacteristicUuid,
  }) =>
      firmwareSessionDeviceId;

  /// If true, the session "Start" will only send `{"playCmd":1}` and return.
  /// This is useful for isolating "turn on" from the full protocol payload.
  // Disable playCmd-only mode so starting a protocol sends the full session
  // payload (including `"led": 1`) for brute-testing firmware behavior.
  static const bool startSendsOnlyPlayCmd = false;

  /// Some firmwares require a single binary "control byte" to wake/enable
  /// the bridge (web test: writeValue(Uint8Array([0x01]))).
  ///
  /// We use this only for the built-in "Light On (Debug)" protocol so it
  /// doesn't affect normal sessions.
  static const int lightOnControlByte = 0x01;

  // Device name prefix for filtering scan results
  static const String deviceNamePrefix = 'HydraWav';

  // Timeouts
  static const Duration scanTimeout = Duration(seconds: 10);
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int maxReconnectAttempts = 5;

  // MTU
  static const int requestedMtu = 512;

  // Play commands
  static const int cmdPause =
      2; // 🔥 FIX: Was 0, should be 0x02 to match device firmware
  static const int cmdResume = 1; // ✅ Correct (0x01)
  static const int cmdStop = 0; // 🔥 FIX: Was 2, device expects 0x00 for stop
}
