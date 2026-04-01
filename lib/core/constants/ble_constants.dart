class BleConstants {
  BleConstants._();

  // TODO: Replace with actual Hydrawav3 device UUIDs
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String writeCharacteristicUuid =
      '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String notifyCharacteristicUuid =
      '0000ffe2-0000-1000-8000-00805f9b34fb';

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
  static const int cmdPause = 0;
  static const int cmdResume = 1;
  static const int cmdStop = 2;
}
