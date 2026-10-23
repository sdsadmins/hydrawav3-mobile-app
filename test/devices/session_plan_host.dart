// Pumps the REAL Session Plan screen (DeviceListScreen) with every network,
// Bluetooth and audio dependency stubbed, in WiFi mode with one selected unit.
//
// Shared by the plan-gating tests (advanced_upgrade_bubble_test.dart,
// plan_device_limit_test.dart). Not a test file itself.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/auth/presentation/providers/auth_provider.dart';
import 'package:hydrawav3/features/ble/presentation/providers/ble_scan_provider.dart';
import 'package:hydrawav3/features/ble/services/ble_scanner.dart'
    show bleScannerProvider;
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/devices/domain/device_model.dart';
import 'package:hydrawav3/features/devices/presentation/providers/players_provider.dart';
import 'package:hydrawav3/features/devices/presentation/providers/wifi_devices_provider.dart';
import 'package:hydrawav3/features/devices/presentation/screens/device_list_screen.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/musics/services/session_music_controller.dart';
import 'package:hydrawav3/features/payments/presentation/providers/token_balance_provider.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';
import 'package:hydrawav3/features/session/domain/session_model.dart';
import 'package:hydrawav3/features/session/presentation/providers/ble_run_state_provider.dart';
import 'package:hydrawav3/features/session/presentation/providers/busy_devices_provider.dart';
import 'package:hydrawav3/features/session/presentation/providers/live_sessions_provider.dart';
import 'package:hydrawav3/features/session/presentation/providers/session_target_provider.dart';
import 'package:hydrawav3/features/session_coach/data/session_coach_repository.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// The one WiFi unit on the plan.
const kPlanUnit = DeviceInfo(
  id: 'd1',
  name: 'Hydra-Unit 1',
  macAddress: '48:CA:43:B0:02:B1',
);

/// A normal (non-Plus) protocol the screen seeds onto the unit by default.
const kPlanProtocol = Protocol(
  id: 'p1',
  templateName: 'Deep-Tension Recovery',
  description: 'Default plan protocol',
  apiTotalDurationSeconds: 540,
);

const kPlanProtocolOption = ProtocolSelectionOption(
  id: 'p1',
  templateName: 'Deep-Tension Recovery',
  description: 'Default plan protocol',
  goalTagName: 'Recovery',
  durationSeconds: 540,
);

class _WifiTarget extends SessionTargetNotifier {
  _WifiTarget(List<String> macs) {
    state = SessionTargetState(
      transport: SessionTransport.wifi,
      deviceIds: macs,
    );
  }
}

class _FakeMusic extends StateNotifier<SessionMusicState>
    implements SessionMusicController {
  _FakeMusic() : super(const SessionMusicState());

  @override
  Future<void> stopPreview() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRunState extends StateNotifier<Set<String>>
    implements BleRunStateMonitor {
  _FakeRunState() : super(const {});

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The screen's post-frame hook calls `start(orgId)` on both feeds; the
/// noSuchMethod fakes would hand back null where a `Future<void>` is expected.
class _QuietTokens extends FakeTokens {
  @override
  Future<void> start(String orgId) async {}
}

class _QuietLiveSessions extends FakeLiveSessions {
  @override
  Future<void> start(String orgId) async {}
}

class _FakeRecents extends StateNotifier<List<String>>
    implements RecentProtocolIdsController {
  _FakeRecents(super.ids);

  @override
  Future<void> recordUsed(String protocolId) async {}
}

/// Callers must `setUpAll(loadAppFonts)`: with the test font's square glyphs
/// the "Add a new unit · Device Center" row overflows at phone width, which
/// a device (Roboto) never does.
///
/// Pumps the Session Plan with [protocols] as the selectable catalogue (the
/// screen seeds the first/default one onto the unit; an empty list leaves the
/// unit without a protocol), the plan's concurrent-device [deviceLimit]
/// (null = unknown, 0 = unlimited) and [liveDevices] already running
/// org-wide. [extraOverrides] win over the defaults.
Future<void> pumpSessionPlan(
  WidgetTester tester, {
  required List<ProtocolSelectionOption> protocols,
  int? deviceLimit,
  int liveDevices = 0,
  List<Override> extraOverrides = const [],
  Size size = const Size(390, 1200),
}) async {
  await pumpApp(
    tester,
    const DeviceListScreen(),
    size: size,
    overrides: [
      authStateProvider
          .overrideWith((ref) => FakeAuth(orgName: 'Gulf Coast Tarpons')),
      liveSessionsProvider.overrideWith((ref) => _QuietLiveSessions()),
      tokenBalanceProvider.overrideWith((ref) => _QuietTokens()),
      wifiDevicesByOrgProvider.overrideWith((ref) async => [kPlanUnit]),
      sessionTargetProvider
          .overrideWith((ref) => _WifiTarget([kPlanUnit.macAddress])),
      sessionClientModeProvider.overrideWith((ref) => ClientMode.guest),
      pairedDevicesProvider.overrideWith((ref) => Stream.value(const [])),
      bleScanResultsProvider.overrideWith((ref) => const Stream.empty()),
      isScanningProvider.overrideWithValue(false),
      bleScannerProvider.overrideWithValue(FakeScanner()),
      startScanProvider.overrideWithValue(() async {}),
      bleRunStateMonitorProvider.overrideWith((ref) => _FakeRunState()),
      sessionMusicControllerProvider.overrideWith((ref) => _FakeMusic()),
      protocolSelectionOptionsProvider
          .overrideWith((ref, goal) async => protocols),
      protocolDetailProvider.overrideWith((ref, id) async => kPlanProtocol),
      goalTagListProvider.overrideWith((ref) async => const []),
      recentProtocolIdsProvider.overrideWith(
          (ref) => _FakeRecents([for (final p in protocols) p.id])),
      clientListProvider.overrideWith((ref) async => const []),
      allSessionsProvider.overrideWith((ref) async => const []),
      orgSportsProvider.overrideWith((ref) async => const []),
      coachBodyPartsProvider.overrideWith((ref) async => const []),
      planDeviceLimitProvider.overrideWith((ref) async => deviceLimit),
      liveDeviceCountProvider.overrideWithValue(liveDevices),
      ...extraOverrides,
    ],
  );
  await settlePlan(tester);
}

/// Lets the FutureProviders resolve and the entrance animations finish.
Future<void> settlePlan(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
