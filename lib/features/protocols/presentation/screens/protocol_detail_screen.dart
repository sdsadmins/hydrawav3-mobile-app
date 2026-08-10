import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../presets/data/preset_repository.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import '../../domain/protocol_model.dart';
import '../../domain/protocol_plus_model.dart';
import '../providers/protocol_provider.dart';
import '../providers/protocol_plus_detail_provider.dart';

class ProtocolDetailScreen extends ConsumerStatefulWidget {
  final String protocolId;
  const ProtocolDetailScreen({super.key, required this.protocolId});

  @override
  ConsumerState<ProtocolDetailScreen> createState() =>
      _ProtocolDetailScreenState();
}

class _ProtocolDetailScreenState extends ConsumerState<ProtocolDetailScreen> {
  bool _showAdvanced = false;
  bool _showSavePreset = false;
  AdvancedSettings _settings = const AdvancedSettings();
  final Map<String, AdvancedSettings> _settingsByDevice = {};
  String? _activeSettingsDeviceId;
  final Map<String, String> _protocolByDeviceId = {};
  String? _delayedDeviceId;
  String? _seededProtocolId;
  bool _startingFromDetail = false;

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

  int _nearestLevel(int pwm, Map<int, int> map, int fallback) {
    if (map.containsKey(pwm)) return map[pwm]!;
    int bestKey = map.keys.first;
    int bestDiff = (pwm - bestKey).abs();
    for (final k in map.keys) {
      final d = (pwm - k).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestKey = k;
      }
    }
    return map[bestKey] ?? fallback;
  }

  AdvancedSettings _advancedDefaultsFromProtocol(Protocol p) {
    final first = p.cycles.isNotEmpty ? p.cycles.first : null;
    final hotLevel =
        _nearestLevel(first?.hotPwm.toInt() ?? 70, _hotPwmToLevel, 5);
    final coldLevel =
        _nearestLevel(first?.coldPwm.toInt() ?? 190, _coldPwmToLevel, 5);

    return AdvancedSettings(
      lights: true,
      vibrationMode: 'Sweep',
      vibrationSweepMin: p.vibmin,
      vibrationSweepMax: p.vibmax,
      vibrationSingleHz: 100,
      cycle1Initiation: p.cycle1,
      cycle5Completion: p.cycle5,
      hotLevel: hotLevel,
      coldLevel: coldLevel,
      hotPack: false,
      coldPack: false,
      hotDrop: p.hotdrop,
      coldDrop: p.colddrop,
      vibMin: p.vibmin,
      vibMax: p.vibmax,
      startDelay: 0,
      flipSettings: false,
    );
  }

  void _seedAdvancedFromProtocol(Protocol p) {
    _settings = _advancedDefaultsFromProtocol(p);
    _settingsByDevice.clear();
    _protocolByDeviceId.clear();
    _activeSettingsDeviceId = null;
    _delayedDeviceId = null;
    _seededProtocolId = p.id;
  }

  /// The "Protocols in this Plus" section: lists each sub-protocol in run order
  /// with its own cycles / sessions / duration. [detail] is null until the
  /// populated sequence loads (shows a placeholder); if the payload carries ids
  /// only, it falls back to a simple count.
  Widget _buildPlusProtocols(ProtocolPlus? detail) {
    Widget shell(Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeConstants.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ThemeConstants.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_rounded,
                      size: 18, color: ThemeConstants.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Protocols in this Plus',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ThemeConstants.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        );

    if (detail == null) {
      return shell(
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading sequence…',
              style: TextStyle(
                fontSize: 13,
                color: ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final subs = detail.protocols;
    if (subs.isEmpty) {
      return shell(
        Text(
          '${detail.protocolCount} protocol(s) in this sequence.',
          style: TextStyle(
            fontSize: 13,
            color: ThemeConstants.textSecondary,
          ),
        ),
      );
    }

    return shell(
      Column(
        children: [
          for (var i = 0; i < subs.length; i++) ...[
            // A connector between consecutive protocols showing the switch
            // delay (the gap the device waits before starting the next one).
            if (i > 0) _delayConnector(detail.delay),
            _subProtocolTile(i + 1, subs[i]),
          ],
        ],
      ),
    );
  }

  /// Connector shown between two sub-protocols in the sequence: a vertical line
  /// aligned under the order badge, with a subtle chip stating the switch delay
  /// (the gap the device waits before the next protocol). Shows "Starts
  /// immediately" when there's no gap.
  Widget _delayConnector(int delaySeconds) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
      child: Row(
        children: [
          // 24px column keeps the dotted line centred under the 24px badge.
          SizedBox(
            width: 24,
            height: 26,
            child: Center(child: _dottedLine()),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: ThemeConstants.accent.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: ThemeConstants.accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.schedule_rounded,
                      size: 12, color: ThemeConstants.accent),
                ),
                const SizedBox(width: 7),
                Text(
                  delaySeconds > 0
                      ? '${_fmtDelay(delaySeconds)} switch delay'
                      : 'No delay',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.accent,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A dotted vertical line (Flutter has no built-in one) — a column of short
  /// dashes evenly spread over the connector height.
  Widget _dottedLine() => SizedBox(
        width: 3,
        height: 26,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            4,
            (_) => Container(
              width: 3,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeConstants.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );

  /// Compact delay label: "45s", "1m", or "1m 30s".
  String _fmtDelay(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  /// One row in the Protocol Plus sequence: order badge + name + compact
  /// cycles / sessions / duration figures.
  Widget _subProtocolTile(int order, Protocol sub) {
    Widget metric(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: ThemeConstants.textTertiary),
            const SizedBox(width: 3),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: ThemeConstants.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeConstants.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$order',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.templateName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    metric(Icons.repeat_rounded, '${sub.cycles.length} cycles'),
                    metric(Icons.play_circle_outline_rounded,
                        '${sub.sessions} sessions'),
                    metric(Icons.timer_outlined, sub.totalDuration.formatted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(protocolDetailProvider(widget.protocolId));
    final cardColor = Theme.of(context).brightness == Brightness.dark
        ? ThemeConstants.surface
        : Colors.white;
    final protocolsAsync = ref.watch(protocolListProvider);
    final target = ref.watch(sessionTargetProvider);
    final connectionStates = ref.watch(bleConnectionStatesProvider);
    final connectedIds = connectionStates.maybeWhen(
      data: (map) => map.entries
          .where((e) => e.value == BleConnectionStatus.connected)
          .map((e) => e.key)
          .toList(),
      orElse: () => const <String>[],
    );

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: Text('Protocol Details')),
      body: async.when(
        loading: () => const HwLoading(),
        error: (e, _) => HwErrorWidget(
            message: e.toString(),
            onRetry: () =>
                ref.invalidate(protocolDetailProvider(widget.protocolId))),
        data: (p) {
          final selectedTargetIds = target.deviceIds;
          if (_seededProtocolId != p.id) {
            // Reset advanced settings + per-device protocol assignments
            // when user navigates to a new protocol detail.
            _seedAdvancedFromProtocol(p);
          }

          // Seed per-device maps synchronously so the dropdown never needs protocol fallback.
          if (selectedTargetIds.isNotEmpty) {
            for (final id in selectedTargetIds) {
              _settingsByDevice.putIfAbsent(id, () => _settings);
              _protocolByDeviceId.putIfAbsent(id, () => p.id);
            }
            if (_activeSettingsDeviceId == null ||
                !selectedTargetIds.contains(_activeSettingsDeviceId)) {
              _activeSettingsDeviceId = selectedTargetIds.first;
            }
          }
          // A Protocol Plus has no cycles of its own; fetch its populated
          // sequence so we can show the SUMMED cycles/sessions and the list of
          // protocols inside it.
          final isPlus = p.isProtocolPlus;
          final plusDetail = isPlus
              ? ref.watch(protocolPlusDetailProvider(p.id)).asData?.value
              : null;
          final plusTotals =
              plusDetail != null ? protocolPlusTotals(plusDetail) : null;
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              AnimatedEntrance(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.templateName,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary,
                          letterSpacing: -0.3)),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(p.description,
                        style: TextStyle(
                            fontSize: 14,
                            color: ThemeConstants.textSecondary,
                            height: 1.5)),
                  ],
                ],
              )),
              const SizedBox(height: 16),
              AnimatedEntrance(
                  index: 1,
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    StatChip(
                        icon: Icons.timer_outlined,
                        value: p.totalDuration.formatted),
                    if (isPlus && plusDetail != null)
                      StatChip(
                          icon: Icons.layers_outlined,
                          value: '${plusDetail.protocolCount}',
                          label: 'protocols'),
                    // For a Plus these are summed across the sequence (null until
                    // the detail loads); a normal protocol uses its own counts.
                    StatChip(
                        icon: Icons.repeat_rounded,
                        value: isPlus
                            ? '${plusTotals?.cycles ?? '…'}'
                            : '${p.cycles.length}',
                        label: 'cycles'),
                    StatChip(
                        icon: Icons.play_circle_outline_rounded,
                        value: isPlus
                            ? '${plusTotals?.sessions ?? '…'}'
                            : '${p.sessions}',
                        label: 'sessions'),
                  ])),
              if (isPlus) ...[
                const SizedBox(height: 20),
                AnimatedEntrance(
                  index: 2,
                  child: _buildPlusProtocols(plusDetail),
                ),
              ],
              const SizedBox(height: 24),
              // AnimatedEntrance(
              //   index: 2,
              //   child: GradientCard(
              //     padding: const EdgeInsets.all(14),
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         Text(
              //           'Selected Devices',
              //           style: TextStyle(
              //             fontSize: 15,
              //             fontWeight: FontWeight.w700,
              //             color: Colors.black,
              //           ),
              //         ),
              //         const SizedBox(height: 8),
              //         Text(
              //           target.deviceIds.isEmpty
              //               ? 'No devices selected. Go to Devices screen and connect devices.'
              //               : '${target.deviceIds.length} selected (${target.transport.name.toUpperCase()})',
              //           style: TextStyle(
              //             fontSize: 12,
              //             color: ThemeConstants.textSecondary,
              //           ),
              //         ),
              //         if (target.deviceIds.isNotEmpty) ...[
              //           const SizedBox(height: 10),
              //           Wrap(
              //             spacing: 6,
              //             runSpacing: 6,
              //             children: target.deviceIds
              //                 .map(
              //                   (id) => Container(
              //                     padding: const EdgeInsets.symmetric(
              //                       horizontal: 8,
              //                       vertical: 5,
              //                     ),
              //                     decoration: BoxDecoration(
              //                       color: ThemeConstants.surfaceVariant,
              //                       borderRadius: BorderRadius.circular(8),
              //                     ),
              //                     child: Text(
              //                       id,
              //                       style: TextStyle(
              //                         fontSize: 11,
              //                         color: Colors.black,
              //                       ),
              //                     ),
              //                   ),
              //                 )
              //                 .toList(),
              //           ),
              //         ],
              //       ],
              //     ),
              //   ),
              // ),
              // const SizedBox(height: 16),
              // AnimatedEntrance(
              //   index: 3,
              //   child: GradientCard(
              //     gradientColors: [cardColor, cardColor],
              //     padding: const EdgeInsets.all(16),
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         Text(
              //           'Web Payload Mapping',
              //           style: TextStyle(
              //             fontSize: 15,
              //             fontWeight: FontWeight.w700,
              //             color: ThemeConstants.textPrimary,
              //           ),
              //         ),
              //         const SizedBox(height: 10),
              //         _R('Session Count', '${p.sessions}'),
              //         _R('Session Pause', '${p.sessionPause.toInt()}s'),
              //         _R('Cycle 1 (edge)', p.cycle1 ? 'enabled' : 'disabled'),
              //         _R('Cycle 5 (edge)', p.cycle5 ? 'enabled' : 'disabled'),
              //         _R('Edge Cycle Duration',
              //             '${p.edgecycleduration.toInt()}s'),
              //       ],
              //     ),
              //   ),
              // ),
              const SizedBox(height: 16),
              // AnimatedEntrance(
              //   index: 4,
              //   child: GradientCard(
              //     padding: const EdgeInsets.all(16),
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         InkWell(
              //           onTap: () =>
              //               setState(() => _showAdvanced = !_showAdvanced),
              //           child: Row(
              //             children: [
              //               Icon(
              //                 Icons.settings_rounded,
              //                 color: ThemeConstants.accent,
              //                 size: 20,
              //               ),
              //               const SizedBox(width: 10),
              //               const Expanded(
              //                 child: Text(
              //                   'Advanced Settings',
              //                   style: TextStyle(
              //                     fontSize: 15,
              //                     fontWeight: FontWeight.w700,
              //                     color: Colors.black,
              //                   ),
              //                 ),
              //               ),
              //               Icon(
              //                 _showAdvanced
              //                     ? Icons.keyboard_arrow_up_rounded
              //                     : Icons.keyboard_arrow_down_rounded,
              //                 color: ThemeConstants.textSecondary,
              //               ),
              //             ],
              //           ),
              //         ),
              //         AnimatedSize(
              //           duration: const Duration(milliseconds: 200),
              //           curve: Curves.easeOut,
              //           child: !_showAdvanced
              //               ? const SizedBox.shrink()
              //               : Padding(
              //                   padding: const EdgeInsets.only(top: 14),
              //                   child: Column(
              //                     crossAxisAlignment: CrossAxisAlignment.start,
              //                     children: [
              //                       if (target.deviceIds.length > 1) ...[
              //                         Text(
              //                           'Editing Settings For Device',
              //                           style: TextStyle(
              //                             color: ThemeConstants.textSecondary,
              //                             fontSize: 11,
              //                             fontWeight: FontWeight.w700,
              //                           ),
              //                         ),
              //                         const SizedBox(height: 8),
              //                         Wrap(
              //                           spacing: 8,
              //                           runSpacing: 8,
              //                           children: target.deviceIds.map((id) {
              //                             final active =
              //                                 id == _activeSettingsDeviceId;
              //                             return InkWell(
              //                               onTap: () => setState(
              //                                 () =>
              //                                     _activeSettingsDeviceId = id,
              //                               ),
              //                               child: Container(
              //                                 padding:
              //                                     const EdgeInsets.symmetric(
              //                                   horizontal: 10,
              //                                   vertical: 8,
              //                                 ),
              //                                 decoration: BoxDecoration(
              //                                   color: active
              //                                       ? ThemeConstants.accent
              //                                           .withValues(alpha: 0.18)
              //                                       : ThemeConstants
              //                                           .surfaceVariant,
              //                                   borderRadius:
              //                                       BorderRadius.circular(10),
              //                                   border: Border.all(
              //                                     color: active
              //                                         ? ThemeConstants.accent
              //                                         : ThemeConstants.border,
              //                                   ),
              //                                 ),
              //                                 child: Text(
              //                                   id,
              //                                   style: TextStyle(
              //                                     color: active
              //                                         ? ThemeConstants.accent
              //                                         : ThemeConstants
              //                                             .textSecondary,
              //                                     fontSize: 11,
              //                                     fontWeight: FontWeight.w700,
              //                                   ),
              //                                 ),
              //                               ),
              //                             );
              //                           }).toList(),
              //                         ),
              //                         const SizedBox(height: 12),
              //                         if (target.deviceIds.isNotEmpty)
              //                           protocolsAsync.when(
              //                             data: (protocols) {
              //                               final activeId =
              //                                   _activeSettingsDeviceId ??
              //                                       target.deviceIds.first;
              //                               final selectedPid =
              //                                   _protocolByDeviceId[activeId]!;
              //                               return Column(
              //                                 crossAxisAlignment:
              //                                     CrossAxisAlignment.start,
              //                                 children: [
              //                                   Text(
              //                                     'Protocol for device',
              //                                     style: TextStyle(
              //                                       color: ThemeConstants
              //                                           .textSecondary,
              //                                       fontSize: 11,
              //                                       fontWeight: FontWeight.w700,
              //                                     ),
              //                                   ),
              //                                   const SizedBox(height: 8),
              //                                   DropdownButton<String>(
              //                                     value: selectedPid,
              //                                     isExpanded: true,
              //                                     dropdownColor:
              //                                         ThemeConstants.surface,
              //                                     items: protocols.map((pr) {
              //                                       return DropdownMenuItem<
              //                                           String>(
              //                                         value: pr.id,
              //                                         child: Text(
              //                                           pr.templateName,
              //                                           overflow: TextOverflow
              //                                               .ellipsis,
              //                                           maxLines: 1,
              //                                           style: TextStyle(
              //                                             fontSize: 13,
              //                                             fontWeight:
              //                                                 FontWeight.w600,
              //                                           ),
              //                                         ),
              //                                       );
              //                                     }).toList(),
              //                                     onChanged: (newId) {
              //                                       if (newId == null) return;
              //                                       final newProtocol =
              //                                           protocols.firstWhere(
              //                                         (x) => x.id == newId,
              //                                       );
              //                                       setState(() {
              //                                         _protocolByDeviceId[
              //                                                 activeId] =
              //                                             newProtocol.id;
              //                                         _settingsByDevice[
              //                                                 activeId] =
              //                                             _advancedDefaultsFromProtocol(
              //                                                 newProtocol);
              //                                       });
              //                                     },
              //                                   ),
              //                                 ],
              //                               );
              //                             },
              //                             loading: () => const SizedBox(
              //                               height: 28,
              //                               width: 28,
              //                               child: CircularProgressIndicator(
              //                                 strokeWidth: 2,
              //                               ),
              //                             ),
              //                             error: (_, __) =>
              //                                 const SizedBox.shrink(),
              //                           ),
              //                         const SizedBox(height: 12),
              //                       ],
              //                       _AdvancedSettingsPanel(
              //                         protocolId: p.id,
              //                         selectedDeviceIds: target.deviceIds,
              //                         settings: _activeSettingsDeviceId != null
              //                             ? (_settingsByDevice[
              //                                     _activeSettingsDeviceId!] ??
              //                                 _settings)
              //                             : _settings,
              //                         delayedDeviceId: _delayedDeviceId,
              //                         showSavePreset: _showSavePreset,
              //                         onChangeSettings: (s) => setState(() {
              //                           _settings = s;
              //                           if (_activeSettingsDeviceId != null) {
              //                             _settingsByDevice[
              //                                 _activeSettingsDeviceId!] = s;
              //                           }
              //                         }),
              //                         onToggleSavePreset: () => setState(
              //                           () =>
              //                               _showSavePreset = !_showSavePreset,
              //                         ),
              //                         onChangeDelayedDeviceId: (id) => setState(
              //                           () => _delayedDeviceId = id,
              //                         ),
              //                       ),
              //                     ],
              //                   ),
              //                 ),
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
              // const SizedBox(height: 16),
              // AnimatedEntrance(
              //     index: 5, child: const SectionHeader(title: 'Cycles')),
              // ...p.cycles.asMap().entries.map((e) {
              //   final i = e.key;
              //   final c = e.value;
              //   return AnimatedEntrance(
              //       index: i + 6,
              //       child: Padding(
              //         padding: const EdgeInsets.only(bottom: 10),
              //         child: GradientCard(
              //             gradientColors: [cardColor, cardColor],
              //             padding: const EdgeInsets.all(16),
              //             child: Column(
              //               crossAxisAlignment: CrossAxisAlignment.start,
              //               children: [
              //                 Row(children: [
              //                   GlowIconBox(
              //                       icon: Icons.loop_rounded,
              //                       size: 36,
              //                       iconSize: 18),
              //                   const SizedBox(width: 12),
              //                   Text('Cycle ${i + 1} (C${i + 1})',
              //                       style: TextStyle(
              //                           fontSize: 15,
              //                           fontWeight: FontWeight.w600,
              //                           color: ThemeConstants.textPrimary)),
              //                 ]),
              //                 const SizedBox(height: 12),
              //                 _R('Duration (cycleDurations)',
              //                     '${c.durationSeconds.toInt()}s'),
              //                 _R('Repetitions (cycleRepetitions)',
              //                     '${c.repetitions}'),
              //                 _R(
              //                   'Pause Between Repetitions (pauseIntervals/cycle_pause)',
              //                   '${c.cyclePause.toInt()}s',
              //                 ),
              //                 _R(
              //                   'Pause After Cycle (cyclePauses/pause_seconds)',
              //                   '${c.pauseSeconds.toInt()}s',
              //                 ),
              //                 _R('Hot PWM', '${c.hotPwm.toInt()}'),
              //                 _R('Cold PWM', '${c.coldPwm.toInt()}'),
              //                 if (c.leftFunction.isNotEmpty)
              //                   _R('Left Function', c.leftFunction),
              //                 if (c.rightFunction.isNotEmpty)
              //                   _R('Right Function', c.rightFunction),
              //               ],
              //             )),
              //       ));
              // }),
              const SizedBox(height: 20),
              // AnimatedEntrance(
              //     index: p.cycles.length + 5,
              //     child: GestureDetector(
              //       onTap: () async {
              //         if (_startingFromDetail) return;
              //         setState(() => _startingFromDetail = true);
              //         try {
              //           // Prefer the user-selected transport + devices from Devices tab.
              //           final target = ref.read(sessionTargetProvider);
              //           appLogger.i(
              //             'ProtocolDetail: Start tapped '
              //             '(protocolId=${p.id}, name=${p.templateName}, sessions=${p.sessions}, cycles=${p.cycles.length})',
              //           );
              //           appLogger.i(
              //             'ProtocolDetail: Advanced snapshot '
              //             '(cycle1=${_settings.cycle1Initiation}, '
              //             'cycle5=${_settings.cycle5Completion}, '
              //             'led=${_settings.lights}, '
              //             'vibrationMode=${_settings.vibrationMode}, '
              //             'vibMin=${_settings.vibMin}, vibMax=${_settings.vibMax}, '
              //             'sweepMin=${_settings.vibrationSweepMin}, sweepMax=${_settings.vibrationSweepMax}, '
              //             'singleHz=${_settings.vibrationSingleHz}, '
              //             'flip=${_settings.flipSettings})',
              //           );
              //           if (target.deviceIds.isNotEmpty) {
              //             if (target.transport == SessionTransport.wifi) {
              //               // Publish first so device and in-app timer stay aligned
              //               // (session screen auto-starts the clock on open).
              //               try {
              //                 final dio = ref.read(djangoDioProvider);
              //                 // Resolve the protocol per selected device (web-parity).
              //                 final protocolIdsNeeded = target.deviceIds
              //                     .map((mac) => _protocolByDeviceId[mac]!)
              //                     .toSet();
              //                 final protocolById = <String, Protocol>{};
              //                 await Future.wait(
              //                     protocolIdsNeeded.map((pid) async {
              //                   final proto = pid == p.id
              //                       ? p
              //                       : await ref.read(
              //                           protocolDetailProvider(pid).future);
              //                   protocolById[pid] = proto;
              //                 }));
              //                 for (final mac in target.deviceIds) {
              //                   final perDeviceSettings =
              //                       _settingsByDevice[mac] ?? _settings;
              //                   final deviceProtocol =
              //                       protocolById[_protocolByDeviceId[mac]!] ??
              //                           (throw StateError(
              //                               'Missing protocol for $mac'));
              //                   final payloadObj = _protocolToWifiPayload(
              //                     deviceProtocol,
              //                     mac: mac,
              //                     advancedSettings: perDeviceSettings,
              //                     applyStartDelay:
              //                         perDeviceSettings.startDelay > 0,
              //                   );
              //                   final payloadStr = jsonEncode(payloadObj);
              //                   appLogger.i(
              //                     'WiFi: Publishing MQTT config (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
              //                   );
              //                   await dio.post(
              //                     ApiEndpoints.mqttPublish,
              //                     data: {
              //                       'topic': 'HydraWav3Pro/config',
              //                       'payload': payloadStr,
              //                     },
              //                   );
              //                 }
              //               } catch (e) {
              //                 appLogger.e('WiFi: publish failed: $e');
              //                 if (context.mounted) {
              //                   ScaffoldMessenger.of(context).showSnackBar(
              //                     SnackBar(
              //                       content: Text('WiFi publish failed: $e'),
              //                     ),
              //                   );
              //                 }
              //                 return;
              //               }
              //               if (!context.mounted) return;
              //               final sessionClockAnchorMs =
              //                   DateTime.now().millisecondsSinceEpoch;
              //               context.push(
              //                 RoutePaths.session,
              //                 extra: {
              //                   'protocolId': p.id,
              //                   'protocol': p,
              //                   'deviceIds': target.deviceIds,
              //                   'transport': 'wifi',
              //                   'sessionClockAnchorMs': sessionClockAnchorMs,
              //                   'advancedSettings': _settings,
              //                   'advancedSettingsByDevice': {
              //                     for (final id in target.deviceIds)
              //                       id: _settingsByDevice[id] ?? _settings,
              //                   },
              //                   'protocolByDeviceId': {
              //                     for (final id in target.deviceIds)
              //                       id: _protocolByDeviceId[id]!,
              //                   },
              //                   'delayedDeviceId': _delayedDeviceId,
              //                   'wifiConfigAlreadyPublished': true,
              //                 },
              //               );
              //               return;
              //             }

              //             // BLE selected
              //             // CRITICAL FIX: Check if selected devices are still connected
              //             final bleRepository = ref.read(bleRepositoryProvider);
              //             final connectedNow = target.deviceIds
              //                 .where((id) => bleRepository.isConnected(id))
              //                 .toList();

              //             if (connectedNow.isEmpty) {
              //               if (!context.mounted) return;
              //               ScaffoldMessenger.of(context).showSnackBar(
              //                 SnackBar(
              //                   content: Text(
              //                     'Selected BLE devices are not connected. ${target.deviceIds.length} device(s) selected but none are connected. '
              //                     'Please reconnect and try again.',
              //                   ),
              //                   duration: const Duration(seconds: 4),
              //                 ),
              //               );
              //               return;
              //             }

              //             if (connectedNow.length < target.deviceIds.length) {
              //               final disconnectedCount =
              //                   target.deviceIds.length - connectedNow.length;
              //               appLogger.w(
              //                 'Protocol: Starting with $disconnectedCount of ${target.deviceIds.length} BLE devices disconnected, '
              //                 'proceeding with ${connectedNow.length} connected device(s)',
              //               );
              //             }

              //             context.push(
              //               RoutePaths.session,
              //               extra: {
              //                 'protocolId': p.id,
              //                 'protocol': p,
              //                 'deviceIds': target.deviceIds,
              //                 'transport': 'ble',
              //                 'advancedSettings': _settings,
              //                 'advancedSettingsByDevice': {
              //                   for (final id in target.deviceIds)
              //                     id: _settingsByDevice[id] ?? _settings,
              //                 },
              //                 'protocolByDeviceId': {
              //                   for (final id in target.deviceIds)
              //                     id: _protocolByDeviceId[id]!,
              //                 },
              //                 'delayedDeviceId': _delayedDeviceId,
              //                 'wifiConfigAlreadyPublished': true,
              //               },
              //             );
              //             return;
              //           }

              //           final hasBle = connectedIds.isNotEmpty;

              //           // WiFi devices available from backend (MQTT/API path)
              //           List<DeviceInfo> wifiDevices = const <DeviceInfo>[];
              //           try {
              //             wifiDevices =
              //                 await ref.read(wifiDevicesByOrgProvider.future);
              //           } catch (_) {
              //             wifiDevices = const <DeviceInfo>[];
              //           }
              //           final hasWifi = wifiDevices.isNotEmpty;

              //           if (!hasBle && !hasWifi) {
              //             if (!context.mounted) return;
              //             ScaffoldMessenger.of(context).showSnackBar(
              //               const SnackBar(
              //                 content: Text(
              //                   'No BLE connected and no WiFi devices found.',
              //                 ),
              //               ),
              //             );
              //             return;
              //           }

              //           Future<void> startBle() async {
              //             final selected = await _pickConnectedDevices(
              //               context,
              //               connectedIds,
              //               p,
              //             );
              //             if (!context.mounted ||
              //                 selected == null ||
              //                 selected.isEmpty) {
              //               return;
              //             }

              //             // Ensure every selected device has an explicit protocol
              //             // mapping (no fallback).
              //             for (final id in selected) {
              //               if (!_protocolByDeviceId.containsKey(id)) {
              //                 _protocolByDeviceId[id] = p.id;
              //               }
              //             }

              //             // CRITICAL FIX: Re-verify devices are still connected after picker
              //             final bleRepository = ref.read(bleRepositoryProvider);
              //             final stillConnected = selected
              //                 .where((id) => bleRepository.isConnected(id))
              //                 .toList();

              //             if (stillConnected.isEmpty) {
              //               if (!context.mounted) return;
              //               ScaffoldMessenger.of(context).showSnackBar(
              //                 const SnackBar(
              //                   content: Text(
              //                     'Selected BLE devices disconnected. Please reconnect and try again.',
              //                   ),
              //                   duration: Duration(seconds: 3),
              //                 ),
              //               );
              //               return;
              //             }

              //             if (stillConnected.length < selected.length) {
              //               appLogger.w(
              //                 'Protocol: ${selected.length - stillConnected.length} BLE devices disconnected after picker, '
              //                 'proceeding with ${stillConnected.length} connected device(s)',
              //               );
              //             }

              //             context.push(
              //               RoutePaths.session,
              //               extra: {
              //                 'protocolId': p.id,
              //                 'protocol': p,
              //                 'deviceIds': selected,
              //                 'transport': 'ble',
              //                 'advancedSettings': _settings,
              //                 'advancedSettingsByDevice': {
              //                   for (final id in selected)
              //                     id: _settingsByDevice[id] ?? _settings,
              //                 },
              //                 'protocolByDeviceId': {
              //                   for (final id in selected)
              //                     id: _protocolByDeviceId[id]!,
              //                 },
              //                 'delayedDeviceId': _delayedDeviceId,
              //               },
              //             );
              //           }

              //           Future<void> startWifi() async {
              //             final selectedWifi =
              //                 await _pickWifiDevices(context, ref);
              //             if (!context.mounted ||
              //                 selectedWifi == null ||
              //                 selectedWifi.isEmpty) {
              //               return;
              //             }

              //             // Ensure every selected device has an explicit protocol
              //             // mapping (no fallback).
              //             for (final d in selectedWifi) {
              //               if (!_protocolByDeviceId
              //                   .containsKey(d.macAddress)) {
              //                 _protocolByDeviceId[d.macAddress] = p.id;
              //               }
              //             }

              //             try {
              //               final dio = ref.read(djangoDioProvider);
              //               // Resolve the protocol per selected WiFi device (web-parity).
              //               final protocolIdsNeeded = selectedWifi
              //                   .map((d) => _protocolByDeviceId[d.macAddress]!)
              //                   .toSet();
              //               final protocolById = <String, Protocol>{};
              //               await Future.wait(
              //                   protocolIdsNeeded.map((pid) async {
              //                 final proto = pid == p.id
              //                     ? p
              //                     : await ref
              //                         .read(protocolDetailProvider(pid).future);
              //                 protocolById[pid] = proto;
              //               }));

              //               // Backend expects payload as a STRINGIFIED OBJECT (not a list).
              //               // So we publish one request per device:
              //               // { topic: "...", payload: "{\"mac\":\"...\", ...}" }
              //               for (final d in selectedWifi) {
              //                 final perDeviceSettings =
              //                     _settingsByDevice[d.macAddress] ?? _settings;
              //                 final deviceProtocol = protocolById[
              //                         _protocolByDeviceId[d.macAddress]!] ??
              //                     (throw StateError(
              //                         'Missing protocol for ${d.macAddress}'));
              //                 final payloadObj = _protocolToWifiPayload(
              //                   deviceProtocol,
              //                   mac: d.macAddress,
              //                   advancedSettings: perDeviceSettings,
              //                   applyStartDelay:
              //                       perDeviceSettings.startDelay > 0,
              //                 );
              //                 final payloadStr = jsonEncode(payloadObj);
              //                 appLogger.i(
              //                   'WiFi: Publishing MQTT config (topic=HydraWav3Pro/config, mac=${d.macAddress}, payload=$payloadStr)',
              //                 );
              //                 final resp = await dio.post(
              //                   ApiEndpoints.mqttPublish,
              //                   data: {
              //                     'topic': 'HydraWav3Pro/config',
              //                     'payload': payloadStr,
              //                   },
              //                 );
              //                 appLogger.i(
              //                   'WiFi: MQTT publish OK (mac=${d.macAddress}, status=${resp.statusCode ?? 200})',
              //                 );
              //               }
              //             } on DioException catch (e) {
              //               appLogger.e(
              //                 'WiFi: MQTT publish failed '
              //                 '(status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
              //               );
              //               if (context.mounted) {
              //                 ScaffoldMessenger.of(context).showSnackBar(
              //                   SnackBar(
              //                     content: Text(
              //                       'WiFi publish failed: ${e.message ?? e.toString()}',
              //                     ),
              //                   ),
              //                 );
              //               }
              //               return;
              //             } catch (e) {
              //               appLogger.e('WiFi: MQTT publish failed: $e');
              //               if (context.mounted) {
              //                 ScaffoldMessenger.of(context).showSnackBar(
              //                   SnackBar(
              //                     content: Text('WiFi publish failed: $e'),
              //                   ),
              //                 );
              //               }
              //               return;
              //             }

              //             if (!context.mounted) return;
              //             final sessionClockAnchorMs =
              //                 DateTime.now().millisecondsSinceEpoch;
              //             context.push(
              //               RoutePaths.session,
              //               extra: {
              //                 'protocolId': p.id,
              //                 'protocol': p,
              //                 'deviceIds': selectedWifi
              //                     .map((d) => d.macAddress)
              //                     .toList(),
              //                 'transport': 'wifi',
              //                 'sessionClockAnchorMs': sessionClockAnchorMs,
              //                 'advancedSettings': _settings,
              //                 'advancedSettingsByDevice': {
              //                   for (final id
              //                       in selectedWifi.map((d) => d.macAddress))
              //                     id: _settingsByDevice[id] ?? _settings,
              //                 },
              //                 'protocolByDeviceId': {
              //                   for (final d in selectedWifi)
              //                     d.macAddress:
              //                         _protocolByDeviceId[d.macAddress]!,
              //                 },
              //                 'delayedDeviceId': _delayedDeviceId,
              //               },
              //             );
              //           }

              //           if (hasWifi && !hasBle) {
              //             await startWifi();
              //             return;
              //           }
              //           if (hasBle && !hasWifi) {
              //             await startBle();
              //             return;
              //           }

              //           // Both available → ask user which transport to use.
              //           final choice = await showModalBottomSheet<String>(
              //             context: context,
              //             showDragHandle: true,
              //             backgroundColor: ThemeConstants.surface,
              //             shape: RoundedRectangleBorder(
              //               borderRadius:
              //                   BorderRadius.vertical(top: Radius.circular(18)),
              //             ),
              //             builder: (ctx) => SafeArea(
              //               top: false,
              //               child: Padding(
              //                 padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              //                 child: Column(
              //                   mainAxisSize: MainAxisSize.min,
              //                   crossAxisAlignment: CrossAxisAlignment.start,
              //                   children: [
              //                     Text(
              //                       'Start session using',
              //                       style: TextStyle(
              //                         fontSize: 18,
              //                         fontWeight: FontWeight.w700,
              //                         color: Colors.black,
              //                       ),
              //                     ),
              //                     const SizedBox(height: 10),
              //                     ListTile(
              //                       leading: Icon(Icons.bluetooth_rounded,
              //                           color: Colors.black),
              //                       title: Text('Bluetooth (BLE)',
              //                           style: TextStyle(color: Colors.black)),
              //                       subtitle: Text(
              //                         '${connectedIds.length} connected',
              //                         style: TextStyle(
              //                           color: ThemeConstants.textSecondary,
              //                         ),
              //                       ),
              //                       onTap: () => Navigator.of(ctx).pop('ble'),
              //                     ),
              //                     ListTile(
              //                       leading: Icon(Icons.wifi_rounded,
              //                           color: Colors.black),
              //                       title: Text('WiFi (MQTT/API)',
              //                           style: TextStyle(color: Colors.black)),
              //                       subtitle: Text(
              //                         '${wifiDevices.length} available',
              //                         style: TextStyle(
              //                           color: ThemeConstants.textSecondary,
              //                         ),
              //                       ),
              //                       onTap: () => Navigator.of(ctx).pop('wifi'),
              //                     ),
              //                   ],
              //                 ),
              //               ),
              //             ),
              //           );

              //           if (!context.mounted || choice == null) return;
              //           if (choice == 'wifi') {
              //             await startWifi();
              //           } else {
              //             await startBle();
              //           }
              //         } finally {
              //           if (mounted) {
              //             setState(() => _startingFromDetail = false);
              //           }
              //         }
              //       },
              //       child: Container(
              //         height: 56,
              //         decoration: BoxDecoration(
              //           color: ThemeConstants.accent,
              //           borderRadius: BorderRadius.circular(14),
              //           boxShadow: [
              //             BoxShadow(
              //                 color:
              //                     ThemeConstants.accent.withValues(alpha: 0.3),
              //                 blurRadius: 16,
              //                 offset: const Offset(0, 4))
              //           ],
              //         ),
              //         child: _startingFromDetail
              //             ? const SizedBox(
              //                 height: 18,
              //                 width: 18,
              //                 child: CircularProgressIndicator(strokeWidth: 2),
              //               )
              //             : const Row(
              //                 mainAxisAlignment: MainAxisAlignment.center,
              //                 children: [
              //                     Icon(Icons.play_arrow_rounded,
              //                         color: Colors.black, size: 22),
              //                     SizedBox(width: 8),
              //                     Text('Start Session',
              //                         style: TextStyle(
              //                             color: Colors.black,
              //                             fontSize: 16,
              //                             fontWeight: FontWeight.w600)),
              //                   ]),
              //       ),
              //     )),
            ],
          );
        },
      ),
    );
  }
}

Future<List<DeviceInfo>?> _pickWifiDevices(
  BuildContext context,
  WidgetRef ref,
) async {
  final async = await ref.read(wifiDevicesByOrgProvider.future);
  if (async.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No WiFi devices found for your organization')),
      );
    }
    return null;
  }

  final Set<String> selectedMacs = <String>{};
  return showModalBottomSheet<List<DeviceInfo>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ThemeConstants.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.85,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select WiFi devices',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These are backend-registered sensors (MQTT/API).',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: async.length,
                        itemBuilder: (ctx, i) {
                          final d = async[i];
                          final key = d.macAddress;
                          final checked = selectedMacs.contains(key);
                          return CheckboxListTile(
                            value: checked,
                            activeColor: ThemeConstants.accent,
                            checkColor: Colors.black,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              d.name,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              d.macAddress,
                              style: TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            onChanged: (v) {
                              setSheetState(() {
                                if (v == true) {
                                  selectedMacs.add(key);
                                } else {
                                  selectedMacs.remove(key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedMacs.isEmpty
                            ? null
                            : () {
                                final picked = async
                                    .where((d) =>
                                        selectedMacs.contains(d.macAddress))
                                    .toList();
                                Navigator.of(ctx).pop(picked);
                              },
                        child: Text(
                          selectedMacs.length <= 1
                              ? 'Send to selected device'
                              : 'Send to ${selectedMacs.length} devices',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Map<String, dynamic> _protocolToWifiPayload(
  Protocol p, {
  required String mac,
  AdvancedSettings advancedSettings = const AdvancedSettings(),
  bool applyStartDelay = false,
}) {
  return _protocolToRs35Payload(
    p,
    mac: mac,
    advancedSettings: advancedSettings,
    applyStartDelay: applyStartDelay,
  );
}

Map<String, dynamic> _protocolToRs35Payload(
  Protocol p, {
  required String mac,
  required AdvancedSettings advancedSettings,
  required bool applyStartDelay,
}) {
  final cycles = p.cycles;

  // Intensity mapping from web sender (0–11).
  const hotMap = <int, int>{
    0: 0,
    1: 50,
    2: 55,
    3: 60,
    4: 65,
    5: 70,
    6: 75,
    7: 80,
    8: 85,
    9: 90,
    10: 95,
    11: 100,
  };
  const coldMap = <int, int>{
    0: 0,
    1: 150,
    2: 160,
    3: 170,
    4: 180,
    5: 190,
    6: 200,
    7: 210,
    8: 220,
    9: 230,
    10: 240,
    11: 250,
  };

  List<String> leftFuncs = cycles.map((c) => c.leftFunction).toList();
  List<String> rightFuncs = cycles.map((c) => c.rightFunction).toList();

  if (advancedSettings.flipSettings) {
    String flip(String fn) {
      if (fn.contains('HotRed')) return fn.replaceAll('HotRed', 'ColdBlue');
      if (fn.contains('ColdBlue')) return fn.replaceAll('ColdBlue', 'HotRed');
      return fn;
    }

    leftFuncs = leftFuncs.map(flip).toList();
    rightFuncs = rightFuncs.map(flip).toList();
  }

  final hotPwm = hotMap[advancedSettings.hotLevel.clamp(0, 11)] ?? 70;
  final coldPwm = coldMap[advancedSettings.coldLevel.clamp(0, 11)] ?? 190;
  final pwmHot = advancedSettings.hotPack
      ? cycles.map((_) => hotPwm).toList()
      : cycles.map((c) => c.hotPwm.toInt()).toList();
  final pwmCold = advancedSettings.coldPack
      ? cycles.map((_) => coldPwm).toList()
      : cycles.map((c) => c.coldPwm.toInt()).toList();

  final vibMode = advancedSettings.vibrationMode;
  final vibMin = switch (vibMode) {
    'Off' => 0,
    'Single' => advancedSettings.vibrationSingleHz.clamp(10, 230).toInt(),
    'Sweep' => advancedSettings.vibrationSweepMin.toInt(),
    _ => advancedSettings.vibMin.toInt(),
  };
  final vibMax = switch (vibMode) {
    'Off' => 0,
    'Single' =>
      (advancedSettings.vibrationSingleHz.clamp(10, 230).toInt() + 10),
    'Sweep' => advancedSettings.vibrationSweepMax.toInt(),
    _ => advancedSettings.vibMax.toInt(),
  };
  final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
    p,
    advancedSettings,
  );
  final totalDuration = _computeFirmwareTotalDurationSeconds(
    p,
    advancedSettings,
    applyStartDelay: applyStartDelay,
  );

  return {
    'mac': mac,
    'sessionCount': p.sessions,
    'sessionPause': p.sessionPause.toInt(),
    'sDelay': applyStartDelay ? advancedSettings.startDelay : 0,
    'cycle1': advancedSettings.cycle1Initiation ? 1 : 0,
    'cycle5': advancedSettings.cycle5Completion ? 1 : 0,
    'edgeCycleDuration': edgeCycleDuration,
    'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
    'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
    // Match web sender exactly.
    'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
    'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
    'leftFuncs': leftFuncs,
    'rightFuncs': rightFuncs,
    'pwmValues': {
      'hot': pwmHot,
      'cold': pwmCold,
    },
    'playCmd': 1,
    'led': advancedSettings.lights ? 1 : 0,
    'hotDrop': advancedSettings.hotDrop.toInt(),
    'coldDrop': advancedSettings.coldDrop.toInt(),
    'vibMin': vibMin,
    'vibMax': vibMax,
    'totalDuration': totalDuration,
  };
}

int _computeFirmwareTotalDurationSeconds(
  Protocol p,
  AdvancedSettings advancedSettings, {
  bool applyStartDelay = false,
}) {
  final cycles = p.cycles;
  if (cycles.length < 3) return p.totalDurationSeconds;

  final edgeCycleDuration = _effectiveEdgeCycleDurationSeconds(
    p,
    advancedSettings,
  );

  int total = applyStartDelay ? advancedSettings.startDelay : 0;

  if (advancedSettings.cycle1Initiation) {
    total += edgeCycleDuration + 30;
  }

  for (var session = 0; session < p.sessions; session++) {
    for (var i = 0; i < 3; i++) {
      final c = cycles[i];
      final reps = max(1, c.repetitions);
      total += reps * c.durationSeconds.toInt();
      total += (reps - 1) * c.pauseSeconds.toInt();

      if (i < 2) {
        total += c.cyclePause.toInt();
      }
    }

    if (session < p.sessions - 1) {
      total += p.sessionPause.toInt();
    }
  }

  if (advancedSettings.cycle5Completion) {
    total += 30 + edgeCycleDuration;
  }

  return total;
}

int _effectiveEdgeCycleDurationSeconds(
  Protocol p,
  AdvancedSettings advancedSettings,
) {
  return (advancedSettings.cycle1Initiation ||
          advancedSettings.cycle5Completion)
      ? 9
      : p.edgecycleduration.toInt();
}

Future<List<String>?> _pickConnectedDevices(
  BuildContext context,
  List<String> connectedIds,
  Protocol protocol,
) async {
  final Set<String> selectedIds = <String>{};
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ThemeConstants.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            top: false,
            child: FractionallySizedBox(
              heightFactor: 0.9,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select connected devices',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose one or more devices for this session.',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeConstants.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...connectedIds.map((id) {
                              final checked = selectedIds.contains(id);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: ThemeConstants.accent,
                                checkColor: Colors.black,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  id,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: ThemeConstants.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                onChanged: (v) {
                                  setSheetState(() {
                                    if (v == true) {
                                      selectedIds.add(id);
                                    } else {
                                      selectedIds.remove(id);
                                    }
                                  });
                                },
                              );
                            }),
                            const SizedBox(height: 8),
                            if (selectedIds.isNotEmpty) ...[
                              Text(
                                'Payload preview (first selected device):',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ThemeConstants.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ThemeConstants.surfaceVariant,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    final selectedTransportId =
                                        selectedIds.first;
                                    final gatt = ref
                                        .read(bleRepositoryProvider)
                                        .getGattInfo(selectedTransportId);
                                    final runtimeDeviceId = protocol.deviceId ??
                                        BleConstants.jsonDeviceIdForSession(
                                          bleTransportId: selectedTransportId,
                                          discoveredWriteCharacteristicUuid:
                                              gatt?.writeUuid,
                                        );
                                    return Text(
                                      const JsonEncoder.withIndent('  ')
                                          .convert(
                                        _protocolToSessionPayload(
                                          protocol,
                                          transportId: selectedTransportId,
                                          runtimeDeviceId: runtimeDeviceId,
                                        ),
                                      ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black,
                                        fontFamily: 'monospace',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedIds.isEmpty
                            ? null
                            : () => Navigator.of(ctx).pop(selectedIds.toList()),
                        child: Text(
                          selectedIds.length <= 1
                              ? 'Start with selected device'
                              : 'Start with ${selectedIds.length} devices',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Map<String, dynamic> _protocolToSessionPayload(
  Protocol p, {
  required String transportId,
  required String runtimeDeviceId,
}) {
  final cycles = p.cycles;
  return {
    'mac': transportId,
    'playCmd': 1,
    'sessionCount': p.sessions,
    'sessionPause': p.sessionPause.toInt(),
    'sDelay': 0,
    'cycle1': p.cycle1 ? 1 : 0,
    'cycle5': p.cycle5 ? 1 : 0,
    'edgeCycleDuration':
        (p.cycle1 || p.cycle5) ? 9 : p.edgecycleduration.toInt(),
    'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
    'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
    'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
    'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
    'leftFuncs': cycles.map((c) => c.leftFunction).toList(),
    'rightFuncs': cycles.map((c) => c.rightFunction).toList(),
    'pwmValues': {
      'hot': cycles.map((c) => c.hotPwm.toInt()).toList(),
      'cold': cycles.map((c) => c.coldPwm.toInt()).toList(),
    },
    'led': 1,
    'hotDrop': p.hotdrop.toInt(),
    'coldDrop': p.colddrop.toInt(),
    'vibMin': p.vibmin.toInt(),
    'vibMax': p.vibmax.toInt(),
    'totalDuration': p.totalDurationSeconds,
  };
}

class _R extends StatelessWidget {
  final String l, v;
  const _R(this.l, this.v);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Text(
                l,
                softWrap: true,
                style: TextStyle(
                  fontSize: 13,
                  color: ThemeConstants.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                v,
                softWrap: true,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeConstants.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

final _presetsProvider = FutureProvider<List<Preset>>((ref) async {
  final repo = ref.read(presetRepositoryProvider);
  return repo.getPresets();
});

class _AdvancedSettingsPanel extends ConsumerWidget {
  final String protocolId;
  final List<String> selectedDeviceIds;
  final AdvancedSettings settings;
  final String? delayedDeviceId;
  final bool showSavePreset;
  final ValueChanged<AdvancedSettings> onChangeSettings;
  final VoidCallback onToggleSavePreset;
  final ValueChanged<String?> onChangeDelayedDeviceId;

  const _AdvancedSettingsPanel({
    required this.protocolId,
    required this.selectedDeviceIds,
    required this.settings,
    required this.delayedDeviceId,
    required this.showSavePreset,
    required this.onChangeSettings,
    required this.onToggleSavePreset,
    required this.onChangeDelayedDeviceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMulti = selectedDeviceIds.length >= 2;
    final presetsAsync = ref.watch(_presetsProvider);

    const vibMaxHz = 230.0;
    const vibMinHz = 0.0;
    const dropMax = 10.0;

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
            onChanged: (v) => onChanged(v.round()),
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
      final v = value.clamp(min, max);
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
                '${v.toStringAsFixed(0)}${unit ?? ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          Slider(
            value: v,
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
                  color: Colors.black,
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
        // Vibration mode (web fields) — web order: vibration first.
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
          children: ['Off', 'Sweep', 'Single'].map((m) {
            final selected = settings.vibrationMode == m;
            return InkWell(
              onTap: () {
                if (m == 'Off') {
                  // Match web UI behavior: turning Off zeroes the sweep range,
                  // but preserves the last single-frequency value.
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
                onChangeSettings(settings.copyWith(vibrationMode: m));
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
                  m,
                  style: TextStyle(
                    color: selected ? ThemeConstants.accent : Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        if (settings.vibrationMode == 'Sweep') ...[
          smallNumberSlider(
            label: 'Vibration Min ',
            value: settings.vibMin,
            min: vibMinHz,
            max: vibMaxHz - 1,
            divisions: (vibMaxHz - 1).toInt(),
            color: ThemeConstants.accent,
            unit: 'Hz',
            onChanged: (v) {
              var newMin = v;
              var newMax = settings.vibMax;
              if (newMin >= newMax) newMax = (newMin + 1).clamp(1, vibMaxHz);
              onChangeSettings(
                settings.copyWith(
                  vibMin: newMin,
                  vibMax: newMax,
                  // Keep both representations in sync; web uses these in payload.
                  vibrationSweepMin: newMin,
                  vibrationSweepMax: newMax,
                ),
              );
            },
          ),
          smallNumberSlider(
            label: 'Vibration Max',
            value: settings.vibMax,
            min: vibMinHz + 1,
            max: vibMaxHz,
            divisions: vibMaxHz.toInt(),
            color: ThemeConstants.accent,
            unit: 'Level',
            onChanged: (v) {
              var newMax = v;
              var newMin = settings.vibMin;
              if (newMax <= newMin)
                newMin = (newMax - 1).clamp(0, vibMaxHz - 1);
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
          const SizedBox(height: 6),
        ] else if (settings.vibrationMode == 'Single') ...[
          smallNumberSlider(
            label: 'Vibration Single',
            value: settings.vibrationSingleHz,
            min: 10,
            max: vibMaxHz,
            divisions: (vibMaxHz - 10).toInt(),
            color: ThemeConstants.accent,
            unit: 'Hz',
            onChanged: (v) => onChangeSettings(
              settings.copyWith(vibrationSingleHz: v),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 12),

        // Hot / Cold intensity — web order after vibration.
        slider(
          label: 'Hot Pad Intensity',
          value: settings.hotLevel,
          valueColor: ThemeConstants.accent,
          onChanged: (v) =>
              onChangeSettings(settings.copyWith(hotLevel: v, hotPack: true)),
        ),
        const SizedBox(height: 10),
        slider(
          label: 'Cold Pad Intensity',
          value: settings.coldLevel,
          valueColor: Colors.blueAccent,
          onChanged: (v) =>
              onChangeSettings(settings.copyWith(coldLevel: v, coldPack: true)),
        ),
        const SizedBox(height: 12),

        // Start Delay — show always, device picker only for multi-device.
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ThemeConstants.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'START DELAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Delay',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${settings.startDelay}s',
                    style: TextStyle(
                      color: ThemeConstants.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Slider(
                value: settings.startDelay.toDouble(),
                min: 0,
                max: 60,
                divisions: 60,
                activeColor: ThemeConstants.accent,
                onChanged: (v) =>
                    onChangeSettings(settings.copyWith(startDelay: v.round())),
              ),
              if (isMulti && settings.startDelay > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Delay which device?',
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
                  children: selectedDeviceIds.map((id) {
                    final selected = delayedDeviceId == id;
                    return InkWell(
                      onTap: () => onChangeDelayedDeviceId(id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
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
                          id,
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
            ],
          ),
        ),
        const SizedBox(height: 12),

        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.6,
          ),
          children: [
            toggle(
              label: 'Cycle 1 Initialization',
              value: settings.cycle1Initiation,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(cycle1Initiation: v)),
            ),
            toggle(
              label: 'Cycle 5 Completion',
              value: settings.cycle5Completion,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(cycle5Completion: v)),
            ),
            toggle(
              label: 'LED',
              value: settings.lights,
              onChanged: (v) => onChangeSettings(settings.copyWith(lights: v)),
            ),
            toggle(
              label: 'Flip Pad',
              value: settings.flipSettings,
              onChanged: (v) =>
                  onChangeSettings(settings.copyWith(flipSettings: v)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: onToggleSavePreset,
          child: Row(
            children: [
              Icon(Icons.save_rounded,
                  size: 16, color: ThemeConstants.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Save configuration as preset',
                style: TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (showSavePreset) ...[
          const SizedBox(height: 10),
          presetsAsync.when(
            data: (presets) {
              presets.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

              Future<void> saveToSlot(int idx) async {
                final repo = ref.read(presetRepositoryProvider);
                final name = 'Preset ${idx + 1}';

                if (idx < presets.length) {
                  await repo.updatePreset(
                    id: presets[idx].id,
                    name: name,
                    deviceIds: selectedDeviceIds,
                    protocolId: protocolId,
                    advancedSettings: settings,
                  );
                } else {
                  await repo.createPreset(
                    name: name,
                    deviceIds: selectedDeviceIds,
                    protocolId: protocolId,
                    advancedSettings: settings,
                  );
                }

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved to $name')),
                );
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ThemeConstants.border),
                ),
                child: Row(
                  children: List.generate(3, (i) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                        child: OutlinedButton(
                          onPressed: selectedDeviceIds.isEmpty
                              ? null
                              : () => saveToSlot(i),
                          child: Text('Slot ${i + 1}'),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: HwLoading(),
            ),
            error: (e, _) => Text(
              'Failed to load presets: $e',
              style: TextStyle(color: ThemeConstants.error, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
