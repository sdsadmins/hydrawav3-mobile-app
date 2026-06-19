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
import '../../../ble/services/ble_scanner.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import '../../../session/services/protocol_plus_controller.dart';

final pairedDevicesProvider = StreamProvider((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

// autoConnectEnabledProvider + bleConnectingIdsProvider now live in
// ble/presentation/providers/auto_connect_provider.dart (shared app-wide with
// the AutoConnectManager).
final _hydrawaveOnlyProvider = StateProvider<bool>((ref) => true);

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  static const String _defaultProtocolTemplateName =
      'Deep-Tension Recovery Stack';

  final Map<String, String> _protocolIdByDeviceId = {};
  final Map<String, Protocol> _selectedProtocolByDeviceId = {};
  final Map<String, AdvancedSettings> _settingsByDeviceId = {};
  final Set<String> _runDeviceIds = <String>{};
  final Set<String> _excludedDeviceIds = <String>{};
  final Map<String, bool> _showAdvancedByDeviceId = {};
  String? _delayedDeviceId;
  bool _starting = false;
  bool _didInitializeAutoScan = false;
  bool _isSeedingDefaultProtocol = false;

  static const Map<int, int> _hotPwmToLevel = {
    0: 0,
    50: 1,
    55: 2,
    60: 3,
    65: 4,
    70: 5,
    75: 6,
    80: 7,
    85: 8,
    90: 9,
    95: 10,
    100: 11,
  };

  static const Map<int, int> _coldPwmToLevel = {
    0: 0,
    150: 1,
    160: 2,
    170: 3,
    180: 4,
    190: 5,
    200: 6,
    210: 7,
    220: 8,
    230: 9,
    240: 10,
    250: 11,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAutoScan());
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

  int _nearestLevel(int pwm, Map<int, int> map, int fallback) {
    if (map.containsKey(pwm)) return map[pwm]!;
    var bestKey = map.keys.first;
    var bestDiff = (pwm - bestKey).abs();
    for (final key in map.keys) {
      final diff = (pwm - key).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestKey = key;
      }
    }
    return map[bestKey] ?? fallback;
  }

  AdvancedSettings _advancedDefaultsFromProtocol(Protocol protocol) {
    final first = protocol.cycles.isNotEmpty ? protocol.cycles.first : null;
    final hotLevel =
        _nearestLevel(first?.hotPwm.toInt() ?? 70, _hotPwmToLevel, 5);
    final coldLevel =
        _nearestLevel(first?.coldPwm.toInt() ?? 190, _coldPwmToLevel, 5);

    return AdvancedSettings(
      lights: true,
      vibrationMode: 'Sweep',
      vibrationSweepMin: protocol.vibmin,
      vibrationSweepMax: protocol.vibmax,
      vibrationSingleHz: 100,
      cycle1Initiation: protocol.cycle1,
      cycle5Completion: protocol.cycle5,
      hotLevel: hotLevel,
      coldLevel: coldLevel,
      hotPack: false,
      coldPack: false,
      hotDrop: protocol.hotdrop,
      coldDrop: protocol.colddrop,
      vibMin: protocol.vibmin,
      vibMax: protocol.vibmax,
      startDelay: 0,
      flipSettings: false,
    );
  }

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

  Future<void> _handleDeviceDisconnect({
    required String deviceId,
    required Future<void> Function() disconnect,
  }) async {
    await disconnect();
    if (!mounted) return;
    setState(() => _clearDeviceSessionState(deviceId));
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
  }) async {
    String query = '';
    String? selectedGoalTagId;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Consumer(
              builder: (context, ref, _) {
                final goalTagsAsync = ref.watch(goalTagListProvider);
                final filteredProtocolsAsync = ref.watch(
                  protocolSelectionOptionsProvider(selectedGoalTagId),
                );

                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select protocol',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: ThemeConstants.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: Icon(
                              Icons.close_rounded,
                              color: ThemeConstants.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        autofocus: true,
                        onChanged: (value) =>
                            setSheetState(() => query = value.trim()),
                        style: TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search protocols...',
                          hintStyle: TextStyle(
                            color: ThemeConstants.textTertiary,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: ThemeConstants.textTertiary,
                          ),
                          filled: true,
                          fillColor: ThemeConstants.surfaceVariant
                              .withValues(alpha: 0.7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: ThemeConstants.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: ThemeConstants.border),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Filter by goal',
                        style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 38,
                        child: goalTagsAsync.when(
                          loading: () => const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (e, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Failed to load goals: $e',
                              style: const TextStyle(
                                color: ThemeConstants.error,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          data: (goalTags) {
                            final activeGoalTags = goalTags
                                .where((goal) => goal.isActive)
                                .toList();
                            return ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _GoalFilterChip(
                                    label: 'All',
                                    selected: selectedGoalTagId == null,
                                    onTap: () => setSheetState(
                                      () => selectedGoalTagId = null,
                                    ),
                                  ),
                                ),
                                ...activeGoalTags.map(
                                  (goal) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _GoalFilterChip(
                                      label: goal.name,
                                      selected: selectedGoalTagId == goal.id,
                                      onTap: () => setSheetState(
                                        () => selectedGoalTagId = goal.id,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Recently used protocols — quick access to the protocols
                      // you ran most recently (hidden while searching/filtering).
                      if (query.isEmpty && selectedGoalTagId == null)
                        Builder(
                          builder: (_) {
                            final recentIds =
                                ref.watch(recentProtocolIdsProvider);
                            if (recentIds.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final allOptions = ref
                                    .watch(
                                        protocolSelectionOptionsProvider(null))
                                    .asData
                                    ?.value ??
                                const <ProtocolSelectionOption>[];
                            final recentOptions = <ProtocolSelectionOption>[];
                            for (final id in recentIds) {
                              final match = allOptions.where((p) => p.id == id);
                              if (match.isNotEmpty) {
                                recentOptions.add(match.first);
                              }
                            }
                            if (recentOptions.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recently used',
                                  style: TextStyle(
                                    color: ThemeConstants.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Horizontal strip of protocol-style cards (same
                                // look as the protocol list below), not goal
                                // capsules.
                                SizedBox(
                                  height: 116,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: recentOptions.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (_, i) {
                                      final protocol = recentOptions[i];
                                      return SizedBox(
                                        width: 300,
                                        child: _recentProtocolCard(
                                          protocol,
                                          selected: protocol.id == currentId,
                                          onTap: () {
                                            ref
                                                .read(recentProtocolIdsProvider
                                                    .notifier)
                                                .recordUsed(protocol.id);
                                            Navigator.of(ctx).pop(protocol.id);
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            );
                          },
                        ),
                      Flexible(
                        child: filteredProtocolsAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          error: (e, _) => Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Failed to load protocols: $e',
                                style: const TextStyle(
                                    color: ThemeConstants.error),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          data: (filteredProtocols) {
                            final list = query.isEmpty
                                ? [...filteredProtocols]
                                : filteredProtocols.where((protocol) {
                                    final lowerQuery = query.toLowerCase();
                                    return protocol.templateName
                                            .toLowerCase()
                                            .contains(lowerQuery) ||
                                        protocol.description
                                            .toLowerCase()
                                            .contains(lowerQuery) ||
                                        (protocol.goalTagName ?? '')
                                            .toLowerCase()
                                            .contains(lowerQuery);
                                  }).toList();

                            list.sort((a, b) => a.templateName
                                .toLowerCase()
                                .compareTo(b.templateName.toLowerCase()));

                            if (list.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 24),
                                  child: Text(
                                    'No protocols found for this goal.',
                                    style: TextStyle(
                                      color: ThemeConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, index) {
                                final protocol = list[index];
                                final selected = protocol.id == currentId;
                                final meta = [
                                  if (protocol.goalTagName?.isNotEmpty ?? false)
                                    protocol.goalTagName!,
                                  if (protocol.totalDuration != null)
                                    protocol.totalDuration!.formatted,
                                ].join(' - ');

                                return InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () {
                                    ref
                                        .read(
                                            recentProtocolIdsProvider.notifier)
                                        .recordUsed(protocol.id);
                                    Navigator.of(ctx).pop(protocol.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? ThemeConstants.accent
                                              .withValues(alpha: 0.14)
                                          : ThemeConstants.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? ThemeConstants.accent
                                            : ThemeConstants.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          selected
                                              ? Icons.check_circle_rounded
                                              : Icons.science_outlined,
                                          size: 18,
                                          color: selected
                                              ? ThemeConstants.accent
                                              : ThemeConstants.textTertiary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                protocol.templateName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: ThemeConstants
                                                      .textPrimary,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              if (protocol
                                                  .description.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                    protocol.description,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: ThemeConstants
                                                          .textSecondary,
                                                      fontSize: 12,
                                                      height: 1.25,
                                                    ),
                                                  ),
                                                ),
                                              if (meta.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                    meta,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: ThemeConstants
                                                          .textSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// A "Recently used" entry rendered with the SAME card styling as the main
  /// protocol list (icon, name, description, "goal - duration" meta) instead of
  /// the old goal-tag capsule.
  Widget _recentProtocolCard(
    ProtocolSelectionOption protocol, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final meta = [
      if (protocol.goalTagName?.isNotEmpty ?? false) protocol.goalTagName!,
      if (protocol.totalDuration != null) protocol.totalDuration!.formatted,
    ].join(' - ');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.14)
              : ThemeConstants.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.science_outlined,
              size: 18,
              color: selected
                  ? ThemeConstants.accent
                  : ThemeConstants.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    protocol.templateName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (protocol.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        protocol.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  if (meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ThemeConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeProtocolTemplateName(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  ProtocolSelectionOption? _findDefaultProtocolOption(
    List<ProtocolSelectionOption> protocols,
  ) {
    final normalizedDefault =
        _normalizeProtocolTemplateName(_defaultProtocolTemplateName);

    for (final protocol in protocols) {
      final normalizedTemplate =
          _normalizeProtocolTemplateName(protocol.templateName);
      // Use `contains` so a leading numbering prefix (e.g. "1. ") in the
      // backend template name doesn't prevent the default match.
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

    final defaultProtocol = _findDefaultProtocolOption(protocols);
    if (defaultProtocol == null) return;

    _isSeedingDefaultProtocol = true;
    try {
      final detailedProtocol =
          await ref.read(protocolDetailProvider(defaultProtocol.id).future);
      if (!mounted) return;

      setState(() {
        for (final deviceId in missingDeviceIds) {
          if (_protocolIdByDeviceId.containsKey(deviceId) &&
              _selectedProtocolByDeviceId.containsKey(deviceId) &&
              _settingsByDeviceId.containsKey(deviceId)) {
            continue;
          }

          _protocolIdByDeviceId[deviceId] = detailedProtocol.id;
          _selectedProtocolByDeviceId[deviceId] = detailedProtocol;
          _settingsByDeviceId[deviceId] =
              _advancedDefaultsFromProtocol(detailedProtocol);
          _showAdvancedByDeviceId.putIfAbsent(deviceId, () => false);
        }
      });
    } finally {
      _isSeedingDefaultProtocol = false;
    }
  }

  Future<void> _selectProtocolForDevice(String deviceId) async {
    final picked = await _pickProtocolId(
      currentId: _protocolIdByDeviceId[deviceId],
    );
    if (!mounted || picked == null) return;

    try {
      final protocol = await ref.read(protocolDetailProvider(picked).future);
      if (!mounted) return;
      setState(() {
        _protocolIdByDeviceId[deviceId] = picked;
        _selectedProtocolByDeviceId[deviceId] = protocol;
        _settingsByDeviceId[deviceId] = _advancedDefaultsFromProtocol(protocol);
        _showAdvancedByDeviceId[deviceId] = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load protocol details: $e')),
      );
    }
  }

  Future<void> _startSession({
    required List<String> runIds,
    required SessionTransport transport,
  }) async {
    final busyDevices =
        ref.read(activeSessionsProvider.notifier).getBusyDevices();
    final conflictingDevices =
        runIds.where((deviceId) => busyDevices.contains(deviceId)).toList();

    if (conflictingDevices.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot start session. Devices already in use: ${conflictingDevices.join(", ")}',
          ),
          backgroundColor: ThemeConstants.error,
        ),
      );
      return;
    }

    setState(() => _starting = true);

    try {
      final selectedProtocolIds =
          runIds.map((id) => _protocolIdByDeviceId[id]!).toSet();
      final fullProtocolById = <String, Protocol>{};

      await Future.wait(
        selectedProtocolIds.map((protocolId) async {
          final detailed =
              await ref.read(protocolDetailProvider(protocolId).future);
          fullProtocolById[protocolId] = detailed;
        }),
      );

      final effectiveDelayedDeviceId =
          _delayedDeviceId != null && runIds.contains(_delayedDeviceId)
              ? _delayedDeviceId
              : null;

      // One launcher handles any mix of normal protocols and Protocol Plus
      // templates across all selected devices (auto-detected per device).
      final selections = [
        for (final id in runIds)
          SessionDeviceSelection(
            deviceId: id,
            protocol: fullProtocolById[_protocolIdByDeviceId[id]!]!,
            advanced: _settingsByDeviceId[id]!,
          ),
      ];

      await launchSession(
        ref,
        context,
        selections: selections,
        transport: transport == SessionTransport.wifi ? 'wifi' : 'ble',
        delayedDeviceId: effectiveDelayedDeviceId,
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

  Widget _buildStartSessionButton({
    required List<String> runIds,
    required SessionTransport transport,
    required bool canStart,
  }) {
    final enabled = !_starting && canStart;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: enabled
            ? () => _startSession(runIds: runIds, transport: transport)
            : null,
        icon: Icon(
          _starting ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
          size: 20,
        ),
        label: Text(_starting ? 'Starting...' : 'Start Session'),
        style: ElevatedButton.styleFrom(
          backgroundColor: ThemeConstants.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
          disabledForegroundColor: ThemeConstants.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
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
  }) {
    final isIncluded = _runDeviceIds.contains(data.id);
    final selectedProtocol = _selectedProtocolByDeviceId[data.id];
    final settings = _settingsByDeviceId[data.id];
    final showAdvanced = _showAdvancedByDeviceId[data.id] ?? false;
    final canEditAdvanced = isIncluded &&
        selectedProtocol != null &&
        // Protocol Plus runs a fixed server-driven sequence; advanced settings
        // don't apply, so the Advanced control is locked for it.
        !selectedProtocol.isProtocolPlus &&
        settings != null &&
        !busyDeviceIds.contains(data.id);
    final protocolMeta = selectedProtocol == null
        ? 'Pick a protocol before starting the session.'
        : [
            if (selectedProtocol.goalTagName?.isNotEmpty ?? false)
              selectedProtocol.goalTagName!,
            if (selectedProtocol.totalDuration != null)
              selectedProtocol.totalDuration!.formatted,
          ].join(' - ');

    return _SessionDeviceSetupCard(
      icon: data.icon,
      transportLabel: data.transportLabel,
      name: data.name,
      subtitle: data.subtitle,
      inUse: isIncluded,
      protocolTitle: selectedProtocol?.templateName ?? 'Select protocol',
      protocolSubtitle: protocolMeta,
      showAdvanced: showAdvanced,
      advancedEnabled: canEditAdvanced,
      onToggleInUse: (value) => _setDeviceIncluded(data.id, value),
      onSelectProtocol:
          isIncluded ? () => _selectProtocolForDevice(data.id) : null,
      onDisconnect: data.onDisconnect,
      onToggleAdvanced: canEditAdvanced
          ? () {
              setState(() {
                _showAdvancedByDeviceId[data.id] = !showAdvanced;
              });
            }
          : null,
      advancedChild: canEditAdvanced
          ? _SessionAdvancedSettingsPanel(
              settings: settings,
              selectedDeviceIds: currentRunIds,
              selectedDeviceLabelsById: currentLabelsById,
              delayedDeviceId: _delayedDeviceId,
              onChangeSettings: (updated) {
                setState(() => _settingsByDeviceId[data.id] = updated);
              },
              onChangeDelayedDeviceId: (deviceId) {
                setState(() => _delayedDeviceId = deviceId);
              },
            )
          : null,
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

    _syncVisibleSessionDevices(currentSessionDeviceIds);
    protocolOptionsAsync.whenData((protocols) {
      _seedDefaultProtocolForDevices(
        deviceIds: currentSessionDeviceIds,
        protocols: protocols,
      );
    });

    final runIds = currentSessionDeviceIds
        .where((id) => _runDeviceIds.contains(id))
        .toList();
    final busyDeviceIds =
        ref.read(activeSessionsProvider.notifier).getBusyDevices().toSet();
    final canStart = runIds.isNotEmpty &&
        runIds.every((id) =>
            _protocolIdByDeviceId.containsKey(id) &&
            _settingsByDeviceId.containsKey(id));

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: AnimatedEntrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Devices',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeConstants.textPrimary,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          _HeaderBtn(
                            icon: Icons.add_rounded,
                            filled: true,
                            onTap: () =>
                                context.push(RoutePaths.deviceRegister),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Manage your Hydrawav3 devices and start sessions',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: ThemeConstants.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
                    border: Border.all(color: ThemeConstants.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SegmentBtn(
                          active: target.transport == SessionTransport.ble,
                          icon: Icons.bluetooth_rounded,
                          label: 'Bluetooth',
                          onTap: () {
                            ref
                                .read(sessionTargetProvider.notifier)
                                .setTransport(SessionTransport.ble, ref);
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
                          active: target.transport == SessionTransport.wifi,
                          icon: Icons.wifi_rounded,
                          label: 'WiFi',
                          onTap: () => ref
                              .read(sessionTargetProvider.notifier)
                              .setTransport(SessionTransport.wifi, ref),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (target.transport == SessionTransport.ble) ...[
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ThemeConstants.border),
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
                                  activeColor: ThemeConstants.accent,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (value) => ref
                                      .read(_hydrawaveOnlyProvider.notifier)
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
                              .read(autoConnectEnabledProvider.notifier)
                              .setEnabled(!autoConnectEnabled);
                          if (!autoConnectEnabled) {
                            await _connectAllHydrawaveDevices(
                              bleScanResultsAsync: bleScanResultsAsync,
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
                            borderRadius: BorderRadius.circular(10),
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
                                    : ThemeConstants.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Auto-connect',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: autoConnectEnabled
                                      ? ThemeConstants.textPrimary
                                      : ThemeConstants.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  _ScanButton(
                    visible: target.transport == SessionTransport.ble,
                    onTap: () => ref.read(startScanProvider)(),
                  ),
                ],
              ),
            ),
          ),
          if (target.transport == SessionTransport.wifi) ...[
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  );
                }
                if (wifiAsync.hasError && !wifiAsync.hasValue) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                      subtitle: 'Select a WiFi device below to configure it.',
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
                          padding: const EdgeInsets.only(bottom: 10),
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
                                        .disconnectDevice(device.macAddress);
                                    ref
                                        .read(sessionTargetProvider.notifier)
                                        .ensureDeselected(device.macAddress);
                                  },
                                );
                              },
                            ),
                            currentRunIds: runIds,
                            currentLabelsById: currentLabelsById,
                            busyDeviceIds: busyDeviceIds,
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
                  child: _buildStartSessionButton(
                    runIds: runIds,
                    transport: target.transport,
                    canStart: canStart,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: const SliverToBoxAdapter(
                child: SectionHeader(title: 'Available WiFi Devices'),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  );
                }
                if (wifiAsync.hasError && !wifiAsync.hasValue) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                      subtitle: 'Make sure your device is turned on',
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, index) {
                      final device = list[index];
                      final selected =
                          target.filteredDeviceIds.contains(device.macAddress);
                      return AnimatedEntrance(
                        index: index + 1,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AvailableDeviceRow(
                            icon: Icons.wifi_rounded,
                            name: device.name,
                            idText: device.macAddress,
                            buttonLabel: selected ? 'Selected' : 'Select',
                            onTap: () {
                              ref
                                  .read(sessionTargetProvider.notifier)
                                  .toggleDevice(device.macAddress);
                              setState(() {
                                if (selected) {
                                  _clearDeviceSessionState(device.macAddress);
                                } else {
                                  _runDeviceIds.add(device.macAddress);
                                  _excludedDeviceIds.remove(device.macAddress);
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
          if (target.transport == SessionTransport.ble) ...[
            pairedDevices.when(
              data: (devices) {
                final scanResults = ref.watch(bleScanResultsProvider);
                final connectedDevices =
                    devices.cast<PairedDevice>().where((d) {
                  if (provisioningIds.contains(d.id)) return false;
                  final state = ref.watch(bleDeviceStatusProvider(d.id));
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
                      ...connectedDevices.asMap().entries.map((entry) {
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
                                          .read(bleRepositoryProvider)
                                          .disconnectDevice(device.id);
                                      ref
                                          .read(sessionTargetProvider.notifier)
                                          .ensureDeselected(device.id);
                                    },
                                  );
                                },
                              ),
                              currentRunIds: runIds,
                              currentLabelsById: currentLabelsById,
                              busyDeviceIds: busyDeviceIds,
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
                      const SectionHeader(title: 'Available Bluetooth Devices'),
                      scanResults.when(
                        data: (list) {
                          if (list.isEmpty) return const SizedBox(height: 0);
                          final byId = <String, ScanResult>{};
                          for (final result in list) {
                            byId.putIfAbsent(
                              result.device.remoteId.str,
                              () => result,
                            );
                          }

                          final connectedIdSet =
                              connectedDevices.map((d) => d.id).toSet();
                          final deduped = byId.values
                              .where((result) => !connectedIdSet
                                  .contains(result.device.remoteId.str))
                              .where((result) {
                            if (!hydrawaveOnly) return true;
                            final expected = BleConstants.preferredServiceUuid;
                            if (expected == null || expected.isEmpty) {
                              return false;
                            }
                            final targetUuid =
                                BleConstants.normalizeUuid(expected);
                            return result.advertisementData.serviceUuids.any(
                              (uuid) =>
                                  BleConstants.normalizeUuid(uuid.str) ==
                                  targetUuid,
                            );
                          }).toList();

                          if (deduped.isEmpty) {
                            return const _EmptyDashed(
                              icon: Icons.bluetooth_rounded,
                              title: 'No devices found',
                              subtitle: 'Make sure your device is turned on',
                            );
                          }

                          return Column(
                            children: deduped.asMap().entries.map((entry) {
                              final index = entry.key;
                              final result = entry.value;
                              final name = result.device.platformName.isNotEmpty
                                  ? result.device.platformName
                                  : 'Unknown';
                              final id = result.device.remoteId.str;
                              final strictEnabled =
                                  BleConstants.strictHydraGattProfile &&
                                      BleConstants.preferredServiceUuid != null;
                              final targetService = strictEnabled
                                  ? BleConstants.normalizeUuid(
                                      BleConstants.preferredServiceUuid!,
                                    )
                                  : null;
                              final advertisedServices = result
                                  .advertisementData.serviceUuids
                                  .map((uuid) =>
                                      BleConstants.normalizeUuid(uuid.str));
                              final uuidAllowed = !strictEnabled ||
                                  advertisedServices.contains(targetService);

                              return AnimatedEntrance(
                                index: index + 1,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AvailableDeviceRow(
                                    icon: Icons.bluetooth_rounded,
                                    name: name,
                                    idText: isIos ? '' : id,
                                    buttonLabel: connectingIds.contains(id)
                                        ? 'Connecting...'
                                        : 'Connect',
                                    isLoading: connectingIds.contains(id),
                                    onTap: () async {
                                      if (connectingIds.contains(id)) return;
                                      if (!uuidAllowed) {
                                        final expectedUuid =
                                            BleConstants.preferredServiceUuid;
                                        ScaffoldMessenger.of(context)
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
                                              bleConnectingIdsProvider.notifier)
                                          .state = {...connectingIds, id};
                                      final messenger =
                                          ScaffoldMessenger.of(context);

                                      try {
                                        final ok = await ref
                                            .read(bleRepositoryProvider)
                                            .connectDevice(result.device);

                                        if (ok) {
                                          await Future<void>.delayed(
                                            const Duration(milliseconds: 150),
                                          );
                                          ref
                                              .read(
                                                sessionTargetProvider.notifier,
                                              )
                                              .ensureSelected(id);
                                          if (!mounted) return;
                                          setState(() {
                                            _runDeviceIds.add(id);
                                            _excludedDeviceIds.remove(id);
                                          });
                                        }

                                        if (!context.mounted) return;
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
                                        final current =
                                            ref.read(bleConnectingIdsProvider);
                                        ref
                                            .read(bleConnectingIdsProvider
                                                .notifier)
                                            .state = {...current}..remove(id);
                                      }
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
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
          SliverToBoxAdapter(
            child: SizedBox(
              height: currentSessionDeviceIds.isEmpty ? 28 : 124,
            ),
          ),
        ],
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

class _SessionDeviceSetupCard extends StatelessWidget {
  final IconData icon;
  final String transportLabel;
  final String name;
  final String subtitle;
  final bool inUse;
  final String protocolTitle;
  final String protocolSubtitle;
  final bool showAdvanced;
  final bool advancedEnabled;
  final ValueChanged<bool> onToggleInUse;
  final VoidCallback? onSelectProtocol;
  final VoidCallback onDisconnect;
  final VoidCallback? onToggleAdvanced;
  final Widget? advancedChild;

  const _SessionDeviceSetupCard({
    required this.icon,
    required this.transportLabel,
    required this.name,
    required this.subtitle,
    required this.inUse,
    required this.protocolTitle,
    required this.protocolSubtitle,
    required this.showAdvanced,
    required this.advancedEnabled,
    required this.onToggleInUse,
    required this.onSelectProtocol,
    required this.onDisconnect,
    required this.onToggleAdvanced,
    required this.advancedChild,
  });

  @override
  Widget build(BuildContext context) {
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
              InkWell(
                onTap: onSelectProtocol,
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.only(left: 8, right: 2),
                      decoration: BoxDecoration(
                        color: inUse
                            ? ThemeConstants.accent.withValues(alpha: 0.12)
                            : ThemeConstants.surfaceVariant,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: inUse
                              ? ThemeConstants.accent.withValues(alpha: 0.25)
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
                              inUse ? 'Use' : 'Use',
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

class _SessionAdvancedSettingsPanel extends StatelessWidget {
  final AdvancedSettings settings;
  final List<String> selectedDeviceIds;
  final Map<String, String> selectedDeviceLabelsById;
  final String? delayedDeviceId;
  final ValueChanged<AdvancedSettings> onChangeSettings;
  final ValueChanged<String?> onChangeDelayedDeviceId;

  const _SessionAdvancedSettingsPanel({
    required this.settings,
    required this.selectedDeviceIds,
    required this.selectedDeviceLabelsById,
    required this.delayedDeviceId,
    required this.onChangeSettings,
    required this.onChangeDelayedDeviceId,
  });

  @override
  Widget build(BuildContext context) {
    final isMulti = selectedDeviceIds.length >= 2;
    const vibMaxHz = 230.0;
    const vibMinHz = 0.0;

    Widget slider({
      required String label,
      required int value,
      required Color valueColor,
      required ValueChanged<int> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: 11,
            divisions: 11,
            activeColor: valueColor,
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      );
    }

    Widget smallNumberSlider({
      required String label,
      required double value,
      required double min,
      required double max,
      required int divisions,
      required Color color,
      required ValueChanged<double> onChanged,
      String? unit,
    }) {
      final clamped = value.clamp(min, max);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '${clamped.toStringAsFixed(0)}${unit ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: color,
            onChanged: onChanged,
          ),
        ],
      );
    }

    Widget toggle({
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: ThemeConstants.accent,
              activeTrackColor: ThemeConstants.accent.withValues(alpha: 0.35),
              onChanged: onChanged,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VIBRATION MODE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ThemeConstants.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Off', 'Sweep', 'Single'].map((mode) {
            final selected = settings.vibrationMode == mode;
            return InkWell(
              onTap: () {
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? ThemeConstants.accent.withValues(alpha: 0.18)
                      : ThemeConstants.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? ThemeConstants.accent
                        : ThemeConstants.border,
                  ),
                ),
                child: Text(
                  mode,
                  style: TextStyle(
                    color: selected
                        ? ThemeConstants.accent
                        : ThemeConstants.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (settings.vibrationMode == 'Sweep') ...[
          smallNumberSlider(
            label: 'Vibration Min',
            value: settings.vibMin,
            min: vibMinHz,
            max: vibMaxHz - 1,
            divisions: (vibMaxHz - 1).toInt(),
            color: ThemeConstants.accent,
            unit: 'Level',
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
          const SizedBox(height: 10),
          smallNumberSlider(
            label: 'Vibration Max',
            value: settings.vibMax,
            min: vibMinHz + 1,
            max: vibMaxHz,
            divisions: (vibMaxHz - 1).toInt(),
            color: ThemeConstants.accent,
            unit: 'Level',
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
        ],
        if (settings.vibrationMode == 'Single') ...[
          const SizedBox(height: 10),
          Text(
            'FREQUENCY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ThemeConstants.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
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
              color: ThemeConstants.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: 'Enter frequency (10-230)',
              hintStyle: TextStyle(color: ThemeConstants.textTertiary),
              filled: true,
              fillColor: ThemeConstants.surfaceVariant,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixText: 'Level',
              suffixStyle: TextStyle(
                color: ThemeConstants.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ThemeConstants.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ThemeConstants.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ThemeConstants.accent),
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
        if (settings.vibrationMode == 'Off') ...[
          const SizedBox(height: 8),
          Text(
            'Vibration is Off.',
            style: TextStyle(color: ThemeConstants.textSecondary),
          ),
        ],
        const SizedBox(height: 10),
        slider(
          label: 'Hot Pad Intensity',
          value: settings.hotLevel,
          valueColor: ThemeConstants.accent,
          onChanged: (value) => onChangeSettings(
              settings.copyWith(hotLevel: value, hotPack: true)),
        ),
        const SizedBox(height: 8),
        slider(
          label: 'Cold Pad Intensity',
          value: settings.coldLevel,
          valueColor: Colors.blueAccent,
          onChanged: (value) => onChangeSettings(
            settings.copyWith(coldLevel: value, coldPack: true),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Start Delay (seconds)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ThemeConstants.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('start_delay_${settings.startDelay}'),
          initialValue: settings.startDelay.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          style: TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: 'Enter seconds (0-60)',
            hintStyle: TextStyle(color: ThemeConstants.textTertiary),
            filled: true,
            fillColor: ThemeConstants.surfaceVariant,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixText: 'sec',
            suffixStyle: TextStyle(
              color: ThemeConstants.textSecondary,
              fontWeight: FontWeight.w700,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: ThemeConstants.accent),
            ),
          ),
          onChanged: (value) {
            final parsed = int.tryParse(value) ?? 0;
            final clamped = parsed.clamp(0, 60);
            if (clamped != settings.startDelay) {
              onChangeSettings(settings.copyWith(startDelay: clamped));
            }
          },
        ),
        if (isMulti && settings.startDelay > 0) ...[
          const SizedBox(height: 6),
          Text(
            'Delay which device?',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ThemeConstants.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedDeviceIds.map((id) {
              final selected = delayedDeviceId == id;
              final label = selectedDeviceLabelsById[id] ?? id;
              return InkWell(
                onTap: () => onChangeDelayedDeviceId(id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? ThemeConstants.accent.withValues(alpha: 0.18)
                        : ThemeConstants.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? ThemeConstants.accent
                          : ThemeConstants.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? ThemeConstants.accent
                          : ThemeConstants.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.6,
          ),
          children: [
            toggle(
              label: 'Cycle 1 Initialization',
              value: settings.cycle1Initiation,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(cycle1Initiation: value)),
            ),
            toggle(
              label: 'Cycle 5 Completion',
              value: settings.cycle5Completion,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(cycle5Completion: value)),
            ),
            toggle(
              label: 'LED',
              value: settings.lights,
              onChanged: (value) =>
                  onChangeSettings(settings.copyWith(lights: value)),
            ),
            toggle(
              label: 'Flip Pad',
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
  final VoidCallback onTap;

  const _AvailableDeviceRow({
    required this.icon,
    required this.name,
    required this.idText,
    required this.buttonLabel,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          GestureDetector(
            onTap: isLoading ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

class _GoalFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _GoalFilterChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.16)
              : ThemeConstants.surfaceVariant.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? ThemeConstants.accent : ThemeConstants.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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
