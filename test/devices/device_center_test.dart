import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/core/storage/local_db.dart';
import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/ble/domain/ble_device_model.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_connection_provider.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_scan_provider.dart';
import 'package:hydrawav3/features/ble/services/ble_scanner.dart' show bleScannerProvider;
import 'package:hydrawav3/features/devices/domain/device_model.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/devices/presentation/screens/device_list_screen.dart'
    show pairedDevicesProvider;
import 'package:hydrawav3/features/devices/presentation/screens/device_register_screen.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/device_center_widgets.dart';
import 'package:hydrawav3/features/session/presentation/providers/live_sessions_provider.dart';

import '../helpers/fakes.dart';

const _units = [
  DeviceInfo(
      id: 'd1', name: 'Hydra-Unit 1', macAddress: '48:CA:43:B0:02:B1',
      firmware: '1.50'),
  DeviceInfo(id: 'd2', name: 'Hydra-Unit 2', macAddress: '48:CA:43:B0:02:C4'),
];

/// Device Center in the v6 layout on phone and tablet: the connected unit
/// reads Ready with its signal and firmware, the other Not connected, and a
/// tap opens the detail page with every existing action on it.
void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider
            .overrideWith((ref) => FakeAuth(orgName: 'Gulf Coast Tarpons')),
        liveSessionsProvider.overrideWith((ref) => FakeLiveSessions()),
        wifiDevicesByOrgProvider.overrideWith((ref) async => _units),
        pairedDevicesProvider.overrideWith((ref) => Stream.value([
              PairedDevice(
                id: 'ble-1',
                macAddress: '48:CA:43:B0:02:B1',
                name: 'Hydra-Unit 1',
                autoReconnect: true,
                createdAt: DateTime(2026),
              ),
            ])),
        bleConnectionStatesProvider.overrideWith((ref) =>
            Stream.value({'ble-1': BleConnectionStatus.connected})),
        unitRssiProvider.overrideWith((ref, id) async => -52),
        // No Bluetooth on the test machine: scan-on-open is a no-op.
        bleScannerProvider.overrideWithValue(FakeScanner()),
        startScanProvider.overrideWithValue(() async {}),
      ],
      child: const MaterialApp(home: DeviceRegisterScreen()),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  for (final size in [const Size(320, 800), const Size(834, 1112)]) {
    final tag = size.width > 600 ? 'tablet' : 'phone';

    testWidgets('list shows status, signal and firmware ($tag)',
        (tester) async {
      await pump(tester, size);
      expect(find.text('Device Center'), findsOneWidget);
      expect(find.text('1 of 2 connected · Gulf Coast Tarpons'), findsOneWidget);
      expect(find.text('Auto scan (BLE)'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Not connected'), findsNWidgets(2)); // line + pill
      expect(find.text('fw 1.50'), findsOneWidget);
      expect(find.byType(SignalBars), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('Tap a unit for rename, WiFi setup, and status.'),
          findsOneWidget);
      // The old per-card action row is gone from the list.
      expect(find.text('EDIT WIFI'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a unit opens its detail page with every action ($tag)',
        (tester) async {
      await pump(tester, size);
      await tester.tap(find.text('Hydra-Unit 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final t in [
        'Unit name',
        'Rename — sent over Bluetooth',
        'Connection',
        'Strong signal (-52 dBm)',
        '1.50',
        '48:CA:43:B0:02:B1',
        '1 Sun ☀ + 1 Moon ☾',
        'Update WiFi network',
        'Locate',
        'Device report',
        'Device lease',
        'Start hand-off',
        'Unregister unit',
      ]) {
        await tester.ensureVisible(find.text(t).first);
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byIcon(Icons.chevron_left_rounded).last);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_left_rounded).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Device Center'), findsOneWidget);
    });
  }

  testWidgets('an unconnected unit hides signal and missing firmware',
      (tester) async {
    await pump(tester, const Size(390, 900));
    await tester.tap(find.text('Hydra-Unit 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Signal'), findsNothing);
    expect(find.text('Firmware'), findsNothing);
    expect(find.text('MAC ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
