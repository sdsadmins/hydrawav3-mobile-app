import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/features/session/domain/active_session_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/active_sessions_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('getBusyDevices only returns devices whose per-device status is live',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = ActiveSessionsNotifier(prefs);

    await notifier.createSession(
      sessionId: 'session-1',
      protocolId: 'protocol-1',
      protocolName: 'Protocol 1',
      deviceIds: const ['device-a', 'device-b'],
      transport: 'ble',
    );

    await notifier.updateDeviceStatuses(
      'session-1',
      const {
        'device-a': SessionStatus.running,
        'device-b': SessionStatus.stopped,
      },
    );

    expect(notifier.getBusyDevices(), contains('device-a'));
    expect(notifier.getBusyDevices(), isNot(contains('device-b')));
  });
}
