import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../session/domain/session_model.dart' as session_model;
import '../../../session/domain/active_session_model.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/services/session_engine.dart';
import '../../../session/services/background_session_runtime.dart';

class _Session {
  final String id, protocol, date, duration;
  final bool synced;
  final int discomfortBefore, discomfortAfter;
  _Session(this.id, this.protocol, this.date, this.duration, this.synced,
      this.discomfortBefore, this.discomfortAfter);
}

final _sessions = <_Session>[];

class HistoryListScreen extends ConsumerWidget {
  const HistoryListScreen({super.key});

  /// Check if a session is actually running by validating individual device statuses
  bool _isSessionActuallyRunning(
      ActiveSession session, SessionEngineState engineState) {
    // Check if any devices in this session are actually running
    bool hasRunningDevices = false;
    for (final deviceId in session.deviceIds) {
      final deviceStatus =
          session.deviceStatuses[deviceId] ?? SessionStatus.idle;
      if (deviceStatus == SessionStatus.running) {
        hasRunningDevices = true;
        break;
      }
    }

    return hasRunningDevices;
  }

  String _deviceSetKey(List<String> ids) {
    final list = List<String>.from(ids)..sort();
    return list.join(',');
  }

  bool _isLiveByDeviceStatuses(ActiveSession s) {
    // Check if any devices in this session are actually running
    bool hasRunningDevices = false;
    for (final deviceId in s.deviceIds) {
      final deviceStatus = s.deviceStatuses[deviceId] ?? SessionStatus.idle;
      if (deviceStatus == SessionStatus.running) {
        hasRunningDevices = true;
        break;
      }
    }

    return hasRunningDevices;
  }

  String _signature(ActiveSession s) {
    return '${s.protocolId}|${s.transport}|${_deviceSetKey(s.deviceIds)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allActiveSessions = ref.watch(activeSessionsProvider);
    final engineState = ref.watch(sessionEngineProvider);

    // Show ALL sessions in History (running on top, older below).
    // Engine is only used to decide which running card can open live timing UI.
    // Keep only genuinely live sessions, then collapse duplicates so
    // one real session appears as one card.
    final liveSessions = allActiveSessions
        .where(_isLiveByDeviceStatuses)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final bySignature = <String, ActiveSession>{};
    for (final s in liveSessions) {
      final key = _signature(s);
      final existing = bySignature[key];
      if (existing == null || s.createdAt.isAfter(existing.createdAt)) {
        bySignature[key] = s;
      }
    }
    final runningSessions = bySignature.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(color: ThemeConstants.background),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Session History',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: ThemeConstants.textPrimary,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        const Text('Track your therapy progress',
                            style: TextStyle(
                                fontSize: 14,
                                color: ThemeConstants.textSecondary)),
                        const SizedBox(height: 16),
                        // Summary stats
                        Row(children: [
                          _SummaryChip(
                              value: '${runningSessions.length}',
                              label: 'Sessions',
                              icon: Icons.play_circle_outline_rounded),
                          const SizedBox(width: 10),
                          const _SummaryChip(
                              value: '-0.0',
                              label: 'Avg Relief',
                              icon: Icons.trending_down_rounded),
                          const SizedBox(width: 10),
                          const _SummaryChip(
                              value: '0m',
                              label: 'Total Time',
                              icon: Icons.timer_outlined),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Sessions
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  // Show current live session from engine - COMMENTED OUT
                  /*if (hasLiveSession && i == 0) {
                    return AnimatedEntrance(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LiveSessionCard(engine: engine),
                      ),
                    );
                  }

                  // Show background service session - COMMENTED OUT
                  if (hasServiceLiveSession && i == 0) {
                    return AnimatedEntrance(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ServiceLiveSessionCard(
                          runtime: bgRuntime,
                        ),
                      ),
                    );
                  }*/

                  // Running sessions (big cards)
                  if (i < runningSessions.length) {
                    final session = runningSessions[i];
                    return AnimatedEntrance(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ActiveSessionCard(
                          session: session,
                          canOpenLive:
                              _isSessionActuallyRunning(session, engineState),
                        ),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
                childCount: runningSessions.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  final ActiveSession session;
  final bool canOpenLive;
  const _ActiveSessionCard({required this.session, required this.canOpenLive});

  @override
  Widget build(BuildContext context) {
    final status = session.status == session_model.SessionStatus.paused
        ? 'Paused'
        : 'Running';
    final perDeviceStatuses = session.deviceIds
        .map((id) => session.deviceStatuses[id] ?? session.status)
        .toList();

    return GradientCard(
      onTap: () {
        if (!canOpenLive) return;
        // Navigate to session screen with this active session
        context.pushNamed(
          RouteNames.session,
          extra: {
            'sessionId': session.id,
            'protocolId': session.protocolId,
            'deviceIds': session.deviceIds,
            'transport':
                session.transport == session_model.SessionTransport.wifi
                    ? 'wifi'
                    : 'ble',
            'advancedSettings': {},
            'advancedSettingsByDevice': {},
            'delayedDeviceId': null,
            'protocolByDeviceId': {},
            // We are coming from History while engine is already running/paused.
            // Skip bootstrap so SessionScreen uses the current engine state.
            'skipEngineBootstrap': true,
            'sessionClockAnchorMs': session.createdAt.millisecondsSinceEpoch,
          },
        );
      },
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.devices_rounded,
                  color: ThemeConstants.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.protocolName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.deviceIds.length} device(s) • ${session.transport.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Started ${_formatDate(session.createdAt)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (session.status == session_model.SessionStatus.paused
                          ? ThemeConstants.warning
                          : ThemeConstants.success)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: session.status == SessionStatus.paused
                        ? ThemeConstants.warning
                        : ThemeConstants.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ThemeConstants.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ThemeConstants.border),
            ),
            child: Column(
              children: List.generate(session.deviceIds.length, (index) {
                final id = session.deviceIds[index];
                final name = session.deviceNames[id] ?? 'Device ${index + 1}';
                final deviceStatus = perDeviceStatuses[index];
                final isPaused =
                    deviceStatus == session_model.SessionStatus.paused;
                final isRunning =
                    deviceStatus == session_model.SessionStatus.running;
                final statusColor = isPaused
                    ? ThemeConstants.warning
                    : (isRunning
                        ? ThemeConstants.success
                        : ThemeConstants.textTertiary);
                final statusLabel =
                    isPaused ? 'Paused' : (isRunning ? 'Running' : 'Idle');

                return Padding(
                  padding: EdgeInsets.only(
                      bottom: index == session.deviceIds.length - 1 ? 0 : 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _ServiceLiveSessionCard extends StatelessWidget {
  final BackgroundSessionState runtime;
  const _ServiceLiveSessionCard({required this.runtime});

  @override
  Widget build(BuildContext context) {
    final snapshot = runtime.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final status = runtime.status == 'paused' ? 'Paused' : 'Running';

    return GradientCard(
      onTap: () {
        context.pushNamed(
          RouteNames.session,
          extra: {
            'protocolId': snapshot.protocolId,
            'deviceIds': snapshot.deviceIds,
            'transport': snapshot.transport,
            'advancedSettings': snapshot.advancedSettings,
            'advancedSettingsByDevice': snapshot.advancedSettingsByDevice,
            'delayedDeviceId': snapshot.delayedDeviceId,
            'protocolByDeviceId': snapshot.protocolByDeviceId,
            // Engine may be cold after app restart; allow bootstrap path.
            'skipEngineBootstrap': false,
            'sessionClockAnchorMs': snapshot.startedAtEpochMs,
          },
        );
      },
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ThemeConstants.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bluetooth_connected_rounded,
              color: ThemeConstants.warning,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.protocolName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${snapshot.deviceIds.length} device(s) in background session',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (runtime.status == 'paused'
                      ? ThemeConstants.warning
                      : ThemeConstants.success)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: runtime.status == 'paused'
                    ? ThemeConstants.warning
                    : ThemeConstants.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _SummaryChip(
      {required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 18),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: ThemeConstants.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final _Session session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final improvement = session.discomfortBefore - session.discomfortAfter;
    return GradientCard(
      onTap: () => context.push('/history/${session.id}'),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const GlowIconBox(icon: Icons.play_circle_outline_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.protocol,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ThemeConstants.textPrimary)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${session.date}  ·  ${session.duration}',
                      style: const TextStyle(
                          fontSize: 12, color: ThemeConstants.textTertiary)),
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ThemeConstants.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('-$improvement',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.success)),
              ),
              const SizedBox(height: 4),
              Icon(
                  session.synced
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  size: 14,
                  color: session.synced
                      ? ThemeConstants.success.withValues(alpha: 0.5)
                      : ThemeConstants.textTertiary),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  final SessionEngineState engine;
  const _LiveSessionCard({required this.engine});

  @override
  Widget build(BuildContext context) {
    final status = engine.status == session_model.SessionStatus.paused
        ? 'Paused'
        : 'Running';
    final protocol = engine.protocol;
    final protocolByDeviceId = <String, String>{
      for (final entry in engine.protocolByDevice.entries)
        entry.key: entry.value.id,
    };

    return GradientCard(
      onTap: () {
        if (protocol == null) return;
        context.pushNamed(
          RouteNames.session,
          extra: {
            'protocolId': protocol.id,
            'protocol': protocol,
            'deviceIds': engine.deviceIds,
            'transport': engine.transport == session_model.SessionTransport.wifi
                ? 'wifi'
                : 'ble',
            'advancedSettings': engine.advancedSettings,
            'advancedSettingsByDevice': engine.advancedSettingsByDevice,
            'delayedDeviceId': engine.delayedDeviceId,
            'protocolByDeviceId': protocolByDeviceId,
            // Critical: keep current in-memory engine session as-is.
            'skipEngineBootstrap': true,
          },
        );
      },
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: ThemeConstants.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  protocol?.templateName ?? 'Live Session',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${engine.deviceIds.length} device(s) connected',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (engine.status == SessionStatus.paused
                      ? ThemeConstants.warning
                      : ThemeConstants.success)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: engine.status == SessionStatus.paused
                    ? ThemeConstants.warning
                    : ThemeConstants.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
