import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/logger.dart';
import '../../../advanced_settings/domain/advanced_settings_model.dart';
import '../../../session/domain/session_model.dart' as session_model;
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/services/protocol_plus_controller.dart';
import '../../../session/services/session_engine.dart';
import '../../domain/protocol_model.dart';
import '../../domain/protocol_plus_model.dart';
import '../providers/protocol_provider.dart';

/// Lists Protocol Plus templates for an already-selected device + transport.
/// Tapping one starts protocol[0] locally (the normal run) and then registers
/// the server-driven sequence so the remaining protocols auto-switch.
class ProtocolPlusListScreen extends ConsumerStatefulWidget {
  final List<String> deviceIds;
  final String transport; // 'ble' or 'wifi'

  const ProtocolPlusListScreen({
    super.key,
    required this.deviceIds,
    this.transport = 'ble',
  });

  @override
  ConsumerState<ProtocolPlusListScreen> createState() =>
      _ProtocolPlusListScreenState();
}

class _ProtocolPlusListScreenState
    extends ConsumerState<ProtocolPlusListScreen> {
  bool _starting = false;

  session_model.SessionTransport get _transportEnum => widget.transport == 'wifi'
      ? session_model.SessionTransport.wifi
      : session_model.SessionTransport.ble;

  Future<void> _start(ProtocolPlus template) async {
    if (_starting) return;
    final deviceId =
        widget.deviceIds.isNotEmpty ? widget.deviceIds.first : null;
    if (deviceId == null) {
      _snack('No device selected for Protocol Plus.');
      return;
    }

    // Guard against starting on a device already running a session.
    final busy = ref.read(activeSessionsProvider.notifier).getBusyDevices();
    if (busy.contains(deviceId)) {
      _snack('Device already in use: $deviceId');
      return;
    }

    setState(() => _starting = true);
    String? sessionId;
    try {
      final controller = ref.read(protocolPlusControllerProvider);

      // Fetch the protocol-plus with its sub-protocols POPULATED (full cycles)
      // and its overall totalDuration.
      final detail = await controller.getProtocolPlusDetail(template.id);
      final orderedIds =
          detail.protocolIds.isNotEmpty ? detail.protocolIds : template.protocolIds;
      final populated = detail.protocols;
      final totalDurationSeconds =
          detail.totalDuration > 0 ? detail.totalDuration : template.totalDuration;
      appLogger.i(
        'ProtocolPlus: plusId=${template.id}, protocolIds=$orderedIds, '
        'populated=${populated.length}, totalDuration=${totalDurationSeconds}s',
      );
      if (orderedIds.isEmpty && populated.isEmpty) {
        throw StateError(
            'Protocol Plus "${template.templateName}" has no protocols');
      }

      // protocol[0] full object (cycles) — prefer the populated payload,
      // otherwise fetch the REAL protocol id (never the plus id).
      Protocol firstProtocol;
      if (populated.isNotEmpty && populated.first.cycles.isNotEmpty) {
        firstProtocol = populated.first;
      } else {
        final firstProtocolId = orderedIds.first;
        if (firstProtocolId == template.id) {
          throw StateError(
              'Protocol Plus data error: protocolIds[0] equals the plus id '
              '($firstProtocolId)');
        }
        appLogger
            .i('ProtocolPlus: fetching first protocol id=$firstProtocolId');
        firstProtocol =
            await ref.read(protocolDetailProvider(firstProtocolId).future);
      }

      const advanced = AdvancedSettings();
      sessionId = const Uuid().v4();
      final engine =
          ref.read(sessionEngineFamilyProvider(sessionId).notifier);

      engine.prepareSession(
        deviceIds: [deviceId],
        transport: _transportEnum,
      );
      engine.loadSession(
        firstProtocol,
        [deviceId],
        transport: _transportEnum,
        advancedSettings: advanced,
        advancedSettingsByDevice: {deviceId: advanced},
        protocolByDevice: {deviceId: firstProtocol},
        wifiConfigAlreadyPublished: false,
      );
      // Protocol Plus: span the WHOLE sequence so the session doesn't end when
      // protocol[0] finishes — later protocols continue via START_PROTOCOL.
      engine.setSessionTotalDuration(totalDurationSeconds);
      // Sequence tracker: plus title + ordered sub-protocol names.
      engine.setProtocolPlusSequence(
        template.templateName,
        populated.isNotEmpty
            ? populated.map((p) => p.templateName).toList()
            : List<String>.from(orderedIds),
      );
      engine.applySessionClockOffsetFromWallAnchor(DateTime.now());
      await engine.start();

      // Open the session screen IMMEDIATELY — the device is already running
      // after engine.start(). Waiting on the (network) server registration here
      // left the device running with no UI, so impatient users navigated away
      // and the run was recorded nowhere. Registration now runs in the
      // background and delivers the socket binding via the bindings provider,
      // which the session screen wires up when it arrives.
      if (!mounted) return;
      context.push(
        RoutePaths.session,
        extra: {
          'sessionId': sessionId,
          'protocolId': firstProtocol.id,
          'protocol': firstProtocol,
          'deviceIds': [deviceId],
          'transport': widget.transport,
          'advancedSettings': advanced,
          'advancedSettingsByDevice': {deviceId: advanced},
          'protocolByDeviceId': {deviceId: firstProtocol.id},
          'skipEngineBootstrap': true,
          // Protocol Plus wiring — registration is in flight; the screen waits
          // for the binding and then drives the socket auto-switches.
          'protocolPlusPending': true,
          'protocolPlusId': template.id,
        },
      );

      // Register the server-driven sequence (schedules protocol[1..N]) in the
      // background; the session screen connects its socket when the binding is
      // published via protocolPlusBindingsProvider.
      unawaited(controller.registerAndPublishBindings(
        sessionId: sessionId,
        plans: [
          ProtocolPlusRegistration(
            deviceId: deviceId,
            plusId: template.id,
            advanced: advanced,
          ),
        ],
        transport: widget.transport,
      ));
    } catch (e) {
      if (sessionId != null) {
        ref.read(sessionEngineFamilyProvider(sessionId).notifier).reset();
      }
      _snack('Failed to start Protocol Plus: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(protocolPlusListProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: const Text('Protocol Plus'),
      ),
      body: Stack(
        children: [
          listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load Protocol Plus: $e'),
              ),
            ),
            data: (templates) {
              if (templates.isEmpty) {
                return const Center(child: Text('No Protocol Plus templates.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final t = templates[index];
                  return _ProtocolPlusCard(
                    template: t,
                    onTap: _starting ? null : () => _start(t),
                  );
                },
              );
            },
          ),
          if (_starting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProtocolPlusCard extends StatelessWidget {
  final ProtocolPlus template;
  final VoidCallback? onTap;

  const _ProtocolPlusCard({required this.template, this.onTap});

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeConstants.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.templateName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded,
                      color: ThemeConstants.accent),
                ],
              ),
              if (template.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  template.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: ThemeConstants.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _Chip(
                    icon: Icons.layers_outlined,
                    label: '${template.protocolCount} protocols',
                  ),
                  const SizedBox(width: 8),
                  _Chip(
                    icon: Icons.timer_outlined,
                    label: _formatDuration(template.totalDuration),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ThemeConstants.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ThemeConstants.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ThemeConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
