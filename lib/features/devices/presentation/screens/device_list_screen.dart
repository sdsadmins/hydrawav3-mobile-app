import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/extensions.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/auto_connect_provider.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../ble/presentation/providers/ble_scan_provider.dart';
import '../../../ble/services/ble_connector.dart';
import '../../../ble/services/ble_scanner.dart';
import '../../../devices/data/device_repository.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../home/presentation/providers/hub_prefs_provider.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../widgets/plan_sheet.dart';
import '../widgets/device_center_widgets.dart'
    show SignalBars, signalOf, unitRssiProvider;
import '../../../session_coach/presentation/widgets/session_coach_card.dart';
import '../widgets/session_plan_widgets.dart';
import '../../../musics/services/session_music_controller.dart';
import '../widgets/session_music_card.dart' show showSessionMusicPicker;
import 'package:flutter_svg/flutter_svg.dart';
import '../../../devices/presentation/widgets/players_section.dart';
import '../../../devices/presentation/widgets/find_pad_placements_card.dart';
import '../../../devices/presentation/widgets/session_music_card.dart';
import '../../../devices/presentation/widgets/scan_units_section.dart';
import '../../../devices/presentation/widgets/ref_palette.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../intake/presentation/providers/guided_assessment_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/domain/active_session_model.dart' as live;
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/busy_devices_provider.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/presentation/providers/ble_run_state_provider.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import '../../../session/presentation/widgets/live_sessions_banner.dart';
import '../../../session/services/protocol_plus_controller.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../payments/presentation/widgets/token_balance_badge.dart';

final pairedDevicesProvider = StreamProvider((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

// autoConnectEnabledProvider + bleConnectingIdsProvider now live in
// ble/presentation/providers/auto_connect_provider.dart (shared app-wide with
// the AutoConnectManager).
final _hydrawaveOnlyProvider = StateProvider<bool>((ref) => true);

/// The protocol a practitioner explicitly picked per device (deviceId →
/// protocolId). Kept in a provider — NOT screen State — because the tab shell
/// disposes and rebuilds the Devices screen on navigation, which would
/// otherwise drop the choice and re-seed the default. Seeding reads this so a
/// device restores its chosen protocol; only an explicit pick writes to it.
final selectedProtocolIdByDeviceProvider =
    StateProvider<Map<String, String>>((ref) => const {});

/// The per-device Advanced Settings a unit starts with for [protocol] — the
/// Session tab's defaults, shared with the Hub's Quick Start so a one-tap
/// start runs exactly what the Session tab would have.
AdvancedSettings sessionDefaultsForProtocol(Protocol protocol) {
  // hotPwmByCycle/coldPwmByCycle left empty deliberately — the protocol's
  // own per-cycle hotPwm/coldPwm values are used unmodified until the user
  // actually adjusts the pooled percentage slider.
  return AdvancedSettings(
    lights: true,
    vibrationMode: 'Sweep',
    vibrationSweepMin: protocol.vibmin,
    vibrationSweepMax: protocol.vibmax,
    vibrationSingleHz: 100,
    cycle1Initiation: protocol.cycle1,
    cycle5Completion: protocol.cycle5,
    hotDrop: protocol.hotdrop,
    coldDrop: protocol.colddrop,
    vibMin: protocol.vibmin,
    vibMax: protocol.vibmax,
    startDelay: 0,
    flipSettings: false,
  );
}

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  /// Protocol selected by default for a device. Matched by ID first (stable —
  /// the name can change), with the template name as a cross-environment
  /// fallback. This is the "1. Deep-Tension Recovery" Protocol Plus.
  static const String _defaultProtocolId = '6a203088c1fa1f5ac0d4f333';
  static const String _defaultProtocolTemplateName = 'Deep-Tension Recovery';

  final Map<String, String> _protocolIdByDeviceId = {};
  final Map<String, Protocol> _selectedProtocolByDeviceId = {};
  final Map<String, AdvancedSettings> _settingsByDeviceId = {};
  final Set<String> _runDeviceIds = <String>{};
  final Set<String> _excludedDeviceIds = <String>{};
  final Map<String, bool> _showAdvancedByDeviceId = {};

  // The copper Session-Plan design now replaces the legacy device manager for
  // ALL account types (the only per-account difference is Players vs Clients,
  // handled inside PlayersSection). Kept behind flags for easy rollback.
  final bool _showNewDesign = true;
  final bool _showLegacyDeviceManager = false;
  String? _delayedDeviceId;
  bool _starting = false;
  bool _didInitializeAutoScan = false;
  bool _isSeedingDefaultProtocol = false;

  /// Held so [dispose] can stop a music preview (ref isn't usable there).
  late final SessionMusicController _music =
      ref.read(sessionMusicControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _music; // resolve while ref is usable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAutoScan();
      // Ensure the token balance feed is running for the header chip.
      final auth = ref.read(authStateProvider);
      final orgId = auth.selectedOrgId ?? auth.user?.organizationId;
      if (orgId != null && orgId.isNotEmpty) {
        ref.read(tokenBalanceProvider.notifier).start(orgId);
        // Keep the org-wide live feed running so devices already in use
        // elsewhere (web / another phone) show as "In use" here. Idempotent.
        ref.read(liveSessionsProvider.notifier).start(orgId);
      }
    });
  }

  @override
  void dispose() {
    // Left Setup (another tab, or back) without starting: stop the music
    // preview. Starting a session opens it on top of Setup, so the music
    // carries on into the session.
    unawaited(_music.stopPreview());
    super.dispose();
  }

  void _initializeAutoScan() {
    if (_didInitializeAutoScan || !mounted) return;
    _didInitializeAutoScan = true;

    final scanner = ref.read(bleScannerProvider);
    scanner.initializeAutoScan();

    final transport = ref.read(sessionTargetProvider).transport;
    final hasActiveConnectionAttempt =
        ref.read(bleConnectingIdsProvider).isNotEmpty;
    if (transport == SessionTransport.ble &&
        !scanner.isScanning &&
        !hasActiveConnectionAttempt) {
      Future.microtask(() => ref.read(startScanProvider)());
    }

    // Auto-connect is now handled app-wide by AutoConnectManager (so it also
    // works while on the Session screen and reconnects ALL matching devices
    // concurrently). This screen only toggles `autoConnectEnabledProvider` and
    // offers the manual "Connect all" button.
  }

  AdvancedSettings _advancedDefaultsFromProtocol(Protocol protocol) =>
      sessionDefaultsForProtocol(protocol);

  void _syncVisibleSessionDevices(Iterable<String> deviceIds) {
    final visibleSet = deviceIds.toSet();
    final pendingAdds = visibleSet
        .where((id) =>
            !_runDeviceIds.contains(id) && !_excludedDeviceIds.contains(id))
        .toList();
    final shouldClearDelayedDevice = _delayedDeviceId != null &&
        !visibleSet.contains(_delayedDeviceId) &&
        !_runDeviceIds.contains(_delayedDeviceId);

    if (pendingAdds.isEmpty && !shouldClearDelayedDevice) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _runDeviceIds.addAll(pendingAdds);
        if (shouldClearDelayedDevice) {
          _delayedDeviceId = null;
        }
      });
    });
  }

  void _setDeviceIncluded(String deviceId, bool included) {
    setState(() {
      if (included) {
        _runDeviceIds.add(deviceId);
        _excludedDeviceIds.remove(deviceId);
      } else {
        _runDeviceIds.remove(deviceId);
        _excludedDeviceIds.add(deviceId);
        if (_delayedDeviceId == deviceId) {
          _delayedDeviceId = null;
        }
      }
    });
  }

  void _clearDeviceSessionState(String deviceId) {
    _runDeviceIds.remove(deviceId);
    _excludedDeviceIds.remove(deviceId);
    _protocolIdByDeviceId.remove(deviceId);
    _selectedProtocolByDeviceId.remove(deviceId);
    _settingsByDeviceId.remove(deviceId);
    _showAdvancedByDeviceId.remove(deviceId);
    if (_delayedDeviceId == deviceId) {
      _delayedDeviceId = null;
    }
  }

  /// "Stop pending" tap target: find the local session that owns [deviceId]
  /// (its engine went terminal but the backend stop hasn't been confirmed —
  /// see `pendingBackendStopDeviceIdsProvider`) and open it against its own
  /// engine, where Stop / Stop All already work. No stop logic here — this
  /// screen just surfaces the problem and hands off to the session screen.
  void _openPendingStopSession(String deviceId) {
    for (final session in ref.read(activeSessionsProvider)) {
      if (session.deviceIds.contains(deviceId)) {
        openOwnLocalSession(context, session);
        return;
      }
    }
  }

  /// "In use" tap target. Two cases, told apart by whether a real session
  /// exists for this device:
  ///
  ///  - A backend/local session genuinely owns it (running or overrun) → jump
  ///    straight to it, own engine if we have one, remote view otherwise —
  ///    the user can Stop / Stop All from there regardless of whether the run
  ///    would ever end on its own.
  ///  - Nothing owns it — the lock is coming purely from this device's own
  ///    BLE telemetry (`bleRunStateMonitorProvider`), e.g. firmware stuck
  ///    reporting `rs: Play` after an abnormal stop, with no session to open
  ///    at all. Offer to force it back to available instead.
  void _handleInUseTap(String deviceId) {
    final variants = macAddressVariants(deviceId).toSet();
    bool matchesAny(Iterable<String> ids) =>
        ids.any((id) => variants.contains(id.trim().toUpperCase()));

    for (final session in ref.read(activeSessionsProvider)) {
      if (matchesAny(session.deviceIds)) {
        openOwnLocalSession(context, session);
        return;
      }
    }
    for (final session in ref.read(liveSessionsProvider)) {
      final ids = session.liveDevices.isNotEmpty
          ? session.liveDevices.map((d) => d.deviceId)
          : session.deviceIds;
      if (matchesAny(ids)) {
        openLiveSession(context, ref, session);
        return;
      }
    }
    unawaited(_offerForceRelease(deviceId));
  }

  Future<void> _offerForceRelease(String deviceId) async {
    final p = RefPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.card,
        title: const Text('No session found'),
        content: const Text(
          "This device isn't linked to any running session, but it's still "
          'reporting itself as in use — likely a stuck state left over from '
          'an earlier run. Mark it available again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Force available'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Best-effort real stop if we happen to hold the link; the override below
    // is what actually unlocks the chip either way, so a disconnected device
    // still clears instead of the action silently doing nothing.
    try {
      final connector = ref.read(bleConnectorProvider);
      if (connector.isConnected(deviceId)) {
        await connector.writeToDevice(deviceId, [0x03]);
      }
    } catch (_) {}
    ref.read(bleRunStateMonitorProvider.notifier).forceClear(deviceId);
  }

  Future<void> _handleDeviceDisconnect({
    required String deviceId,
    required Future<void> Function() disconnect,
  }) async {
    await disconnect();
    if (!mounted) return;
    setState(() => _clearDeviceSessionState(deviceId));

    // A just-disconnected BLE device starts advertising again, but the connect
    // flow had stopped the scan — and with auto-connect off, nothing restarts
    // it. Without this, freed devices don't reappear under "Available Bluetooth
    // Devices" on their own (only the one caught in the brief window before the
    // scan stopped would show); the user has to tap Scan. Re-arm a scan so ALL
    // freed devices resurface. `startScan` no-ops if one is already running, and
    // the manual disconnect already suppressed auto-reconnect for this device,
    // so this won't fight a reconnect.
    if (ref.read(sessionTargetProvider).transport == SessionTransport.ble) {
      unawaited(ref.read(startScanProvider)());
    }
  }

  Future<void> _connectAllHydrawaveDevices({
    required AsyncValue<List<ScanResult>> bleScanResultsAsync,
    required bool hydrawaveOnly,
    required Set<String> connectingIds,
  }) async {
    if (!hydrawaveOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enable the Hydrawav3 filter before auto-connecting devices.',
          ),
        ),
      );
      return;
    }

    final scanResults = bleScanResultsAsync.maybeWhen(
      data: (list) => list,
      orElse: () => const <ScanResult>[],
    );

    final expectedUuid = BleConstants.preferredServiceUuid;
    if (expectedUuid == null || expectedUuid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hydrawav3 service UUID is not configured.'),
        ),
      );
      return;
    }

    final targetUuid = BleConstants.normalizeUuid(expectedUuid);
    final filtered = scanResults.where((result) {
      final id = result.device.remoteId.str;
      if (connectingIds.contains(id)) return false;
      return result.advertisementData.serviceUuids.any(
        (uuid) => BleConstants.normalizeUuid(uuid.str) == targetUuid,
      );
    }).toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Hydrawav3 devices available to auto-connect.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final connected = <String>[];
    final failed = <String>[];

    for (final result in filtered) {
      final id = result.device.remoteId.str;
      final name = result.device.platformName.isNotEmpty
          ? result.device.platformName
          : id;

      ref.read(bleConnectingIdsProvider.notifier).state = {
        ...ref.read(bleConnectingIdsProvider),
        id,
      };

      try {
        final ok =
            await ref.read(bleRepositoryProvider).connectDevice(result.device);
        if (ok) {
          connected.add(name);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          ref.read(sessionTargetProvider.notifier).ensureSelected(id);
          if (!mounted) return;
          setState(() {
            _runDeviceIds.add(id);
            _excludedDeviceIds.remove(id);
          });
        } else {
          failed.add(name);
        }
      } finally {
        final current = ref.read(bleConnectingIdsProvider);
        ref.read(bleConnectingIdsProvider.notifier).state = {
          ...current,
        }..remove(id);
      }
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Auto-connect complete: ${connected.length} connected'
          '${failed.isNotEmpty ? ', ${failed.length} failed' : ''}.',
        ),
      ),
    );
  }

  Future<String?> _pickProtocolId({
    required String? currentId,
    String? unitName,
  }) {
    return showPlanSheet<String>(
      context,
      title: unitName == null || unitName.isEmpty
          ? 'Select protocol'
          : '$unitName · protocol',
      builder: (_) => _ProtocolPicker(currentId: currentId),
    );
  }

  String _normalizeProtocolTemplateName(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  ProtocolSelectionOption? _findDefaultProtocolOption(
    List<ProtocolSelectionOption> protocols,
  ) {
    // Pass 0: match by ID — stable across renames.
    for (final protocol in protocols) {
      if (protocol.id == _defaultProtocolId) return protocol;
    }

    final normalizedDefault =
        _normalizeProtocolTemplateName(_defaultProtocolTemplateName);
    // Drop a leading numbering prefix (e.g. "1. ") before comparing.
    String stripLeadingNumber(String n) =>
        n.replaceFirst(RegExp(r'^[0-9]+'), '');

    // Pass 1: prefer an EXACT name match (ignoring a leading number), so
    // "1. Deep-Tension Recovery" wins over a longer variant like
    // "Deep-Tension Recovery Stack".
    for (final protocol in protocols) {
      final normalizedTemplate =
          _normalizeProtocolTemplateName(protocol.templateName);
      if (stripLeadingNumber(normalizedTemplate) == normalizedDefault) {
        return protocol;
      }
    }
    // Pass 2: fall back to a substring match.
    for (final protocol in protocols) {
      final normalizedTemplate =
          _normalizeProtocolTemplateName(protocol.templateName);
      if (normalizedTemplate.contains(normalizedDefault)) {
        return protocol;
      }
    }
    return null;
  }

  Future<void> _seedDefaultProtocolForDevices({
    required List<String> deviceIds,
    required List<ProtocolSelectionOption> protocols,
  }) async {
    if (_isSeedingDefaultProtocol || deviceIds.isEmpty) return;

    final missingDeviceIds = deviceIds
        .where((id) =>
            !_protocolIdByDeviceId.containsKey(id) ||
            !_selectedProtocolByDeviceId.containsKey(id) ||
            !_settingsByDeviceId.containsKey(id))
        .toList();
    if (missingDeviceIds.isEmpty) return;

    // The user's Settings-chosen default (Home > Quick Start default, also
    // settable from the Settings screen) — takes priority over the hardcoded
    // "Deep-Tension Recovery" fallback below, which only applies when the
    // user has never set one and has no recent protocol either. Without
    // this, changing the default in Settings had no visible effect here:
    // this screen always fell back to the hardcoded id/name match.
    final settingsDefaultId = ref.read(defaultProtocolIdProvider);
    final settingsDefault = settingsDefaultId == null
        ? null
        : protocols.where((p) => p.id == settingsDefaultId).firstOrNull;
    final defaultProtocol =
        settingsDefault ?? _findDefaultProtocolOption(protocols);
    // Restore each device's previously PICKED protocol (persisted across
    // navigation) and only fall back to the default when it was never chosen.
    final persisted = ref.read(selectedProtocolIdByDeviceProvider);

    _isSeedingDefaultProtocol = true;
    try {
      for (final deviceId in missingDeviceIds) {
        // Already populated by a concurrent pass — skip.
        if (_protocolIdByDeviceId.containsKey(deviceId) &&
            _selectedProtocolByDeviceId.containsKey(deviceId) &&
            _settingsByDeviceId.containsKey(deviceId)) {
          continue;
        }

        final protocolId = persisted[deviceId] ?? defaultProtocol?.id;
        if (protocolId == null) continue;

        Protocol detail;
        try {
          detail = await ref.read(protocolDetailProvider(protocolId).future);
        } catch (_) {
          // A persisted protocol that no longer loads (e.g. deleted) — fall
          // back to the default so the device still gets seeded.
          if (defaultProtocol == null || protocolId == defaultProtocol.id) {
            continue;
          }
          detail =
              await ref.read(protocolDetailProvider(defaultProtocol.id).future);
        }
        if (!mounted) return;

        setState(() {
          _protocolIdByDeviceId[deviceId] = detail.id;
          _selectedProtocolByDeviceId[deviceId] = detail;
          _settingsByDeviceId[deviceId] = _advancedDefaultsFromProtocol(detail);
          _showAdvancedByDeviceId.putIfAbsent(deviceId, () => false);
        });
      }
    } finally {
      _isSeedingDefaultProtocol = false;
    }
  }

  Future<void> _selectProtocolForDevice(String deviceId,
      {String? unitName}) async {
    final picked = await _pickProtocolId(
      currentId: _protocolIdByDeviceId[deviceId],
      unitName: unitName,
    );
    if (!mounted || picked == null) return;
    await _applyProtocolToDevice(deviceId, picked);
  }

  /// Puts [protocolId] on one unit exactly as the unit's protocol picker does
  /// (also used by the Session Coach's "Use this set"). True on success.
  Future<bool> _applyProtocolToDevice(
      String deviceId, String protocolId) async {
    try {
      final protocol =
          await ref.read(protocolDetailProvider(protocolId).future);
      if (!mounted) return false;
      setState(() {
        _protocolIdByDeviceId[deviceId] = protocolId;
        _selectedProtocolByDeviceId[deviceId] = protocol;
        _settingsByDeviceId[deviceId] = _advancedDefaultsFromProtocol(protocol);
        _showAdvancedByDeviceId[deviceId] = false;
      });
      // Persist the explicit choice so it survives leaving/returning to the tab.
      ref.read(selectedProtocolIdByDeviceProvider.notifier).update(
            (m) => {...m, deviceId: protocolId},
          );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load protocol details: $e')),
      );
      return false;
    }
  }

  /// One-tap Locate for a BLE-connected device card: sends `{"beeping": true}`
  /// straight over BLE via [DeviceRepository.locateDeviceViaBle] (works
  /// mid-session too) with a brief toast — no popup.
  bool _locateSending = false;
  Future<void> _sendLocate(String deviceId) async {
    if (_locateSending) return;
    _locateSending = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(deviceRepositoryProvider)
          .locateDeviceViaBle(deviceId, beeping: true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Locate command sent')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Locate failed: $e')),
      );
    } finally {
      _locateSending = false;
    }
  }

  Future<void> _startSession({
    required List<String> runIds,
    required SessionTransport transport,
  }) async {
    // In Client mode a client must be selected so the intake syncs with a
    // clientId (the backend requires it when clientType != 'guest').
    final clientMode = ref.read(sessionClientModeProvider);
    final selectedClient = ref.read(selectedClientProvider);
    if (clientMode == ClientMode.client && selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Select a client or switch to Guest before starting.',
          ),
          backgroundColor: ThemeConstants.error,
        ),
      );
      return;
    }

    // Skip any device that's already running (rather than aborting the whole
    // start) so a running device can never block starting the ready ones. The
    // UI already excludes running devices from `runIds`; this just guards a
    // race where a device becomes busy between build and tapping Start.
    final busyDevices =
        ref.read(activeSessionsProvider.notifier).getBusyDevices();
    final runnableIds =
        runIds.where((deviceId) => !busyDevices.contains(deviceId)).toList();

    if (runnableIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Those devices are already running. Connect or select a free '
            'device to start a new session.',
          ),
          backgroundColor: ThemeConstants.error,
        ),
      );
      return;
    }

    // Enforce the plan's concurrent-device limit (0 = unlimited). Devices
    // already running org-wide (this phone / web / another phone) plus the ones
    // we're about to start must not exceed it.
    final deviceLimit = ref.read(planDeviceLimitProvider).valueOrNull;
    if (deviceLimit != null && deviceLimit > 0) {
      // One entry per physical device, per-device status honoured — see
      // [liveDeviceCountProvider]. The old inline set unioned `busyDevices`
      // (which expands every MAC into its ±1 variants) with every
      // `session.deviceIds` (which includes devices already stopped inside a
      // still-running session), so the count ran several times higher than the
      // number of devices actually running.
      final runningCount = ref.read(liveDeviceCountProvider);
      if (runningCount + runnableIds.length > deviceLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your plan allows $deviceLimit device(s) at a time '
              '($runningCount already running). Stop a device or '
              'upgrade your plan to run more.',
            ),
            backgroundColor: ThemeConstants.error,
          ),
        );
        return;
      }
    }

    setState(() => _starting = true);

    try {
      final selectedProtocolIds =
          runnableIds.map((id) => _protocolIdByDeviceId[id]!).toSet();
      final fullProtocolById = <String, Protocol>{};

      await Future.wait(
        selectedProtocolIds.map((protocolId) async {
          final detailed =
              await ref.read(protocolDetailProvider(protocolId).future);
          fullProtocolById[protocolId] = detailed;
        }),
      );

      final effectiveDelayedDeviceId =
          _delayedDeviceId != null && runnableIds.contains(_delayedDeviceId)
              ? _delayedDeviceId
              : null;

      // One launcher handles any mix of normal protocols and Protocol Plus
      // templates across all selected devices (auto-detected per device).
      final selections = [
        for (final id in runnableIds)
          SessionDeviceSelection(
            deviceId: id,
            protocol: fullProtocolById[_protocolIdByDeviceId[id]!]!,
            advanced: _settingsByDeviceId[id]!,
          ),
      ];

      // Thread Client/Guest + Guided Assessment so the synced intake carries
      // clientId + the real guided fields (web parity). Client sessions always
      // run the Guided Assessment (Quick Start is Guest-only), so capture
      // intake in Client mode OR when a Guest chose Guided.
      final sessionType = ref.read(sessionTypeProvider);
      final intake =
          (clientMode == ClientMode.client || sessionType == SessionType.guided)
              ? ref.read(guidedAssessmentProvider)
              : null;
      await launchSession(
        ref,
        context,
        selections: selections,
        transport: transport == SessionTransport.wifi ? 'wifi' : 'ble',
        delayedDeviceId: effectiveDelayedDeviceId,
        clientId: clientMode == ClientMode.client ? selectedClient?.id : null,
        intake: intake,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Start failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  // Client/Guest selection, the Guided-vs-QuickStart chooser and the Guided
  // Assessment now live on the dedicated "AI" tab (AiScreen). This screen keeps
  // only device management + per-device Session Setup + the Start button, which
  // still reads the client/session-type/guided state from the shared providers.

  Widget _buildStartSessionButton({
    required List<String> runIds,
    required SessionTransport transport,
    required bool canStart,
  }) {
    final enabled = !_starting && canStart;

    // Explain why Start is disabled so it never looks stuck (esp. now that the
    // Guided Assessment moved to the AI tab).
    String? reason;
    if (!enabled && !_starting) {
      if (runIds.isEmpty) {
        reason = 'Connect or select a device to start.';
      } else if (!runIds.every((id) =>
          _protocolIdByDeviceId.containsKey(id) &&
          _settingsByDeviceId.containsKey(id))) {
        reason = 'Select a protocol for each device.';
      }
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: enabled
                ? () => _startSession(runIds: runIds, transport: transport)
                : null,
            icon: Icon(
              _starting
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
              size: 20,
            ),
            label: Text(_starting ? 'Starting...' : 'Start Session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeConstants.accent,
              foregroundColor: Colors.white,
              // Let the disabled state fall back to the theme default (grayish),
              // matching the "Generate AI Report" button in light mode.
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: ThemeConstants.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  /// Why Start can't run yet, or null when it can — the same reasons the old
  /// Start button printed under itself.
  String? _startBlockedReason(List<String> runIds, bool canStart) {
    if (_starting || canStart) return null;
    if (runIds.isEmpty) return 'Connect or select a device to start.';
    if (!runIds.every((id) =>
        _protocolIdByDeviceId.containsKey(id) &&
        _settingsByDeviceId.containsKey(id))) {
      return 'Select a protocol for each device.';
    }
    return null;
  }

  /// The v6 dock: music and Start as round buttons, then the pre-start
  /// summary strip. Start runs exactly the same `_startSession` as before;
  /// when it can't start yet, tapping it says why.
  Widget _planDock({
    required List<String> runIds,
    required SessionTransport transport,
    required bool canStart,
  }) {
    final enabled = !_starting && canStart;
    final client = ref.watch(selectedClientProvider);
    final guest = ref.watch(sessionClientModeProvider) == ClientMode.guest ||
        client == null;
    final music = ref.watch(sessionMusicControllerProvider);

    var longest = Duration.zero;
    final names = <String>[];
    for (final id in runIds) {
      final proto = _selectedProtocolByDeviceId[id];
      if (proto == null) continue;
      if (proto.totalDuration > longest) longest = proto.totalDuration;
      if (!names.contains(proto.templateName)) names.add(proto.templateName);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlanMusicFab(
                on: music.hasTrack,
                onTap: () => showSessionMusicPicker(context, ref),
              ),
              const SizedBox(height: 12),
              PlanStartFab(
                ready: enabled,
                starting: _starting,
                onTap: () {
                  if (enabled) {
                    _startSession(runIds: runIds, transport: transport);
                    return;
                  }
                  final reason = _startBlockedReason(runIds, canStart);
                  if (reason == null) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text(reason)));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: PlanSummaryStrip(
            who: guest ? 'Guest' : client.displayName,
            units: runIds.length,
            longest: longest,
            protocols: names,
            guest: guest,
          ),
        ),
      ],
    );
  }

  /// Reference "Connection" picker — sets the REAL transport.
  void _showConnectionSheet(
    BuildContext context,
    RefPalette p,
    SessionTransport current,
  ) {
    void pick(SessionTransport t) {
      ref.read(sessionTargetProvider.notifier).setTransport(t, ref);
      if (t == SessionTransport.ble) {
        Future.delayed(const Duration(milliseconds: 100),
            () => ref.read(startScanProvider)());
      }
      Navigator.of(context).pop();
    }

    Widget row(String title, String subtitle, bool selected, VoidCallback tap) {
      return InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: p.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (selected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.tanSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Selected',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.copperInk)),
                )
              else
                Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: p.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Connection',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: p.ink)),
              const SizedBox(height: 6),
              Text(
                'Most rooms run Bluetooth. WiFi is for enterprise clinics '
                'controlling units through the cloud.',
                style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
              ),
              const SizedBox(height: 12),
              row(
                  'Bluetooth',
                  'Direct to nearby units — the default',
                  current == SessionTransport.ble,
                  () => pick(SessionTransport.ble)),
              Divider(height: 1, color: p.line),
              row(
                  'WiFi · cloud',
                  'Enterprise clinics · units beyond Bluetooth range',
                  current == SessionTransport.wifi,
                  () => pick(SessionTransport.wifi)),
            ],
          ),
        ),
      ),
    );
  }

  /// WiFi "Your other units" — registered devices with a Select/Selected
  /// toggle, in the copper reference design. Same wiring as the legacy WiFi
  /// list: `sessionTargetProvider.toggleDevice` + plan-limit enforcement.
  Widget _buildWifiUnits(
    RefPalette p,
    List<DeviceInfo> devices,
    SessionTargetState target,
    Set<String> inUseDeviceIds,
    bool deviceLimitReached,
    int? deviceLimit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Text(
            'YOUR OTHER UNITS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: p.copperInk,
            ),
          ),
        ),
        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No registered WiFi units. Add one from the Device Center.',
              style: TextStyle(fontSize: 12, height: 1.4, color: p.ink3),
            ),
          )
        else
          for (final device in devices)
            _buildWifiUnitRow(p, device, target, inUseDeviceIds,
                deviceLimitReached, deviceLimit),
        const SizedBox(height: 8),
        _refAddUnitButton(p),
      ],
    );
  }

  Widget _buildWifiUnitRow(
    RefPalette p,
    DeviceInfo device,
    SessionTargetState target,
    Set<String> inUseDeviceIds,
    bool deviceLimitReached,
    int? deviceLimit,
  ) {
    final inUse = inUseDeviceIds.contains(device.macAddress);
    final selected =
        !inUse && target.filteredDeviceIds.contains(device.macAddress);

    void toggle() {
      if (!selected && deviceLimitReached) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your plan allows $deviceLimit device(s) at a time. '
              'Stop a running device or upgrade your plan to run more.',
            ),
          ),
        );
        return;
      }
      ref.read(sessionTargetProvider.notifier).toggleDevice(device.macAddress);
      setState(() {
        if (selected) {
          _clearDeviceSessionState(device.macAddress);
        } else {
          _runDeviceIds.add(device.macAddress);
          _excludedDeviceIds.remove(device.macAddress);
        }
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? p.copper : p.cardline,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: p.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5E8CA0), Color(0xFF2F4A5A)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.wifi_rounded, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  device.macAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (inUse)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _handleInUseTap(device.macAddress),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.tanSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'In use',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
              ),
            )
          else
            Material(
              color: selected ? p.copper : null,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: toggle,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: selected ? null : p.heroGrad,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        const Icon(Icons.check_rounded,
                            size: 15, color: Colors.white),
                      if (selected) const SizedBox(width: 4),
                      Text(
                        selected ? 'Selected' : 'Select',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF2E9E2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Reference `.btn.ghost` — "Add a new unit · Device Center".
  Widget _refAddUnitButton(RefPalette p) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => context.push(RoutePaths.deviceRegister),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 16, color: p.ink2),
              const SizedBox(width: 6),
              Text(
                'Add a new unit · Device Center',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: p.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionSetupCard({
    required _DeviceSessionCardData data,
    required List<String> currentRunIds,
    required Map<String, String> currentLabelsById,
    required Set<String> busyDeviceIds,
    Set<String> pendingStopDeviceIds = const {},
    bool refDesign = false,
  }) {
    final isIncluded = _runDeviceIds.contains(data.id);
    final isBusy = busyDeviceIds.contains(data.id);
    // Left the busy set already (engine went terminal), but the backend
    // hasn't confirmed the stop yet — mutually exclusive with isBusy.
    final isPendingStop = !isBusy && pendingStopDeviceIds.contains(data.id);
    final selectedProtocol = _selectedProtocolByDeviceId[data.id];
    final settings = _settingsByDeviceId[data.id];
    final showAdvanced = _showAdvancedByDeviceId[data.id] ?? false;
    final canEditAdvanced =
        isIncluded && selectedProtocol != null && settings != null && !isBusy;
    // A busy device has no protocol of its own to show (it's running one we
    // didn't launch) — leave the protocol row blank rather than prompting to
    // pick, which it can't do while in use.
    final protocolMeta = isBusy
        ? ''
        : selectedProtocol == null
            ? 'Pick a protocol before starting the session.'
            : [
                if (selectedProtocol.goalTagName?.isNotEmpty ?? false)
                  selectedProtocol.goalTagName!,
                '${(selectedProtocol.totalDuration.inSeconds / 60).round()} min',
              ].join(' · ');

    return _SessionDeviceSetupCard(
      bleId: data.transportLabel == 'BLE' ? data.id : null,
      icon: data.icon,
      transportLabel: data.transportLabel,
      name: data.name,
      subtitle: data.subtitle,
      inUse: isIncluded,
      isRunning: isBusy,
      isPendingStop: isPendingStop,
      onRetryStop:
          isPendingStop ? () => _openPendingStopSession(data.id) : null,
      onTapInUse: isBusy ? () => _handleInUseTap(data.id) : null,
      protocolTitle:
          isBusy ? '' : (selectedProtocol?.templateName ?? 'Select protocol'),
      protocolSubtitle: protocolMeta,
      showAdvanced: showAdvanced,
      advancedEnabled: canEditAdvanced,
      // The card's Delay stepper edits the same Advanced setting.
      startDelay: settings?.startDelay ?? 0,
      onChangeStartDelay: canEditAdvanced
          ? (value) {
              final current = _settingsByDeviceId[data.id];
              if (current == null) return;
              final clamped = value.clamp(0, 60);
              if (clamped == current.startDelay) return;
              setState(() {
                _settingsByDeviceId[data.id] =
                    current.copyWith(startDelay: clamped);
              });
            }
          : null,
      onToggleInUse: (value) => _setDeviceIncluded(data.id, value),
      onSelectProtocol: isIncluded
          ? () => _selectProtocolForDevice(data.id, unitName: data.name)
          : null,
      onDisconnect: data.onDisconnect,
      // Locate is offered only for a BLE-connected unit (WiFi units locate
      // from the Devices Fleet screen). data.id is the BLE remoteId — the
      // exact key locateDeviceViaBle / bleRepository.isConnected use, and
      // works on iOS (UUID) as well as Android (MAC). One tap fires it
      // straight away (beep on) — no popup.
      onLocate:
          data.transportLabel == 'BLE' ? () => _sendLocate(data.id) : null,
      onToggleAdvanced: canEditAdvanced
          ? () {
              setState(() {
                _showAdvancedByDeviceId[data.id] = !showAdvanced;
              });
            }
          : null,
      advancedChild: !canEditAdvanced
          ? null
          : (selectedProtocol.isProtocolPlus
              ? _ProtocolPlusAdvancedSettingsPanel(
                  settings: settings,
                  onChangeSettings: (updated) {
                    setState(() => _settingsByDeviceId[data.id] = updated);
                  },
                )
              : _SessionAdvancedSettingsPanel(
                  settings: settings,
                  onChangeSettings: (updated) {
                    setState(() => _settingsByDeviceId[data.id] = updated);
                  },
                )),
      refDesign: refDesign,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairedDevices = ref.watch(pairedDevicesProvider);
    ref.watch(activeSessionsProvider);
    final protocolOptionsAsync =
        ref.watch(protocolSelectionOptionsProvider(null));
    final target = ref.watch(sessionTargetProvider);
    final wifiAsync = ref.watch(wifiDevicesByOrgProvider);
    final bleScanResultsAsync = ref.watch(bleScanResultsProvider);
    final connectingIds = ref.watch(bleConnectingIdsProvider);
    final hydrawaveOnly = ref.watch(_hydrawaveOnlyProvider);
    final autoConnectEnabled = ref.watch(autoConnectEnabledProvider);
    final provisioningIds = ref.watch(bleProvisioningIdsProvider);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    final pairedDeviceList = pairedDevices.maybeWhen(
      data: (devices) => devices.cast<PairedDevice>(),
      orElse: () => const <PairedDevice>[],
    );
    final bleConnectedDevices = pairedDeviceList.where((device) {
      if (provisioningIds.contains(device.id)) return false;
      final state = ref.watch(bleDeviceStatusProvider(device.id));
      return state == BleConnectionStatus.connected;
    }).toList();

    // Prefer the last-known value so a reload (e.g. after removing the last
    // device) keeps rendering the real list/empty-state instead of dropping
    // back to an infinite spinner. Only treat it as "loading" on first fetch.
    final wifiDeviceList = wifiAsync.valueOrNull ?? const <DeviceInfo>[];
    final wifiFirstLoading = wifiAsync.isLoading && !wifiAsync.hasValue;
    final selectedWifiDevices = wifiDeviceList
        .where((device) => target.deviceIds.contains(device.macAddress))
        .toList();

    final currentSessionDeviceIds = target.transport == SessionTransport.ble
        ? bleConnectedDevices.map((device) => device.id).toList()
        : selectedWifiDevices.map((device) => device.macAddress).toList();
    final currentLabelsById = <String, String>{
      if (target.transport == SessionTransport.ble)
        for (final device in bleConnectedDevices) device.id: device.name,
      if (target.transport == SessionTransport.wifi)
        for (final device in selectedWifiDevices)
          device.macAddress: device.name,
    };

    // Devices already running in ANY live session — this phone, the web, or
    // another phone — can't be selected for a new run. Local busy set covers
    // this phone's runs; the org-wide feed covers web/other phones. When we
    // already know from our own session engine that a device is stopped, we
    // prefer that local truth over a stale backend/feed report so the UI frees
    // the device immediately.
    final busyDeviceIds =
        ref.read(activeSessionsProvider.notifier).getBusyDevices().toSet();
    final localDeviceStatuses = <String, live.SessionStatus>{};
    for (final session in ref.watch(activeSessionsProvider)) {
      for (final entry in session.deviceStatuses.entries) {
        localDeviceStatuses[entry.key] = entry.value;
      }
    }

    bool shouldTreatAsBusy(String deviceId) {
      final localStatus = localDeviceStatuses[deviceId];
      return localStatus == null ||
          localStatus == live.SessionStatus.running ||
          localStatus == live.SessionStatus.paused;
    }

    // `completed` counts as busy here too, matching the Hub's live-devices
    // card (`_isVisibleStatus` in live_sessions_provider.dart): the backend
    // session lingers until someone hits Stop All, so a device whose run
    // finished but hasn't been closed out yet is NOT actually free. Excluding
    // `completed` used to make this screen quietly unlock + hide the card the
    // instant a countdown hit zero, while Hub kept showing it stuck at
    // 00:00 — same backend session, two screens disagreeing about whether it
    // was still active. Now both agree, and the tappable "In use" chip below
    // is the way to reach it here, same as the Hub row.
    bool isLiveStatus(live.SessionStatus s) =>
        s == live.SessionStatus.running ||
        s == live.SessionStatus.paused ||
        s == live.SessionStatus.completed;

    final liveInUseDeviceIds = <String>{};
    for (final s in ref.watch(liveSessionsProvider)) {
      if (s.liveDevices.isNotEmpty) {
        for (final d in s.liveDevices) {
          if (isLiveStatus(d.status)) {
            if (shouldTreatAsBusy(d.deviceId)) {
              liveInUseDeviceIds.add(d.deviceId);
            }
          }
        }
      } else if (isLiveStatus(s.status)) {
        // Feed carried no per-device breakdown — fall back to session status.
        for (final deviceId in s.deviceIds) {
          if (shouldTreatAsBusy(deviceId)) {
            liveInUseDeviceIds.add(deviceId);
          }
        }
      }
    }
    // A BLE unit whose own telemetry reports rs = Play/Pause is mid-session
    // (e.g. started from another controller) — treat it as "In use" too, even
    // when it isn't in the backend live feed. Keyed by BLE remoteId, which is
    // exactly the id BLE cards select on (device.id).
    final bleBusyDeviceIds = ref.watch(bleRunStateMonitorProvider);
    final inUseDeviceIds = <String>{
      ...busyDeviceIds,
      ...liveInUseDeviceIds,
      ...bleBusyDeviceIds.where(shouldTreatAsBusy),
    };

    // Devices whose LOCAL engine already went terminal, but the backend
    // hasn't confirmed the stop (a failed/retrying POST — see
    // `SessionEngineState.backendStopUnresolved`). Deliberately NOT merged
    // into `inUseDeviceIds`: a device here has already left `busyDeviceIds`,
    // so it needs its own "pending stop" state rather than being folded back
    // into the fully-locked "in use" bucket.
    final pendingBackendStopDeviceIds =
        ref.watch(pendingBackendStopDeviceIdsProvider);

    // Auto-select + default-protocol seeding apply only to devices that are NOT
    // busy. Seeding a busy device would give it a protocol we immediately clear
    // (below), and auto-select would re-add what we just deselected — the two
    // fighting each frame is what made the busy card's protocol row blink.
    final selectableSessionDeviceIds = currentSessionDeviceIds
        .where((id) => !inUseDeviceIds.contains(id))
        .toList();
    _syncVisibleSessionDevices(selectableSessionDeviceIds);
    protocolOptionsAsync.whenData((protocols) {
      _seedDefaultProtocolForDevices(
        deviceIds: selectableSessionDeviceIds,
        protocols: protocols,
      );
    });

    // A device that just went busy (e.g. its BLE telemetry started reporting
    // Play) while it was selected here must leave the run set and drop its
    // protocol so the card shows blank, not a stale pick. One-shot: once it's
    // out of the run set the seeding above won't re-add it (busy is filtered
    // from selectableSessionDeviceIds), so this doesn't re-fire and the row
    // stops blinking. When the device later frees up it re-appears in the
    // selectable set and is auto-selected + re-seeded as normal. Done after
    // this frame to avoid mutating state mid-build.
    final nowBusySelected =
        _runDeviceIds.where(inUseDeviceIds.contains).toList();
    if (nowBusySelected.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final id in nowBusySelected) {
            _clearDeviceSessionState(id);
          }
        });
      });
    }
    // The Start batch is only the READY (not-yet-running) selected devices. A
    // device already running (this phone / web / another phone) is excluded so
    // pressing Start runs just the new device(s) and never trips the "device in
    // use" guard — the running device is managed from the Session screen.
    final runIds = currentSessionDeviceIds
        .where(
            (id) => _runDeviceIds.contains(id) && !inUseDeviceIds.contains(id))
        .toList();
    // Plan's max concurrent devices (0/null = unlimited). Devices already
    // running org-wide consume slots, so a new run can add at most
    // (deviceLimit - alreadyRunning) more — web parity.
    final deviceLimit = ref.watch(planDeviceLimitProvider).valueOrNull;
    // New (not-yet-running) selections only — exclude any already counted in
    // inUseDeviceIds so an own running device isn't double-counted.
    final newlySelectedCount = currentSessionDeviceIds
        .where((id) => !inUseDeviceIds.contains(id))
        .length;
    // `inUseDeviceIds.length` is NOT the running-device count: the same unit
    // lands in it twice when the local advertised id and the backend's
    // firmware id (which differ by ±1) are both present, so a single running
    // device could already read as two and lock out the plan.
    final runningDeviceCount = ref.watch(liveDeviceCountProvider);
    final deviceLimitReached = deviceLimit != null &&
        deviceLimit > 0 &&
        (runningDeviceCount + newlySelectedCount) >= deviceLimit;
    // Picking a client no longer requires an area of focus. The body-part /
    // guided-assessment step is optional intake, not a precondition — Start
    // only needs devices with a protocol configured, in Client and Guest mode
    // alike.
    final canStart = runIds.isNotEmpty &&
        runIds.every((id) =>
            _protocolIdByDeviceId.containsKey(id) &&
            _settingsByDeviceId.containsKey(id));

    // Tablet: a centred 786px column, units two across (97-tablet.js).
    final tablet = HwTablet.of(context);
    final side = HwTablet.sidePadding(context, phone: 16);
    final plusMute = ref.watch(protocolPlusMuteEnabledProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      // The Hydrawav3 wordmark over the plan (`.v5s-brand`).
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                          child: Center(
                            child: SizedBox(
                              width: 236,
                              child: ClipRect(
                                child: Align(
                                  heightFactor: 0.62,
                                  child: SvgPicture.asset(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 'assets/images/Hydrawav3_White_Logo.svg'
                                        : 'assets/images/Hydrawav3_Black_Logo.svg',
                                    fit: BoxFit.fitWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding:
                                EdgeInsets.fromLTRB(side + 2, 12, side, 16),
                            child: AnimatedEntrance(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'Session Plan',
                                            style: TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w700,
                                              color: ThemeConstants.textPrimary,
                                              letterSpacing: -0.23,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: TokenBalanceBadge(),
                                      ),
                                      // "Add a unit" now lives at the bottom of the
                                      // "Your other units" scan section for everyone.
                                      if (_showLegacyDeviceManager) ...[
                                        const SizedBox(width: 10),
                                        _HeaderBtn(
                                          icon: Icons.add_rounded,
                                          filled: true,
                                          onTap: () => context
                                              .push(RoutePaths.deviceRegister),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Connect your device and customize your protocols',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: PlanTones.sub(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_showNewDesign) ...[
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(side, 0, side, 4),
                          sliver: SliverToBoxAdapter(
                            child: AnimatedEntrance(
                              index: 0,
                              // Live runs surface here (above Select User) rather
                              // than in Session History — the banner collapses to
                              // nothing when no session is running. Below it, the
                              // v6 duo: Select User beside Find Pad Placements.
                              child: Column(
                                children: [
                                  const LiveSessionsBanner(),
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const Expanded(child: PlayersSection()),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FindPadPlacementsCard(
                                            onTap: () => context.go(
                                                '${RoutePaths.assistant}?intent=pads'),
                                            // tablet "PICK A FOCUS": the same
                                            // recovery deep link the Hub uses
                                            onFocus: (goal) => context.go(
                                                '${RoutePaths.assistant}?intent=recovery&goal=$goal'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // v6 Session Coach: body → goal → the admin's
                                  // sets, applied to the units below.
                                  const SizedBox(height: 12),
                                  SessionCoachCard(
                                    units: [
                                      for (final id in currentSessionDeviceIds)
                                        CoachUnit(
                                          id: id,
                                          name: currentLabelsById[id] ?? 'Unit',
                                          canLocate: target.transport ==
                                              SessionTransport.ble,
                                        ),
                                    ],
                                    onApply: _applyProtocolToDevice,
                                    onLocate: _sendLocate,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(side, 14, side, 4),
                          sliver: SliverToBoxAdapter(
                            child: AnimatedEntrance(
                              index: 2,
                              child: Builder(builder: (context) {
                                final p = RefPalette.of(context);
                                // Build the REAL connected-device cards (same
                                // callbacks as the standard manager) in the copper
                                // reference design.
                                final cards = <Widget>[];
                                if (target.transport == SessionTransport.ble) {
                                  for (final device in bleConnectedDevices) {
                                    cards.add(Padding(
                                      padding: EdgeInsets.only(
                                          bottom: tablet ? 0 : 10),
                                      child: _buildSessionSetupCard(
                                        data: _DeviceSessionCardData(
                                          id: device.id,
                                          icon: Icons.bluetooth_rounded,
                                          transportLabel: 'BLE',
                                          name: device.name,
                                          subtitle: isIos
                                              ? 'Connected Device'
                                              : 'MAC: ${device.id}',
                                          onDisconnect: () async {
                                            await _handleDeviceDisconnect(
                                              deviceId: device.id,
                                              disconnect: () async {
                                                await ref
                                                    .read(bleRepositoryProvider)
                                                    .disconnectDevice(
                                                        device.id);
                                                ref
                                                    .read(sessionTargetProvider
                                                        .notifier)
                                                    .ensureDeselected(
                                                        device.id);
                                              },
                                            );
                                          },
                                        ),
                                        currentRunIds: runIds,
                                        currentLabelsById: currentLabelsById,
                                        busyDeviceIds: inUseDeviceIds,
                                        pendingStopDeviceIds:
                                            pendingBackendStopDeviceIds,
                                        refDesign: true,
                                      ),
                                    ));
                                  }
                                } else {
                                  for (final device in selectedWifiDevices) {
                                    cards.add(Padding(
                                      padding: EdgeInsets.only(
                                          bottom: tablet ? 0 : 10),
                                      child: _buildSessionSetupCard(
                                        data: _DeviceSessionCardData(
                                          id: device.macAddress,
                                          icon: Icons.wifi_rounded,
                                          transportLabel: 'WiFi',
                                          name: device.name,
                                          subtitle: 'MAC: ${device.macAddress}',
                                          onDisconnect: () async {
                                            ref
                                                .read(sessionTargetProvider
                                                    .notifier)
                                                .toggleDevice(
                                                    device.macAddress);
                                            setState(() =>
                                                _clearDeviceSessionState(
                                                    device.macAddress));
                                          },
                                        ),
                                        currentRunIds: runIds,
                                        currentLabelsById: currentLabelsById,
                                        busyDeviceIds: inUseDeviceIds,
                                        pendingStopDeviceIds:
                                            pendingBackendStopDeviceIds,
                                        refDesign: true,
                                      ),
                                    ));
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // `.ry-ses-sechead`: eyebrow + mute, Auto-connect
                                    // and Connection pills.
                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(2, 0, 2, 6),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            child: PlanEyebrow('Session setup'),
                                          ),
                                          // The Protocol Plus "2 beeps only"
                                          // switch, as the v6 mute pill.
                                          PlanPill(
                                            icon: plusMute
                                                ? Icons.volume_off_rounded
                                                : Icons.volume_up_rounded,
                                            on: plusMute,
                                            tooltip:
                                                'Protocol Plus: 2 beeps only',
                                            onTap: () {
                                              final next = !plusMute;
                                              ref
                                                  .read(
                                                      protocolPlusMuteEnabledProvider
                                                          .notifier)
                                                  .setEnabled(next);
                                              ScaffoldMessenger.of(context)
                                                ..clearSnackBars()
                                                ..showSnackBar(SnackBar(
                                                  duration: const Duration(
                                                      seconds: 2),
                                                  content: Text(next
                                                      ? 'Protocol Plus: 2 beeps only — muted between stages'
                                                      : 'Protocol Plus: beeps at every stage change'),
                                                ));
                                            },
                                          ),
                                          const SizedBox(width: 6),
                                          PlanPill(
                                            label: 'Auto-connect',
                                            on: autoConnectEnabled,
                                            onTap: () => ref
                                                .read(autoConnectEnabledProvider
                                                    .notifier)
                                                .setEnabled(
                                                    !autoConnectEnabled),
                                          ),
                                          const SizedBox(width: 6),
                                          PlanPill(
                                            icon: target.transport ==
                                                    SessionTransport.wifi
                                                ? Icons.wifi_rounded
                                                : Icons.bluetooth_rounded,
                                            label: target.transport ==
                                                    SessionTransport.wifi
                                                ? 'WiFi'
                                                : 'BLE',
                                            caret: true,
                                            onTap: () => _showConnectionSheet(
                                                context, p, target.transport),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (cards.isEmpty)
                                      PlanCard(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 22),
                                        child: Text(
                                          target.transport ==
                                                  SessionTransport.ble
                                              ? 'No Bluetooth units connected. Scan below or connect an available unit.'
                                              : 'No WiFi units selected. Set up WiFi from the Device Center.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 13,
                                              height: 1.45,
                                              color: p.ink2),
                                        ),
                                      )
                                    else if (tablet)
                                      // Tablet: units two across
                                      // (97-tablet §2b).
                                      HwAutoGrid(gap: 14, children: cards)
                                    else
                                      ...cards,
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                        // Session music is the small round button above Start,
                        // and the Protocol Plus mute is the pill in the Session
                        // setup header (v6) — the card that held both is gone.
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(side, 8, side, 24),
                          sliver: SliverToBoxAdapter(
                            child: AnimatedEntrance(
                              index: 4,
                              // BLE → live scan + connect; WiFi → registered-unit
                              // list with Select/Selected (same as the old flow).
                              child: target.transport == SessionTransport.ble
                                  ? const ScanUnitsSection()
                                  : Builder(builder: (context) {
                                      return _buildWifiUnits(
                                        RefPalette.of(context),
                                        wifiDeviceList,
                                        target,
                                        inUseDeviceIds,
                                        deviceLimitReached,
                                        deviceLimit,
                                      );
                                    }),
                            ),
                          ),
                        ),
                      ],
                      // University shows only the clean reference design above;
                      // the standard device manager below is hidden for it.
                      if (_showLegacyDeviceManager)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: AnimatedEntrance(
                              index: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: ThemeConstants.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: ThemeConstants.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.20),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _SegmentBtn(
                                        active: target.transport ==
                                            SessionTransport.ble,
                                        icon: Icons.bluetooth_rounded,
                                        label: 'Bluetooth',
                                        onTap: () {
                                          ref
                                              .read(sessionTargetProvider
                                                  .notifier)
                                              .setTransport(
                                                  SessionTransport.ble, ref);
                                          Future.delayed(
                                            const Duration(milliseconds: 100),
                                            () => ref.read(startScanProvider)(),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _SegmentBtn(
                                        active: target.transport ==
                                            SessionTransport.wifi,
                                        icon: Icons.wifi_rounded,
                                        label: 'WiFi',
                                        onTap: () => ref
                                            .read(
                                                sessionTargetProvider.notifier)
                                            .setTransport(
                                                SessionTransport.wifi, ref),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_showLegacyDeviceManager)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (target.transport ==
                                    SessionTransport.ble) ...[
                                  Container(
                                    height: 34,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: ThemeConstants.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: ThemeConstants.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.verified_rounded,
                                          size: 14,
                                          color: hydrawaveOnly
                                              ? ThemeConstants.accent
                                              : ThemeConstants.textTertiary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Hydrawav3',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: hydrawaveOnly
                                                ? ThemeConstants.accent
                                                : ThemeConstants.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          height: 22,
                                          child: Center(
                                            child: Transform.scale(
                                              scale: 0.68,
                                              child: Switch.adaptive(
                                                value: hydrawaveOnly,
                                                activeColor:
                                                    ThemeConstants.accent,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                onChanged: (value) => ref
                                                    .read(_hydrawaveOnlyProvider
                                                        .notifier)
                                                    .state = value,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hydrawaveOnly)
                                    GestureDetector(
                                      onTap: () async {
                                        await ref
                                            .read(autoConnectEnabledProvider
                                                .notifier)
                                            .setEnabled(!autoConnectEnabled);
                                        if (!autoConnectEnabled) {
                                          await _connectAllHydrawaveDevices(
                                            bleScanResultsAsync:
                                                bleScanResultsAsync,
                                            hydrawaveOnly: hydrawaveOnly,
                                            connectingIds: connectingIds,
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: autoConnectEnabled
                                              ? ThemeConstants.accent
                                              : ThemeConstants.surface,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: autoConnectEnabled
                                                ? ThemeConstants.accent
                                                : ThemeConstants.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.usb_rounded,
                                              size: 16,
                                              color: autoConnectEnabled
                                                  ? ThemeConstants.textPrimary
                                                  : ThemeConstants
                                                      .textSecondary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Auto-connect',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: autoConnectEnabled
                                                    ? ThemeConstants.textPrimary
                                                    : ThemeConstants
                                                        .textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                                _ScanButton(
                                  visible:
                                      target.transport == SessionTransport.ble,
                                  onTap: () => ref.read(startScanProvider)(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_showLegacyDeviceManager &&
                          target.transport == SessionTransport.wifi) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: const SliverToBoxAdapter(
                            child: AnimatedEntrance(
                              index: 0,
                              child: SectionHeader(title: 'Session Setup'),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          sliver: (() {
                            if (wifiFirstLoading) {
                              return const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (wifiAsync.hasError && !wifiAsync.hasValue) {
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Failed to load WiFi devices: ${wifiAsync.error}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ThemeConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final list = wifiDeviceList;
                            if (list.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 8, bottom: 8),
                                  child: Text(
                                    'No registered devices.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ThemeConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (selectedWifiDevices.isEmpty) {
                              return const SliverToBoxAdapter(
                                child: _EmptyDashed(
                                  icon: Icons.wifi_rounded,
                                  title: 'No devices selected',
                                  subtitle:
                                      'Select a WiFi device below to configure it.',
                                ),
                              );
                            }

                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, index) {
                                  final device = selectedWifiDevices[index];
                                  return AnimatedEntrance(
                                    index: index + 1,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _buildSessionSetupCard(
                                        data: _DeviceSessionCardData(
                                          id: device.macAddress,
                                          icon: Icons.wifi_rounded,
                                          transportLabel: 'WiFi',
                                          name: device.name,
                                          subtitle: 'MAC: ${device.macAddress}',
                                          onDisconnect: () async {
                                            await _handleDeviceDisconnect(
                                              deviceId: device.macAddress,
                                              disconnect: () async {
                                                await ref
                                                    .read(bleRepositoryProvider)
                                                    .disconnectDevice(
                                                        device.macAddress);
                                                ref
                                                    .read(sessionTargetProvider
                                                        .notifier)
                                                    .ensureDeselected(
                                                        device.macAddress);
                                              },
                                            );
                                          },
                                        ),
                                        currentRunIds: runIds,
                                        currentLabelsById: currentLabelsById,
                                        busyDeviceIds: inUseDeviceIds,
                                        pendingStopDeviceIds:
                                            pendingBackendStopDeviceIds,
                                      ),
                                    ),
                                  );
                                },
                                childCount: selectedWifiDevices.length,
                              ),
                            );
                          })(),
                        ),
                        if (selectedWifiDevices.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildStartSessionButton(
                                    runIds: runIds,
                                    transport: target.transport,
                                    canStart: canStart,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: const SliverToBoxAdapter(
                            child:
                                SectionHeader(title: 'Available WiFi Devices'),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          sliver: (() {
                            if (wifiFirstLoading) {
                              return const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (wifiAsync.hasError && !wifiAsync.hasValue) {
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Failed to load WiFi devices: ${wifiAsync.error}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ThemeConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }
                            final list = wifiDeviceList;
                            if (list.isEmpty) {
                              return const SliverToBoxAdapter(
                                child: _EmptyDashed(
                                  icon: Icons.wifi_rounded,
                                  title: 'No registered devices',
                                  subtitle:
                                      'Make sure your device is turned on',
                                ),
                              );
                            }

                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, index) {
                                  final device = list[index];
                                  // Running in ANY live session — this phone's OWN run, the
                                  // web, or another phone — counts as "In use". "In use"
                                  // wins over "Selected" so a device this app started also
                                  // shows the badge (not a still-selectable "Selected").
                                  final inUse = inUseDeviceIds
                                      .contains(device.macAddress);
                                  final pendingStop = !inUse &&
                                      pendingBackendStopDeviceIds
                                          .contains(device.macAddress);
                                  final selected = !inUse &&
                                      !pendingStop &&
                                      target.filteredDeviceIds
                                          .contains(device.macAddress);
                                  return AnimatedEntrance(
                                    index: index + 1,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _AvailableDeviceRow(
                                        icon: Icons.wifi_rounded,
                                        name: device.name,
                                        idText: device.macAddress,
                                        buttonLabel:
                                            selected ? 'Selected' : 'Select',
                                        isInUse: inUse,
                                        isPendingStop: pendingStop,
                                        onTap: pendingStop
                                            ? () => _openPendingStopSession(
                                                device.macAddress)
                                            : inUse
                                                ? () => _handleInUseTap(
                                                    device.macAddress)
                                                : () {
                                                    // Enforce the plan's concurrent-device
                                                    // limit when adding a device (deselect is
                                                    // always allowed).
                                                    if (!selected &&
                                                        deviceLimitReached) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Your plan allows $deviceLimit device(s) at a time. '
                                                            'Stop a running device or upgrade your plan to run more.',
                                                          ),
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    ref
                                                        .read(
                                                            sessionTargetProvider
                                                                .notifier)
                                                        .toggleDevice(
                                                            device.macAddress);
                                                    setState(() {
                                                      if (selected) {
                                                        _clearDeviceSessionState(
                                                            device.macAddress);
                                                      } else {
                                                        _runDeviceIds.add(
                                                            device.macAddress);
                                                        _excludedDeviceIds
                                                            .remove(device
                                                                .macAddress);
                                                      }
                                                    });
                                                  },
                                      ),
                                    ),
                                  );
                                },
                                childCount: list.length,
                              ),
                            );
                          })(),
                        ),
                      ],
                      if (_showLegacyDeviceManager &&
                          target.transport == SessionTransport.ble) ...[
                        pairedDevices.when(
                          data: (devices) {
                            final scanResults =
                                ref.watch(bleScanResultsProvider);
                            final connectedDevices =
                                devices.cast<PairedDevice>().where((d) {
                              if (provisioningIds.contains(d.id)) return false;
                              final state =
                                  ref.watch(bleDeviceStatusProvider(d.id));
                              return state == BleConnectionStatus.connected;
                            }).toList();

                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  const SectionHeader(title: 'Session Setup'),
                                  if (connectedDevices.isEmpty)
                                    const _EmptyDashed(
                                      icon: Icons.bluetooth_rounded,
                                      title: 'No devices connected',
                                      subtitle:
                                          'Connect a Bluetooth device to configure protocol and session settings.',
                                    ),
                                  ...connectedDevices
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    final index = entry.key;
                                    final device = entry.value;
                                    return AnimatedEntrance(
                                      index: index + 1,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: _buildSessionSetupCard(
                                          data: _DeviceSessionCardData(
                                            id: device.id,
                                            icon: Icons.bluetooth_rounded,
                                            transportLabel: 'BLE',
                                            name: device.name,
                                            subtitle: isIos
                                                ? 'Connected Device'
                                                : 'MAC: ${device.id}',
                                            onDisconnect: () async {
                                              await _handleDeviceDisconnect(
                                                deviceId: device.id,
                                                disconnect: () async {
                                                  await ref
                                                      .read(
                                                          bleRepositoryProvider)
                                                      .disconnectDevice(
                                                          device.id);
                                                  ref
                                                      .read(
                                                          sessionTargetProvider
                                                              .notifier)
                                                      .ensureDeselected(
                                                          device.id);
                                                },
                                              );
                                            },
                                          ),
                                          currentRunIds: runIds,
                                          currentLabelsById: currentLabelsById,
                                          busyDeviceIds: inUseDeviceIds,
                                          pendingStopDeviceIds:
                                              pendingBackendStopDeviceIds,
                                        ),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 16),
                                  if (connectedDevices.isNotEmpty) ...[
                                    _buildStartSessionButton(
                                      runIds: runIds,
                                      transport: target.transport,
                                      canStart: canStart,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  const SectionHeader(
                                      title: 'Available Bluetooth Devices'),
                                  scanResults.when(
                                    data: (list) {
                                      if (list.isEmpty)
                                        return const SizedBox(height: 0);
                                      final byId = <String, ScanResult>{};
                                      for (final result in list) {
                                        byId.putIfAbsent(
                                          result.device.remoteId.str,
                                          () => result,
                                        );
                                      }

                                      final connectedIdSet = connectedDevices
                                          .map((d) => d.id)
                                          .toSet();
                                      final deduped = byId.values
                                          .where((result) =>
                                              !connectedIdSet.contains(
                                                  result.device.remoteId.str))
                                          .where((result) {
                                        if (!hydrawaveOnly) return true;
                                        final expected =
                                            BleConstants.preferredServiceUuid;
                                        if (expected == null ||
                                            expected.isEmpty) {
                                          return false;
                                        }
                                        final targetUuid =
                                            BleConstants.normalizeUuid(
                                                expected);
                                        return result
                                            .advertisementData.serviceUuids
                                            .any(
                                          (uuid) =>
                                              BleConstants.normalizeUuid(
                                                  uuid.str) ==
                                              targetUuid,
                                        );
                                      }).toList();

                                      if (deduped.isEmpty) {
                                        return const _EmptyDashed(
                                          icon: Icons.bluetooth_rounded,
                                          title: 'No devices found',
                                          subtitle:
                                              'Make sure your device is turned on',
                                        );
                                      }

                                      return Column(
                                        children: deduped
                                            .asMap()
                                            .entries
                                            .map((entry) {
                                          final index = entry.key;
                                          final result = entry.value;
                                          final name = result.device
                                                  .platformName.isNotEmpty
                                              ? result.device.platformName
                                              : 'Unknown';
                                          final id = result.device.remoteId.str;
                                          final strictEnabled = BleConstants
                                                  .strictHydraGattProfile &&
                                              BleConstants
                                                      .preferredServiceUuid !=
                                                  null;
                                          final targetService = strictEnabled
                                              ? BleConstants.normalizeUuid(
                                                  BleConstants
                                                      .preferredServiceUuid!,
                                                )
                                              : null;
                                          final advertisedServices = result
                                              .advertisementData.serviceUuids
                                              .map((uuid) =>
                                                  BleConstants.normalizeUuid(
                                                      uuid.str));
                                          final uuidAllowed = !strictEnabled ||
                                              advertisedServices
                                                  .contains(targetService);

                                          return AnimatedEntrance(
                                            index: index + 1,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: _AvailableDeviceRow(
                                                icon: Icons.bluetooth_rounded,
                                                name: name,
                                                idText: isIos ? '' : id,
                                                buttonLabel:
                                                    connectingIds.contains(id)
                                                        ? 'Connecting...'
                                                        : 'Connect',
                                                isLoading:
                                                    connectingIds.contains(id),
                                                onTap: () async {
                                                  if (connectingIds
                                                      .contains(id)) return;
                                                  // Enforce the plan's concurrent-device
                                                  // limit before connecting another device.
                                                  if (deviceLimitReached) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Your plan allows $deviceLimit device(s) at a time. '
                                                          'Stop a device or upgrade your plan to run more.',
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  if (!uuidAllowed) {
                                                    final expectedUuid =
                                                        BleConstants
                                                            .preferredServiceUuid;
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          expectedUuid == null
                                                              ? 'Cannot connect: this device does not match the required Hydrawav profile.'
                                                              : 'Cannot connect: this device does not advertise the required Hydrawav service.',
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  }

                                                  ref
                                                      .read(
                                                          bleConnectingIdsProvider
                                                              .notifier)
                                                      .state = {
                                                    ...connectingIds,
                                                    id
                                                  };
                                                  final messenger =
                                                      ScaffoldMessenger.of(
                                                          context);

                                                  try {
                                                    final ok = await ref
                                                        .read(
                                                            bleRepositoryProvider)
                                                        .connectDevice(
                                                            result.device);

                                                    if (ok) {
                                                      await Future<
                                                          void>.delayed(
                                                        const Duration(
                                                            milliseconds: 150),
                                                      );
                                                      ref
                                                          .read(
                                                            sessionTargetProvider
                                                                .notifier,
                                                          )
                                                          .ensureSelected(id);
                                                      if (!mounted) return;
                                                      setState(() {
                                                        _runDeviceIds.add(id);
                                                        _excludedDeviceIds
                                                            .remove(id);
                                                      });
                                                    }

                                                    if (!context.mounted)
                                                      return;
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          ok
                                                              ? 'Connected to $name'
                                                              : 'Failed to connect to $name',
                                                        ),
                                                      ),
                                                    );
                                                  } finally {
                                                    final current = ref.read(
                                                        bleConnectingIdsProvider);
                                                    ref
                                                        .read(
                                                            bleConnectingIdsProvider
                                                                .notifier)
                                                        .state = {...current}
                                                      ..remove(id);
                                                  }
                                                },
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    },
                                    loading: () => const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 16),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      ),
                                    ),
                                    error: (e, _) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      child: Text(
                                        'Scan error: $e',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: ThemeConstants.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                            );
                          },
                          loading: () => const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                          ),
                          error: (e, _) => SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Failed to load paired devices',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ThemeConstants.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Room for the floating Start button and summary strip.
                      const SliverToBoxAdapter(child: SizedBox(height: 250)),
                    ],
                  ),
                ),
              ],
            ),
            // v6: music + Start float bottom-right over the summary strip.
            if (_showNewDesign)
              Positioned(
                left: side,
                right: side,
                bottom: 10,
                child: _planDock(
                  runIds: runIds,
                  transport: target.transport,
                  canStart: canStart,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentBtn extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SegmentBtn({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          // Web-parity: selected toggle segment is the dark slate, not the
          // tan accent (which is reserved for primary actions).
          color: active ? ThemeConstants.segmentActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color:
                        ThemeConstants.segmentActiveBg.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  active ? ThemeConstants.onNav : ThemeConstants.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active
                    ? ThemeConstants.onNav
                    : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends ConsumerWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ScanButton({
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();
    final scanning = ref.watch(isScanningProvider);
    return GestureDetector(
      onTap: scanning ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scanning
                ? ThemeConstants.accent.withValues(alpha: 0.45)
                : ThemeConstants.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh_rounded,
              size: 16,
              color: scanning
                  ? ThemeConstants.accent
                  : ThemeConstants.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              scanning ? 'Scanning...' : 'Scan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scanning
                    ? ThemeConstants.accent
                    : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copper handoff (`devCard`) rendering of [_SessionDeviceSetupCard] for the
/// university accountType. Same fields + callbacks — design only.
class _RefDeviceCard {
  final _SessionDeviceSetupCard w;
  const _RefDeviceCard(this.w);

  /// The v6 unit card (`.ry-ses-unit`): the tall USE switch and the unit's
  /// puck with LOCATE under them; name, ID and the protocol beside; then a
  /// row of round-ended controls. Every control calls the same callback the
  /// card always had.
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = PlanTones.dark(context);
    final armed = w.inUse && !w.isRunning;
    final compactId = w.subtitle
        .trim()
        .replaceFirst(RegExp(r'^(mac|id)\s*:\s*', caseSensitive: false), '');
    final copper = dark ? const Color(0xFFE2C0A2) : PlanTones.copper;
    final sub = PlanTones.sub(context);

    final List<BoxShadow> shadow = armed
        ? [
            BoxShadow(
              color: PlanTones.copper.withValues(alpha: dark ? .22 : .25),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: dark
                  ? const Color.fromRGBO(0, 0, 0, .65)
                  : const Color.fromRGBO(192, 157, 132, .5),
              blurRadius: dark ? 28 : 32,
              spreadRadius: dark ? -12 : -6,
              offset: Offset(0, dark ? 12 : 10),
            ),
          ]
        : [
            BoxShadow(
              color: dark
                  ? const Color.fromRGBO(0, 0, 0, .6)
                  : const Color.fromRGBO(192, 157, 132, .4),
              blurRadius: 26,
              spreadRadius: dark ? -12 : -6,
              offset: Offset(0, dark ? 10 : 8),
            ),
          ];

    // The protocol line. A running unit has no protocol of ours to show and
    // can't be edited.
    final Widget protocol = w.isRunning
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Running — controlled elsewhere',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: sub,
              ),
            ),
          )
        : PlanPress(
            onTap: w.onSelectProtocol,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROTOCOL:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.32,
                      color: sub,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          w.protocolTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: copper,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Icon(Icons.expand_more_rounded,
                            size: 16, color: sub),
                      ),
                    ],
                  ),
                  if (w.protocolSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      w.protocolSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: w.protocolTitle == 'Select protocol'
                            ? FontWeight.w400
                            : FontWeight.w700,
                        color:
                            w.protocolTitle == 'Select protocol' ? sub : copper,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: (w.inUse || w.isRunning || w.isPendingStop) ? 1 : 0.82,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: dark ? null : Colors.white,
          gradient: dark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF243240), Color(0xFF18222A)],
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: armed
                ? PlanTones.copper
                : (dark
                    ? const Color.fromRGBO(222, 179, 147, .28)
                    : PlanTones.cardBorder),
            width: 2,
          ),
          boxShadow: shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `.ry-ses-utop`
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // A running or stop-pending unit can't be toggled;
                            // its state chip sits in the row below instead.
                            PlanUseSwitch(
                              on: w.inUse,
                              onTap: (w.isRunning || w.isPendingStop)
                                  ? null
                                  : () => w.onToggleInUse(!w.inUse),
                            ),
                            const SizedBox(width: 6),
                            PlanPuck(on: armed || w.isRunning),
                          ],
                        ),
                        if (w.onLocate != null)
                          PlanLocatePill(onTap: w.onLocate!),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _UnitHead(name: w.name, id: compactId, bleId: w.bleId),
                        protocol,
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // `.ry-ses-uctl`
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: dark
                        ? const Color.fromRGBO(192, 157, 132, .2)
                        : PlanTones.hairline(context),
                  ),
                ),
              ),
              child: Row(
                children: [
                  PlanUnitButton(
                    icon: w.transportLabel == 'BLE'
                        ? Icons.bluetooth_disabled_rounded
                        : Icons.link_off_rounded,
                    tooltip: 'Disconnect',
                    onTap: w.onDisconnect,
                  ),
                  const SizedBox(width: 8),
                  PlanUnitButton(
                    icon: Icons.tune_rounded,
                    // sliders standing upright
                    iconTurns: 1,
                    tooltip: 'Advanced settings',
                    on: w.showAdvanced,
                    onTap: w.advancedEnabled ? w.onToggleAdvanced : null,
                  ),
                  if (w.isRunning) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _inUseChip(p, onTap: w.onTapInUse),
                    ),
                  ] else if (w.isPendingStop) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _pendingStopChip(p, onTap: w.onRetryStop),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: PlanDelayStepper(
                        seconds: w.startDelay,
                        onChanged: w.onChangeStartDelay,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // `.ry-ses-adv`
            if (w.showAdvanced && w.advancedChild != null)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: dark
                          ? const Color.fromRGBO(192, 157, 132, .2)
                          : PlanTones.hairline(context),
                    ),
                  ),
                ),
                child: w.advancedChild,
              ),
          ],
        ),
      ),
    );
  }

  /// "In use" chip shown in place of the Use toggle for a device that's
  /// already running, so it can't be added to a new session. Tappable —
  /// `_handleInUseTap` opens the owning session if one exists, else offers a
  /// force-release for a device stuck busy with nothing actually running it.
  Widget _inUseChip(RefPalette p, {VoidCallback? onTap}) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: p.copper.withValues(alpha: 0.14),
              border: Border.all(color: p.copper, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: p.copperInk),
                const SizedBox(width: 5),
                // Wraps rather than overflowing when space is tight
                // (a narrow phone, or a large system font size).
                Flexible(
                  child: Text(
                    'In use',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// Tappable chip shown in place of the Use toggle for a device whose local
  /// engine went terminal but the backend hasn't confirmed the stop —
  /// lightly adapted from [_inUseChip]: same pill shape, but tappable (opens
  /// the session screen to finish the stop) with a refresh icon instead of
  /// the lock, so it reads as actionable rather than locked.
  Widget _pendingStopChip(RefPalette p, {required VoidCallback? onTap}) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: p.copper.withValues(alpha: 0.14),
              border: Border.all(color: p.copper, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, size: 13, color: p.copperInk),
                const SizedBox(width: 5),
                // Wraps rather than overflowing when space is tight
                // (a narrow phone, or a large system font size).
                Flexible(
                  child: Text(
                    'Stop pending',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The unit's name, with the `ID` pill (`.v51-idbtn`) that reveals its
/// MAC / id underneath on demand.
class _UnitHead extends ConsumerStatefulWidget {
  final String name;
  final String id;

  /// BLE units only: the Bluetooth id their signal is read from.
  final String? bleId;
  const _UnitHead({required this.name, required this.id, this.bleId});

  @override
  ConsumerState<_UnitHead> createState() => _UnitHeadState();
}

class _UnitHeadState extends ConsumerState<_UnitHead> {
  bool _showId = false;

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final sub = PlanTones.sub(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color:
                      dark ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (widget.id.isNotEmpty) ...[
              const SizedBox(width: 7),
              Semantics(
                button: true,
                label: _showId ? 'Hide unit ID' : 'Show unit ID',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showId = !_showId),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 30,
                        constraints: const BoxConstraints(minWidth: 32),
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          gradient: _showId
                              ? const LinearGradient(colors: [
                                  Color(0xFFDEB393),
                                  Color(0xFFB27D5C),
                                ])
                              : null,
                          color: _showId
                              ? null
                              : (dark
                                  ? const Color.fromRGBO(255, 255, 255, .05)
                                  : const Color(0xFFF7F3F0)),
                          borderRadius: BorderRadius.circular(999),
                          border: _showId
                              ? null
                              : Border.all(
                                  color: dark
                                      ? const Color.fromRGBO(222, 179, 147, .2)
                                      : const Color.fromRGBO(26, 26, 26, .08),
                                ),
                        ),
                        // hugs its text (an `alignment` would stretch the
                        // badge to the 44px tap box)
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            'ID',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .5,
                              color: _showId
                                  ? PlanTones.copperText
                                  : (dark ? sub : const Color(0xFF9A918A)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (widget.bleId != null)
              Builder(builder: (context) {
                final rssi =
                    ref.watch(unitRssiProvider(widget.bleId!)).valueOrNull;
                if (rssi == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: '${signalOf(rssi).word} ($rssi dBm)',
                    child: SignalBars(signalOf(rssi).bars),
                  ),
                );
              }),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: const Cubic(.22, .61, .36, 1),
          alignment: Alignment.topLeft,
          child: _showId
              ? Text(
                  widget.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: sub,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SessionDeviceSetupCard extends StatelessWidget {
  final IconData icon;
  final String transportLabel;
  final String name;
  final String subtitle;
  final bool inUse;

  /// This device is in a LIVE session — grey the whole card (protocol, Use,
  /// Advanced are locked) and keep only Disconnect active, glowing.
  final bool isRunning;

  /// This device's local engine already went terminal, but the backend
  /// hasn't confirmed the stop (see `pendingBackendStopDeviceIdsProvider`).
  /// Mutually exclusive with [isRunning]. Unlike a running card, this one
  /// stays fully opaque and offers a tappable "Stop pending" chip instead of
  /// the Use toggle — tapping it opens the session screen so the
  /// practitioner can finish the stop from there.
  final bool isPendingStop;
  final VoidCallback? onRetryStop;

  /// Tap target for the locked "In use" chip itself (only set while
  /// [isRunning]) — opens the owning session if one exists, else offers to
  /// force the device back to available. See `_handleInUseTap`.
  final VoidCallback? onTapInUse;
  final String protocolTitle;
  final String protocolSubtitle;
  final bool showAdvanced;
  final bool advancedEnabled;
  final ValueChanged<bool> onToggleInUse;
  final VoidCallback? onSelectProtocol;
  final VoidCallback onDisconnect;
  final VoidCallback? onToggleAdvanced;
  final Widget? advancedChild;

  /// The unit's Advanced "Start Delay" (seconds), shown on the card's Delay
  /// stepper. [onChangeStartDelay] writes it back; null locks the stepper.
  final int startDelay;
  final ValueChanged<int>? onChangeStartDelay;

  /// University accountType renders the copper handoff design; all callbacks
  /// (protocol select, Use, Advanced, Disconnect) are identical.
  final bool refDesign;

  /// Opens the Locate popup for this (BLE-connected) device. When set, the
  /// header's transport pill ("BLE") is replaced by a tappable Locate
  /// button. Null hides the button and keeps the plain pill (e.g. WiFi
  /// units, which locate from the Devices Fleet screen instead).
  final VoidCallback? onLocate;

  /// BLE units: the Bluetooth id, for the signal bars in the header.
  final String? bleId;

  const _SessionDeviceSetupCard({
    required this.icon,
    required this.transportLabel,
    required this.name,
    required this.subtitle,
    required this.inUse,
    this.isRunning = false,
    this.isPendingStop = false,
    this.onRetryStop,
    this.onTapInUse,
    required this.protocolTitle,
    required this.protocolSubtitle,
    required this.showAdvanced,
    required this.advancedEnabled,
    required this.onToggleInUse,
    required this.onSelectProtocol,
    required this.onDisconnect,
    required this.onToggleAdvanced,
    required this.advancedChild,
    this.startDelay = 0,
    this.onChangeStartDelay,
    this.onLocate,
    this.bleId,
    this.refDesign = false,
  });

  @override
  Widget build(BuildContext context) {
    if (refDesign) return _RefDeviceCard(this).build(context);
    final secondaryColor =
        inUse ? ThemeConstants.textSecondary : ThemeConstants.textTertiary;
    final cardBorderColor = inUse
        ? ThemeConstants.accent.withValues(alpha: 0.2)
        : ThemeConstants.border;
    final compactDeviceId = subtitle
        .trim()
        .replaceFirst(RegExp(r'^(mac|id)\s*:\s*', caseSensitive: false), '');

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: inUse ? 1 : 0.74,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: ThemeConstants.surfaceVariant,
                                borderRadius: BorderRadius.circular(9),
                                border:
                                    Border.all(color: ThemeConstants.border),
                              ),
                              child: Icon(
                                icon,
                                color: ThemeConstants.textPrimary,
                                size: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: ThemeConstants.textPrimary,
                                        height: 1,
                                      ),
                                    ),
                                    if (compactDeviceId.isNotEmpty)
                                      TextSpan(
                                        text: ' ($compactDeviceId)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: secondaryColor,
                                          height: 1,
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Opacity(
                opacity: isRunning ? 0.5 : 1,
                child: InkWell(
                  onTap: isRunning ? null : onSelectProtocol,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color:
                          ThemeConstants.surfaceVariant.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: inUse
                            ? ThemeConstants.border
                            : ThemeConstants.border.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: 17,
                          color: inUse
                              ? ThemeConstants.accent
                              : ThemeConstants.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            protocolTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ThemeConstants.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: ThemeConstants.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: isRunning
                        // Already running — NOT part of the next Start batch.
                        // Show a locked "Running" chip instead of the Use toggle
                        // (start/stop is managed from the Session screen), so the
                        // running device can never block starting a new one.
                        ? Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: ThemeConstants.success
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: ThemeConstants.success
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.play_circle_rounded,
                                    size: 15, color: ThemeConstants.success),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    'Running',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeConstants.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : isPendingStop
                            ? Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: onRetryStop,
                                  child: Container(
                                    height: 34,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: ThemeConstants.accent
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: ThemeConstants.accent
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.refresh_rounded,
                                            size: 15,
                                            color: ThemeConstants.accent),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            'Stop pending',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: ThemeConstants.accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                height: 34,
                                padding:
                                    const EdgeInsets.only(left: 8, right: 2),
                                decoration: BoxDecoration(
                                  color: inUse
                                      ? ThemeConstants.accent
                                          .withValues(alpha: 0.12)
                                      : ThemeConstants.surfaceVariant,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: inUse
                                        ? ThemeConstants.accent
                                            .withValues(alpha: 0.25)
                                        : ThemeConstants.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      inUse
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      size: 15,
                                      color: inUse
                                          ? ThemeConstants.accent
                                          : ThemeConstants.textTertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Use',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: inUse
                                              ? ThemeConstants.textPrimary
                                              : ThemeConstants.textTertiary,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 30,
                                      height: 22,
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: Switch.adaptive(
                                          value: inUse,
                                          activeColor: ThemeConstants.accent,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          onChanged: onToggleInUse,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 5,
                    child: Builder(
                      builder: (context) {
                        final chip = Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: advancedEnabled
                                ? ThemeConstants.accent.withValues(alpha: 0.12)
                                : ThemeConstants.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: advancedEnabled
                                  ? ThemeConstants.accent
                                      .withValues(alpha: 0.25)
                                  : ThemeConstants.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 15,
                                color: advancedEnabled
                                    ? ThemeConstants.accent
                                    : ThemeConstants.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Advanced',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: advancedEnabled
                                        ? ThemeConstants.textPrimary
                                        : ThemeConstants.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              // Enabled → expand/collapse chevron. Disabled →
                              // a lock to signal it's a premium/upgrade gate.
                              Icon(
                                advancedEnabled
                                    ? (showAdvanced
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded)
                                    : Icons.lock_outline_rounded,
                                size: 14,
                                color: advancedEnabled
                                    ? ThemeConstants.textSecondary
                                    : ThemeConstants.textTertiary,
                              ),
                            ],
                          ),
                        );

                        // Enabled: tap toggles the Advanced panel.
                        if (advancedEnabled) {
                          return InkWell(
                            onTap: onToggleAdvanced,
                            borderRadius: BorderRadius.circular(999),
                            child: chip,
                          );
                        }

                        // Disabled (greyed): tap pops an upgrade info bubble.
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showAdvancedUpgradeInfo(context),
                          child: chip,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: InkWell(
                      onTap: onDisconnect,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: ThemeConstants.surfaceVariant,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: ThemeConstants.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.link_off_rounded,
                              size: 15,
                              color: ThemeConstants.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Disconnect',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeConstants.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: !showAdvanced || advancedChild == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: advancedChild,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Info bubble shown when the greyed-out "Advanced" control is tapped: it's a
  /// premium feature, so prompt the user to upgrade their account.
  void _showAdvancedUpgradeInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => Dialog(
        backgroundColor: ThemeConstants.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: ThemeConstants.accent,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Advanced is a premium feature',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Upgrade your account to unlock advanced session settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: ThemeConstants.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.accent,
                    foregroundColor: ThemeConstants.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hot / cold pad tints (`.ry-ses-sl input.hot` / `.cold`).
const Color _kHotTint = Color(0xFFC0553B);
const Color _kColdTint = Color(0xFF3D6B94);

/// Advanced Settings for a normal protocol, in the v6 `.ry-ses-adv` layout:
/// vibration mode, the two pad-intensity nudges, then "More settings" with
/// the vibration range and the four switches. Start Delay lives on the unit
/// card's stepper, not here.
class _SessionAdvancedSettingsPanel extends StatelessWidget {
  final AdvancedSettings settings;
  final ValueChanged<AdvancedSettings> onChangeSettings;

  const _SessionAdvancedSettingsPanel({
    required this.settings,
    required this.onChangeSettings,
  });

  @override
  Widget build(BuildContext context) {
    const vibMaxHz = 230.0;
    const vibMinHz = 0.0;
    final dark = PlanTones.dark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        PlanModeSeg(
          options: const ['Off', 'Sweep', 'Single'],
          selected: settings.vibrationMode,
          onSelect: (mode) {
            if (mode == 'Off') {
              onChangeSettings(
                settings.copyWith(
                  vibrationMode: 'Off',
                  vibMin: 0,
                  vibMax: 1,
                  vibrationSweepMin: 0,
                  vibrationSweepMax: 1,
                ),
              );
              return;
            }
            onChangeSettings(settings.copyWith(vibrationMode: mode));
          },
        ),
        if (settings.vibrationMode == 'Single') ...[
          const SizedBox(height: 12),
          const PlanAdvLabel('Frequency'),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey(
              'single_vibration_hz_${settings.vibrationSingleHz.toStringAsFixed(0)}',
            ),
            initialValue: settings.vibrationSingleHz.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: TextStyle(
              color: dark ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Enter frequency (10-230)',
              hintStyle: TextStyle(color: PlanTones.sub(context)),
              filled: true,
              fillColor: PlanTones.fill(context),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              suffixText: 'Level',
              suffixStyle: TextStyle(
                color: PlanTones.sub(context),
                fontWeight: FontWeight.w700,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: PlanTones.hairline(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: PlanTones.hairline(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: PlanTones.copper, width: 1.5),
              ),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value) ?? 10;
              final clamped = parsed.clamp(10, 230).toDouble();
              if (clamped != settings.vibrationSingleHz) {
                onChangeSettings(
                  settings.copyWith(
                    vibrationSingleHz: clamped,
                    vibMin: clamped,
                    vibMax: clamped,
                    vibrationSweepMin: clamped,
                    vibrationSweepMax: clamped,
                  ),
                );
              }
            },
          ),
        ],
        const SizedBox(height: 12),
        // Hot / Cold intensity — each cycle scales independently off its own
        // protocol base value (SessionEngine.applyIndividualPercent); no
        // pooling/coupling between cycles. Range capped at ±10% — client
        // requirement, small-step fine tuning only.
        PlanAdjustSlider(
          label: 'Hot pad intensity',
          value: settings.hotPercent,
          tint: _kHotTint,
          onChanged: (v) => onChangeSettings(settings.copyWith(hotPercent: v)),
        ),
        const SizedBox(height: 10),
        PlanAdjustSlider(
          label: 'Cold pad intensity',
          value: settings.coldPercent,
          tint: _kColdTint,
          onChanged: (v) => onChangeSettings(settings.copyWith(coldPercent: v)),
        ),
        const SizedBox(height: 10),
        PlanMoreSettings(
          children: [
            if (settings.vibrationMode == 'Sweep') ...[
              PlanLevelSlider(
                label: 'Vibration min',
                value: settings.vibMin,
                min: vibMinHz,
                max: vibMaxHz - 1,
                divisions: (vibMaxHz - 1).toInt(),
                onChanged: (value) {
                  var newMin = value;
                  var newMax = settings.vibMax;
                  if (newMin >= newMax) {
                    newMax = (newMin + 1).clamp(1, vibMaxHz);
                  }
                  onChangeSettings(
                    settings.copyWith(
                      vibMin: newMin,
                      vibMax: newMax,
                      vibrationSweepMin: newMin,
                      vibrationSweepMax: newMax,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              PlanLevelSlider(
                label: 'Vibration max',
                value: settings.vibMax,
                min: vibMinHz + 1,
                max: vibMaxHz,
                divisions: (vibMaxHz - 1).toInt(),
                onChanged: (value) {
                  var newMax = value;
                  var newMin = settings.vibMin;
                  if (newMax <= newMin) {
                    newMin = (newMax - 1).clamp(0, vibMaxHz - 1);
                  }
                  onChangeSettings(
                    settings.copyWith(
                      vibMin: newMin,
                      vibMax: newMax,
                      vibrationSweepMin: newMin,
                      vibrationSweepMax: newMax,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            PlanToggleRow(
              label: 'Warm Opening Cycle',
              value: settings.cycle1Initiation,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(cycle1Initiation: value)),
            ),
            const SizedBox(height: 6),
            PlanToggleRow(
              label: 'Cool Closing Cycle',
              value: settings.cycle5Completion,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(cycle5Completion: value)),
            ),
            const SizedBox(height: 6),
            PlanToggleRow(
              label: 'Lights',
              value: settings.lights,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(lights: value)),
            ),
            const SizedBox(height: 6),
            PlanToggleRow(
              label: 'Flip Sun and Moon pad',
              value: settings.flipSettings,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(flipSettings: value)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Advanced Settings for a Protocol Plus run — deliberately minimal
/// (unlike [_SessionAdvancedSettingsPanel]'s full set): only the controls
/// that make sense as a session-wide choice carried across every
/// sub-protocol switch. No cycle1/cycle5, no vibration min/max, no hot/cold
/// drop — Plus derives all of that fresh from each sub-protocol itself (see
/// SessionEngine._advancedSettingsForProtocol). Start Delay (first
/// sub-protocol only) is set from the unit card's stepper.
class _ProtocolPlusAdvancedSettingsPanel extends StatelessWidget {
  final AdvancedSettings settings;
  final ValueChanged<AdvancedSettings> onChangeSettings;

  const _ProtocolPlusAdvancedSettingsPanel({
    required this.settings,
    required this.onChangeSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Same Off / Sweep / Single strip as a normal protocol, for a
        // matching look. Behaviour is unchanged: Sweep = vibration on (each
        // step's own range), Off = off. Single can't apply across a
        // sequence of protocols, so it shows but is disabled.
        PlanModeSeg(
          options: const ['Off', 'Sweep', 'Single'],
          disabled: const {'Single'},
          selected: settings.vibrationMode == 'Off' ? 'Off' : 'Sweep',
          onSelect: (mode) => onChangeSettings(
            settings.copyWith(vibrationMode: mode == 'Off' ? 'Off' : 'Sweep'),
          ),
        ),
        const SizedBox(height: 12),
        PlanAdjustSlider(
          label: 'Hot pad intensity',
          value: settings.hotPercent,
          tint: _kHotTint,
          onChanged: (v) => onChangeSettings(settings.copyWith(hotPercent: v)),
        ),
        const SizedBox(height: 10),
        PlanAdjustSlider(
          label: 'Cold pad intensity',
          value: settings.coldPercent,
          tint: _kColdTint,
          onChanged: (v) => onChangeSettings(settings.copyWith(coldPercent: v)),
        ),
        const SizedBox(height: 10),
        // Lights + flip under "More settings", as on a normal protocol.
        PlanMoreSettings(
          children: [
            PlanToggleRow(
              label: 'Lights',
              value: settings.lights,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(lights: value)),
            ),
            const SizedBox(height: 6),
            PlanToggleRow(
              label: 'Flip Sun and Moon pad',
              value: settings.flipSettings,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(flipSettings: value)),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvailableDeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String idText;
  final String buttonLabel;
  final bool isLoading;

  /// Device is already running in a live session (this phone / web / another
  /// phone). Selection is blocked and an "In use" badge replaces the button.
  final bool isInUse;

  /// The LOCAL engine already went terminal for this device, but the backend
  /// hasn't confirmed the stop yet (see `backendStopUnresolved`). Mutually
  /// exclusive with [isInUse] — this device has already left the busy set.
  /// Unlike "In use", this stays fully opaque and tappable: tapping opens the
  /// session screen so the practitioner can finish the stop from there.
  final bool isPendingStop;
  final VoidCallback? onTap;

  const _AvailableDeviceRow({
    required this.icon,
    required this.name,
    required this.idText,
    required this.buttonLabel,
    this.isLoading = false,
    this.isInUse = false,
    this.isPendingStop = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isInUse ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ThemeConstants.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ThemeConstants.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ThemeConstants.border),
              ),
              child: Icon(icon, color: ThemeConstants.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    idText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeConstants.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isInUse)
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: ThemeConstants.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: ThemeConstants.error.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'In use',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.error,
                    ),
                  ),
                ),
              )
            else if (isPendingStop)
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: ThemeConstants.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: ThemeConstants.accent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 14, color: ThemeConstants.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Stop pending',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ThemeConstants.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: isLoading ? null : onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: ThemeConstants.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ThemeConstants.border),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ThemeConstants.accent,
                          ),
                        )
                      : Text(
                          buttonLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDashed extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyDashed({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ThemeConstants.border.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 44, color: ThemeConstants.textTertiary),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: ThemeConstants.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  const _HeaderBtn({
    required this.icon,
    // ignore: unused_element_parameter
    this.label,
    required this.onTap,
    this.filled = false,
    // ignore: unused_element_parameter
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final foregroundColor =
        filled ? ThemeConstants.textPrimary : ThemeConstants.accent;
    final backgroundColor = enabled
        ? (filled
            ? ThemeConstants.accent
            : ThemeConstants.accent.withValues(alpha: 0.1))
        : ThemeConstants.surfaceVariant;
    final borderColor = enabled
        ? ThemeConstants.accent.withValues(alpha: 0.15)
        : ThemeConstants.border;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 10 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: filled && enabled ? null : Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: enabled ? foregroundColor : ThemeConstants.textTertiary,
                size: 20,
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color:
                        enabled ? foregroundColor : ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The Session Plan protocol picker in the v6 look (`devProtoSheet`):
/// search pill, the goal chips from the API, "Recently used" pills, then the
/// protocol rows with a SELECT pill. Same data, filtering and results as
/// before — pops the chosen protocol id.
class _ProtocolPicker extends ConsumerStatefulWidget {
  final String? currentId;
  const _ProtocolPicker({required this.currentId});

  @override
  ConsumerState<_ProtocolPicker> createState() => _ProtocolPickerState();
}

class _ProtocolPickerState extends ConsumerState<_ProtocolPicker> {
  String _query = '';
  String? _goalId;

  void _choose(String id) {
    ref.read(recentProtocolIdsProvider.notifier).recordUsed(id);
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final tablet = HwTablet.of(context);
    final goalTagsAsync = ref.watch(goalTagListProvider);
    final filteredAsync = ref.watch(protocolSelectionOptionsProvider(_goalId));
    final sub = PlanTones.sub(context);

    Widget rail(List<Widget> items, {double gap = 8}) => tablet
        ? Wrap(spacing: gap, runSpacing: gap, children: items)
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  items[i],
                ],
              ],
            ),
          );

    // Goal chips — straight from the API (active goals only).
    final goals = goalTagsAsync.when(
      loading: () => const SizedBox(
        height: 36,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(PlanTones.copper),
            ),
          ),
        ),
      ),
      error: (e, _) => Text(
        'Failed to load goals: $e',
        style: const TextStyle(color: ThemeConstants.error, fontSize: 12),
      ),
      data: (goalTags) => rail([
        _GoalPill(
          label: 'All',
          icon: Icons.auto_awesome_outlined,
          selected: _goalId == null,
          onTap: () => setState(() => _goalId = null),
        ),
        for (final goal in goalTags.where((g) => g.isActive))
          _GoalPill(
            label: goal.name,
            selected: _goalId == goal.id,
            onTap: () => setState(() => _goalId = goal.id),
          ),
      ]),
    );

    // Recently used — hidden while searching / filtering.
    Widget recents = const SizedBox.shrink();
    if (_query.isEmpty && _goalId == null) {
      final recentIds = ref.watch(recentProtocolIdsProvider);
      final allOptions =
          ref.watch(protocolSelectionOptionsProvider(null)).asData?.value ??
              const <ProtocolSelectionOption>[];
      final recentOptions = <ProtocolSelectionOption>[
        for (final id in recentIds)
          ...allOptions.where((p) => p.id == id).take(1),
      ];
      if (recentOptions.isNotEmpty) {
        recents = Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'RECENTLY USED',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.26,
                  color: sub,
                ),
              ),
              const SizedBox(height: 8),
              rail([
                for (final protocol in recentOptions)
                  _RecentPill(
                    label: protocol.templateName,
                    selected: protocol.id == widget.currentId,
                    locked: !protocol.active,
                    onTap: () => _choose(protocol.id),
                  ),
              ]),
            ],
          ),
        );
      }
    }

    final list = filteredAsync.when<Widget>(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(PlanTones.copper),
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Failed to load protocols: $e',
          style: const TextStyle(color: ThemeConstants.error),
          textAlign: TextAlign.center,
        ),
      ),
      data: (filtered) {
        // Search by protocol title only (not the description or goal name).
        final q = _query.toLowerCase();
        final rows = q.isEmpty
            ? [...filtered]
            : filtered
                .where((p) => p.templateName.toLowerCase().contains(q))
                .toList();
        rows.sort((a, b) => naturalCompare(a.templateName, b.templateName));
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No protocols found for this goal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: sub),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: PlanTones.hairline(context)),
              _ProtocolRow(
                protocol: rows[i],
                selected: rows[i].id == widget.currentId,
                onTap: () {
                  // Plan gating (web parity): locked protocols can't be
                  // selected.
                  if (!rows[i].active) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('This protocol isn\'t included in your plan.'),
                      ),
                    );
                    return;
                  }
                  _choose(rows[i].id);
                },
              ),
            ],
          ],
        );
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Don't pop the keyboard on open — they often just browse / use the
        // goal filter + recents without searching.
        PlanSearchField(
          hint: 'Search protocols…',
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        goals,
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 18),
            children: [recents, list],
          ),
        ),
      ],
    );
  }
}

/// `.ry-ses-pkcat` — a goal filter pill; filled copper when chosen.
class _GoalPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _GoalPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final fg = selected
        ? Colors.white
        : (dark ? const Color(0xFFE7D3C0) : const Color(0xFF3A2E24));
    return Semantics(
      button: true,
      selected: selected,
      child: PlanPress(
        onTap: onTap,
        scale: .95,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFC09D84)
                : (dark ? const Color(0xFF15171C) : PlanTones.card(context)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : (dark
                      ? const Color.fromRGBO(255, 255, 255, .1)
                      : const Color.fromRGBO(26, 26, 26, .08)),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-pkrecent button` — a recently used protocol; the one in use
/// carries a copper dot and border.
class _RecentPill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  const _RecentPill({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    return Opacity(
      opacity: locked ? .55 : 1,
      child: PlanPress(
        onTap: locked ? null : onTap,
        scale: .96,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38, maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? PlanTones.card(context)
                : (dark ? const Color(0xFF15171C) : const Color(0xFFF7F3F0)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? PlanTones.copper
                  : (dark
                      ? const Color.fromRGBO(255, 255, 255, .08)
                      : const Color.fromRGBO(26, 26, 26, .06)),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                Icon(Icons.lock_outline_rounded,
                    size: 13, color: PlanTones.sub(context)),
                const SizedBox(width: 6),
              ] else if (selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: PlanTones.copper,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: dark
                        ? const Color(0xFFF1E4D6)
                        : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ry-ses-pkrow` — icon tile, name + one line of detail, and the
/// SELECT / SELECTED / PLANS pill.
class _ProtocolRow extends StatelessWidget {
  final ProtocolSelectionOption protocol;
  final bool selected;
  final VoidCallback onTap;
  const _ProtocolRow({
    required this.protocol,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = PlanTones.dark(context);
    final locked = !protocol.active;
    final sub = PlanTones.sub(context);
    // The duration sits right after the name; the line under it carries the
    // description and goal.
    final minutes = protocol.totalDuration == null
        ? null
        : '${(protocol.totalDuration!.inSeconds / 60).round()} min';
    final detail = [
      if (protocol.description.trim().isNotEmpty) protocol.description.trim(),
      if (protocol.goalTagName?.isNotEmpty ?? false) protocol.goalTagName!,
    ].join(' · ');

    final Widget pill;
    if (locked) {
      pill = _pill(
        context,
        label: 'PLANS',
        icon: Icons.lock_outline_rounded,
        fg: sub,
        bg: dark ? const Color(0xFF15171C) : const Color(0xFFF7F3F0),
      );
    } else if (selected) {
      pill = _pill(context,
          label: 'SELECTED',
          fg: Colors.white,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC9A788), Color(0xFFA9825F)],
          ));
    } else {
      pill = _pill(
        context,
        label: 'SELECT',
        fg: dark ? const Color(0xFFE7D3C0) : PlanTones.warmInk,
        bg: PlanTones.fill(context),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Opacity(
        opacity: locked ? .6 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: PlanTones.copper.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    locked ? Icons.lock_outline_rounded : Icons.waves_rounded,
                    size: 18,
                    color:
                        dark ? const Color(0xFFE2C0A2) : PlanTones.copperDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: protocol.templateName),
                          if (minutes != null)
                            TextSpan(
                              text: '  ·  $minutes',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? const Color(0xFFE2C0A2)
                                    : PlanTones.copperDeep,
                              ),
                            ),
                        ]),
                        // Long names wrap to a third line before trimming.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: dark
                              ? const Color(0xFFF1E4D6)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: sub,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                pill,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    required Color fg,
    Color? bg,
    Gradient? gradient,
    IconData? icon,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: fg,
              ),
            ),
          ],
        ),
      );
}

class _DeviceSessionCardData {
  final String id;
  final IconData icon;
  final String transportLabel;
  final String name;
  final String subtitle;
  final Future<void> Function() onDisconnect;

  const _DeviceSessionCardData({
    required this.id,
    required this.icon,
    required this.transportLabel,
    required this.name,
    required this.subtitle,
    required this.onDisconnect,
  });
}

/// Builds one Session Plan unit card in its v6 design, for layout tests and
/// previews. The Session tab itself builds these through
/// `_buildSessionSetupCard`; this only exposes the same widget.
@visibleForTesting
Widget debugSessionUnitCard({
  required String name,
  String subtitle = 'MAC: 48:CA:43:B0:02:B1',
  bool inUse = true,
  bool isRunning = false,
  bool isPendingStop = false,
  String protocolTitle = 'Performance Activation',
  String protocolSubtitle = 'Performance & Readiness · 9 min',
  bool showAdvanced = false,
  int startDelay = 0,
  ValueChanged<int>? onChangeStartDelay,
  AdvancedSettings? advanced,
  bool protocolPlus = false,
  ValueChanged<AdvancedSettings>? onChangeAdvanced,
}) {
  final change = onChangeAdvanced ?? (_) {};
  return _SessionDeviceSetupCard(
    icon: Icons.bluetooth_rounded,
    transportLabel: 'BLE',
    name: name,
    subtitle: subtitle,
    inUse: inUse,
    isRunning: isRunning,
    isPendingStop: isPendingStop,
    onTapInUse: isRunning ? () {} : null,
    onRetryStop: isPendingStop ? () {} : null,
    protocolTitle: protocolTitle,
    protocolSubtitle: protocolSubtitle,
    showAdvanced: showAdvanced,
    advancedEnabled: true,
    onToggleInUse: (_) {},
    onSelectProtocol: () {},
    onDisconnect: () {},
    onToggleAdvanced: () {},
    advancedChild: advanced == null
        ? null
        : (protocolPlus
            ? _ProtocolPlusAdvancedSettingsPanel(
                settings: advanced, onChangeSettings: change)
            : _SessionAdvancedSettingsPanel(
                settings: advanced, onChangeSettings: change)),
    startDelay: startDelay,
    onChangeStartDelay: onChangeStartDelay,
    onLocate: () {},
    refDesign: true,
  );
}

/// Opens the Session Plan protocol picker, for tests and previews. The
/// Session tab opens it through `_pickProtocolId`; this is the same sheet.
@visibleForTesting
Future<String?> debugShowProtocolPicker(
  BuildContext context, {
  String? currentId,
  String? unitName,
}) {
  return showPlanSheet<String>(
    context,
    title: unitName == null ? 'Select protocol' : '$unitName · protocol',
    builder: (_) => _ProtocolPicker(currentId: currentId),
  );
}
