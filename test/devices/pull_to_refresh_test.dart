// Pull-to-refresh re-fetches: Device Center re-runs wifiDevicesByOrgProvider
// (in the list, empty and error states alike) and the Protocol Library
// re-runs protocolListProvider and goalTagListProvider.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/error/exceptions.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_connection_provider.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_scan_provider.dart';
import 'package:hydrawav3/features/ble/services/ble_scanner.dart'
    show bleScannerProvider;
import 'package:hydrawav3/features/devices/domain/device_model.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/devices/presentation/screens/device_list_screen.dart'
    show pairedDevicesProvider;
import 'package:hydrawav3/features/devices/presentation/screens/device_register_screen.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/protocols/presentation/screens/protocol_list_screen.dart';
import 'package:hydrawav3/features/session/presentation/providers/live_sessions_provider.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/qa_snap.dart';

const _unit = DeviceInfo(
  id: 'd1',
  name: 'Hydra-Unit 1',
  macAddress: '48:CA:43:B0:02:B1',
);

const _protocol = Protocol(
  id: 'calm',
  templateName: 'Deep Relaxation',
  apiTotalDurationSeconds: 1200,
);

/// The RefreshIndicator pull: drag ITS scrollable (not, say, the search
/// field's) well past the trigger distance, let it snap back and run
/// onRefresh.
Future<void> pullToRefresh(WidgetTester tester) async {
  final list = find
      .descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.fling(list, const Offset(0, 320), 1200);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpFrames(tester, frames: 6, step: const Duration(milliseconds: 250));
}

void main() {
  group('Device Center', () {
    Future<void> pumpCenter(
      WidgetTester tester,
      Future<List<DeviceInfo>> Function() fetch,
    ) async {
      await pumpApp(
        tester,
        const DeviceRegisterScreen(),
        overrides: [
          authStateProvider
              .overrideWith((ref) => FakeAuth(orgName: 'Gulf Coast Tarpons')),
          liveSessionsProvider.overrideWith((ref) => FakeLiveSessions()),
          wifiDevicesByOrgProvider.overrideWith((ref) => fetch()),
          pairedDevicesProvider.overrideWith((ref) => Stream.value(const [])),
          bleConnectionStatesProvider
              .overrideWith((ref) => Stream.value(const {})),
          bleScannerProvider.overrideWithValue(FakeScanner()),
          startScanProvider.overrideWithValue(() async {}),
        ],
      );
      await pumpFrames(tester);
    }

    qaTestWidgets('[FIX-19] pull on the device list re-fetches the org devices',
        (tester) async {
      var fetches = 0;
      await pumpCenter(tester, () async {
        fetches++;
        return [_unit];
      });
      expect(find.text('Hydra-Unit 1'), findsOneWidget);
      expect(fetches, 1);

      await pullToRefresh(tester);
      expect(fetches, 2);
      expect(find.text('Hydra-Unit 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    qaTestWidgets('[FIX-19] pull in the empty state re-fetches too',
        (tester) async {
      var fetches = 0;
      await pumpCenter(tester, () async {
        fetches++;
        return const [];
      });
      expect(find.text('Hydra-Unit 1'), findsNothing);
      expect(fetches, 1);

      await pullToRefresh(tester);
      expect(fetches, 2);
      expect(tester.takeException(), isNull);
    });

    qaTestWidgets('[FIX-19] pull in the error state re-fetches and recovers',
        (tester) async {
      var fetches = 0;
      await pumpCenter(tester, () async {
        fetches++;
        if (fetches == 1) throw const ServerException('Failed to fetch devices');
        return [_unit];
      });
      expect(find.text('Hydra-Unit 1'), findsNothing);
      expect(fetches, 1);

      await pullToRefresh(tester);
      expect(fetches, 2);
      expect(find.text('Hydra-Unit 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Protocol Library', () {
    qaTestWidgets(
        '[FIX-19] pull re-fetches both the protocols and the goal tags',
        (tester) async {
      var protocolFetches = 0;
      var goalFetches = 0;
      await pumpApp(
        tester,
        const ProtocolListScreen(),
        overrides: [
          protocolListProvider.overrideWith((ref) async {
            protocolFetches++;
            return const [_protocol];
          }),
          goalTagListProvider.overrideWith((ref) async {
            goalFetches++;
            return const [GoalTagOption(id: 'g1', name: 'Calm')];
          }),
          currentPlanProvider.overrideWith((ref) async => null),
        ],
      );
      await pumpFrames(tester);
      expect(find.text('Deep Relaxation'), findsOneWidget);
      expect(protocolFetches, 1);
      expect(goalFetches, 1);

      await pullToRefresh(tester);
      expect(protocolFetches, 2);
      expect(goalFetches, 2);
      expect(find.text('Deep Relaxation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
