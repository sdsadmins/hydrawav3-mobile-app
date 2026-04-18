import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/ble_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../devices/domain/device_model.dart';
import '../../../devices/presentation/providers/wifi_devices_provider.dart';
import '../../../session/domain/session_model.dart';
import '../../../session/presentation/providers/session_target_provider.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';

class ProtocolDetailScreen extends ConsumerWidget {
  final String protocolId;
  const ProtocolDetailScreen({super.key, required this.protocolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(protocolDetailProvider(protocolId));
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
      appBar: AppBar(title: const Text('Protocol Details')),
      body: async.when(
        loading: () => const HwLoading(),
        error: (e, _) => HwErrorWidget(
            message: e.toString(),
            onRetry: () => ref.invalidate(protocolDetailProvider(protocolId))),
        data: (p) => ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedEntrance(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.templateName,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3)),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(p.description,
                      style: const TextStyle(
                          fontSize: 14,
                          color: ThemeConstants.textSecondary,
                          height: 1.5)),
                ],
              ],
            )),
            const SizedBox(height: 16),
            AnimatedEntrance(
                index: 1,
                child: Row(children: [
                  StatChip(
                      icon: Icons.timer_outlined,
                      value: p.totalDuration.formatted),
                  const SizedBox(width: 8),
                  StatChip(
                      icon: Icons.repeat_rounded,
                      value: '${p.cycles.length}',
                      label: 'cycles'),
                  const SizedBox(width: 8),
                  StatChip(
                      icon: Icons.play_circle_outline_rounded,
                      value: '${p.sessions}',
                      label: 'sessions'),
                ])),
            const SizedBox(height: 24),
            AnimatedEntrance(
              index: 2,
              child: GradientCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Web Payload Mapping',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _R('Session Count', '${p.sessions}'),
                    _R('Session Pause', '${p.sessionPause.toInt()}s'),
                    _R('Cycle 1 (edge)', p.cycle1 ? 'enabled' : 'disabled'),
                    _R('Cycle 5 (edge)', p.cycle5 ? 'enabled' : 'disabled'),
                    _R('Edge Cycle Duration', '${p.edgecycleduration.toInt()}s'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedEntrance(
                index: 3, child: const SectionHeader(title: 'Cycles')),
            ...p.cycles.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              return AnimatedEntrance(
                  index: i + 4,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GradientCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              GlowIconBox(
                                  icon: Icons.loop_rounded,
                                  size: 36,
                                  iconSize: 18),
                              const SizedBox(width: 12),
                              Text('Cycle ${i + 1} (C${i + 1})',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ]),
                            const SizedBox(height: 12),
                            _R('Duration (cycleDurations)', '${c.durationSeconds.toInt()}s'),
                            _R('Repetitions (cycleRepetitions)', '${c.repetitions}'),
                            _R(
                              'Pause Between Repetitions (pauseIntervals/cycle_pause)',
                              '${c.cyclePause.toInt()}s',
                            ),
                            _R(
                              'Pause After Cycle (cyclePauses/pause_seconds)',
                              '${c.pauseSeconds.toInt()}s',
                            ),
                            _R('Hot PWM', '${c.hotPwm.toInt()}'),
                            _R('Cold PWM', '${c.coldPwm.toInt()}'),
                            if (c.leftFunction.isNotEmpty)
                              _R('Left Function', c.leftFunction),
                            if (c.rightFunction.isNotEmpty)
                              _R('Right Function', c.rightFunction),
                          ],
                        )),
                  ));
            }),
            const SizedBox(height: 20),
            AnimatedEntrance(
                index: p.cycles.length + 3,
                child: GestureDetector(
                  onTap: () async {
                    // Prefer the user-selected transport + devices from Devices tab.
                    final target = ref.read(sessionTargetProvider);
                    appLogger.i(
                      'ProtocolDetail: Start tapped '
                      '(protocolId=${p.id}, name=${p.templateName}, sessions=${p.sessions}, cycles=${p.cycles.length})',
                    );
                    if (target.deviceIds.isNotEmpty) {
                      if (target.transport == SessionTransport.wifi) {
                        // Publish first so device and in-app timer stay aligned
                        // (session screen auto-starts the clock on open).
                        try {
                          final dio = ref.read(djangoDioProvider);
                          for (final mac in target.deviceIds) {
                            final payloadObj =
                                _protocolToWifiPayload(p, mac: mac);
                            final payloadStr = jsonEncode(payloadObj);
                            appLogger.i(
                              'WiFi: Publishing MQTT config (topic=HydraWav3Pro/config, mac=$mac, payload=$payloadStr)',
                            );
                            await dio.post(
                              ApiEndpoints.mqttPublish,
                              data: {
                                'topic': 'HydraWav3Pro/config',
                                'payload': payloadStr,
                              },
                            );
                          }
                        } catch (e) {
                          appLogger.e('WiFi: publish failed: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('WiFi publish failed: $e'),
                              ),
                            );
                          }
                          return;
                        }
                        if (!context.mounted) return;
                        final sessionClockAnchorMs =
                            DateTime.now().millisecondsSinceEpoch;
                        context.push(
                          RoutePaths.session,
                          extra: {
                            'protocolId': p.id,
                            'protocol': p,
                            'deviceIds': target.deviceIds,
                            'transport': 'wifi',
                            'sessionClockAnchorMs': sessionClockAnchorMs,
                          },
                        );
                        return;
                      }

                      // BLE selected
                      // CRITICAL FIX: Check if selected devices are still connected
                      final bleRepository = ref.read(bleRepositoryProvider);
                      final connectedNow = target.deviceIds
                          .where((id) => bleRepository.isConnected(id))
                          .toList();

                      if (connectedNow.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Selected BLE devices are not connected. ${target.deviceIds.length} device(s) selected but none are connected. '
                              'Please reconnect and try again.',
                            ),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                        return;
                      }

                      if (connectedNow.length < target.deviceIds.length) {
                        final disconnectedCount =
                            target.deviceIds.length - connectedNow.length;
                        appLogger.w(
                          'Protocol: Starting with $disconnectedCount of ${target.deviceIds.length} BLE devices disconnected, '
                          'proceeding with ${connectedNow.length} connected device(s)',
                        );
                      }

                      context.push(
                        RoutePaths.session,
                        extra: {
                          'protocolId': p.id,
                          'protocol': p,
                          'deviceIds': target.deviceIds,
                          'transport': 'ble',
                        },
                      );
                      return;
                    }

                    final hasBle = connectedIds.isNotEmpty;

                    // WiFi devices available from backend (MQTT/API path)
                    List<DeviceInfo> wifiDevices = const <DeviceInfo>[];
                    try {
                      wifiDevices =
                          await ref.read(wifiDevicesByOrgProvider.future);
                    } catch (_) {
                      wifiDevices = const <DeviceInfo>[];
                    }
                    final hasWifi = wifiDevices.isNotEmpty;

                    if (!hasBle && !hasWifi) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No BLE connected and no WiFi devices found.',
                          ),
                        ),
                      );
                      return;
                    }

                    Future<void> startBle() async {
                      final selected = await _pickConnectedDevices(
                        context,
                        connectedIds,
                        p,
                      );
                      if (!context.mounted ||
                          selected == null ||
                          selected.isEmpty) {
                        return;
                      }

                      // CRITICAL FIX: Re-verify devices are still connected after picker
                      final bleRepository = ref.read(bleRepositoryProvider);
                      final stillConnected = selected
                          .where((id) => bleRepository.isConnected(id))
                          .toList();

                      if (stillConnected.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Selected BLE devices disconnected. Please reconnect and try again.',
                            ),
                            duration: Duration(seconds: 3),
                          ),
                        );
                        return;
                      }

                      if (stillConnected.length < selected.length) {
                        appLogger.w(
                          'Protocol: ${selected.length - stillConnected.length} BLE devices disconnected after picker, '
                          'proceeding with ${stillConnected.length} connected device(s)',
                        );
                      }

                      context.push(
                        RoutePaths.session,
                        extra: {
                          'protocolId': p.id,
                          'protocol': p,
                          'deviceIds': selected,
                          'transport': 'ble'
                        },
                      );
                    }

                    Future<void> startWifi() async {
                      final selectedWifi = await _pickWifiDevices(context, ref);
                      if (!context.mounted ||
                          selectedWifi == null ||
                          selectedWifi.isEmpty) {
                        return;
                      }

                      try {
                        final dio = ref.read(djangoDioProvider);

                        // Backend expects payload as a STRINGIFIED OBJECT (not a list).
                        // So we publish one request per device:
                        // { topic: "...", payload: "{\"mac\":\"...\", ...}" }
                        for (final d in selectedWifi) {
                          final payloadObj =
                              _protocolToWifiPayload(p, mac: d.macAddress);
                          final payloadStr = jsonEncode(payloadObj);
                          appLogger.i(
                            'WiFi: Publishing MQTT config (topic=HydraWav3Pro/config, mac=${d.macAddress}, payload=$payloadStr)',
                          );
                          final resp = await dio.post(
                            ApiEndpoints.mqttPublish,
                            data: {
                              'topic': 'HydraWav3Pro/config',
                              'payload': payloadStr,
                            },
                          );
                          appLogger.i(
                            'WiFi: MQTT publish OK (mac=${d.macAddress}, status=${resp.statusCode ?? 200})',
                          );
                        }
                      } on DioException catch (e) {
                        appLogger.e(
                          'WiFi: MQTT publish failed '
                          '(status=${e.response?.statusCode}, data=${e.response?.data}, message=${e.message})',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'WiFi publish failed: ${e.message ?? e.toString()}',
                              ),
                            ),
                          );
                        }
                        return;
                      } catch (e) {
                        appLogger.e('WiFi: MQTT publish failed: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('WiFi publish failed: $e'),
                            ),
                          );
                        }
                        return;
                      }

                      if (!context.mounted) return;
                      final sessionClockAnchorMs =
                          DateTime.now().millisecondsSinceEpoch;
                      context.push(
                        RoutePaths.session,
                        extra: {
                          'protocolId': p.id,
                          'protocol': p,
                          'deviceIds':
                              selectedWifi.map((d) => d.macAddress).toList(),
                          'transport': 'wifi',
                          'sessionClockAnchorMs': sessionClockAnchorMs,
                        },
                      );
                    }

                    if (hasWifi && !hasBle) {
                      await startWifi();
                      return;
                    }
                    if (hasBle && !hasWifi) {
                      await startBle();
                      return;
                    }

                    // Both available → ask user which transport to use.
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      backgroundColor: ThemeConstants.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(18)),
                      ),
                      builder: (ctx) => SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Start session using',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ListTile(
                                leading: const Icon(Icons.bluetooth_rounded,
                                    color: Colors.white),
                                title: const Text('Bluetooth (BLE)',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  '${connectedIds.length} connected',
                                  style: const TextStyle(
                                    color: ThemeConstants.textSecondary,
                                  ),
                                ),
                                onTap: () => Navigator.of(ctx).pop('ble'),
                              ),
                              ListTile(
                                leading: const Icon(Icons.wifi_rounded,
                                    color: Colors.white),
                                title: const Text('WiFi (MQTT/API)',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  '${wifiDevices.length} available',
                                  style: const TextStyle(
                                    color: ThemeConstants.textSecondary,
                                  ),
                                ),
                                onTap: () => Navigator.of(ctx).pop('wifi'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    if (!context.mounted || choice == null) return;
                    if (choice == 'wifi') {
                      await startWifi();
                    } else {
                      await startBle();
                    }
                  },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [ThemeConstants.accent, Color(0xFFE09060)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: ThemeConstants.accent.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 22),
                          SizedBox(width: 8),
                          Text('Start Session',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                )),
          ],
        ),
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

  String? selectedMac;
  return showModalBottomSheet<List<DeviceInfo>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
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
                    const Text(
                      'Select one WiFi device',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
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
                          final checked = selectedMac == key;
                          return RadioListTile<String>(
                            value: key,
                            groupValue: selectedMac,
                            activeColor: ThemeConstants.accent,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              d.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              d.macAddress,
                              style: const TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            onChanged: (v) {
                              setSheetState(() {
                                selectedMac = v;
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
                        onPressed: selectedMac == null
                            ? null
                            : () {
                                final picked = async
                                    .where((d) => d.macAddress == selectedMac)
                                    .toList();
                                Navigator.of(ctx).pop(picked);
                              },
                        child: const Text('Send to selected device'),
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
}) {
  final cycles = p.cycles;
  return {
    'mac': mac,
    'sessionCount': p.sessions,
    'sessionPause': p.sessionPause.toInt(),
    'sDelay': 0,
    'cycle1': p.cycle1 ? 1 : 0,
    'cycle5': p.cycle5 ? 1 : 0,
    'edgeCycleDuration': p.edgecycleduration.toInt(),
    'cycleRepetitions': cycles.map((c) => c.repetitions).toList(),
    'cycleDurations': cycles.map((c) => c.durationSeconds.toInt()).toList(),
    // Match web sender exactly.
    'cyclePauses': cycles.map((c) => c.pauseSeconds.toInt()).toList(),
    'pauseIntervals': cycles.map((c) => c.cyclePause.toInt()).toList(),
    'leftFuncs': cycles.map((c) => c.leftFunction).toList(),
    'rightFuncs': cycles.map((c) => c.rightFunction).toList(),
    'pwmValues': {
      'hot': cycles.map((c) => c.hotPwm.toInt()).toList(),
      'cold': cycles.map((c) => c.coldPwm.toInt()).toList(),
    },
    'playCmd': 1,
    'led': 1,
    'hotDrop': p.hotdrop.toInt(),
    'coldDrop': p.colddrop.toInt(),
    'vibMin': p.vibmin.toInt(),
    'vibMax': p.vibmax.toInt(),
    'totalDuration': p.totalDurationSeconds,
  };
}

Future<List<String>?> _pickConnectedDevices(
  BuildContext context,
  List<String> connectedIds,
  Protocol protocol,
) async {
  String? selectedId = connectedIds.isNotEmpty ? connectedIds.first : null;
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
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
                    const Text(
                      'Select one connected device',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose one device for this session.',
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
                              final checked = selectedId == id;
                              return RadioListTile<String>(
                                value: id,
                                groupValue: selectedId,
                                activeColor: ThemeConstants.accent,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  id,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: ThemeConstants.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                onChanged: (v) {
                                  setSheetState(() {
                                    selectedId = v;
                                  });
                                },
                              );
                            }),
                            const SizedBox(height: 8),
                            if (selectedId != null) ...[
                              const Text(
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
                                    final selectedTransportId = selectedId!;
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
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
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
                        onPressed: selectedId == null
                            ? null
                            : () => Navigator.of(ctx).pop(<String>[selectedId!]),
                        child: const Text('Start with selected device'),
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
    'edgeCycleDuration': p.edgecycleduration.toInt(),
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
                style: const TextStyle(
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}
