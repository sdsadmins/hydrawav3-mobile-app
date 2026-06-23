import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../session/domain/active_session_model.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/services/session_sync_service.dart';

enum _HistoryTab { live, history }

enum _HistoryFilter { all, guest }

class HistoryListScreen extends ConsumerStatefulWidget {
  const HistoryListScreen({super.key});

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  _HistoryTab _selectedTab = _HistoryTab.live;
  _HistoryFilter _historyFilter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    // Defensively ensure the org-wide live feed is running (idempotent if the
    // app bootstrap already started it) so the Live tab reflects the backend.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orgId = ref.read(authStateProvider).selectedOrgId;
      if (orgId != null && orgId.isNotEmpty) {
        ref.read(liveSessionsProvider.notifier).start(orgId);
      }
    });
  }

  bool _isLiveStatus(SessionStatus status) {
    return status == SessionStatus.running || status == SessionStatus.paused;
  }

  /// Keep sessions visible while at least one device is still live,
  /// including the fully-paused case where no device is currently running.
  bool _isVisibleActiveSession(ActiveSession session) {
    if (_isLiveStatus(session.status)) {
      return true;
    }
    for (final deviceId in session.deviceIds) {
      final deviceStatus =
          session.deviceStatuses[deviceId] ?? SessionStatus.idle;
      if (_isLiveStatus(deviceStatus)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final allActiveSessions = ref.watch(liveSessionsProvider);

    // Keep only genuinely live sessions (running on top, older below).
    final runningSessions = allActiveSessions
        .where(_isVisibleActiveSession)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final sessionsAsync = ref.watch(allSessionsProvider);
    final savedSessions = sessionsAsync.asData?.value ?? const <SessionHistoryItem>[];
    final trackedMinutes = savedSessions.fold<int>(
      0,
      (sum, s) => sum + (_intakeDurationSeconds(s) ~/ 60),
    );

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session History',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: ThemeConstants.textPrimary,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 12),
                    Row(children: [
                      _SummaryChip(
                          value: '${runningSessions.length}',
                          label: 'Live',
                          icon: Icons.play_circle_outline_rounded),
                      const SizedBox(width: 8),
                      _SummaryChip(
                          value: '${savedSessions.length}',
                          label: 'History',
                          icon: Icons.history_rounded),
                      const SizedBox(width: 8),
                      _SummaryChip(
                          value: '${trackedMinutes}m',
                          label: 'Tracked',
                          icon: Icons.timer_outlined),
                    ]),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: ThemeConstants.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HistoryTabButton(
                              label: 'Live Session',
                              icon: Icons.bolt_rounded,
                              selected: _selectedTab == _HistoryTab.live,
                              onTap: () => setState(
                                () => _selectedTab = _HistoryTab.live,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _HistoryTabButton(
                              label: 'History',
                              icon: Icons.history_rounded,
                              selected: _selectedTab == _HistoryTab.history,
                              onTap: () => setState(
                                () => _selectedTab = _HistoryTab.history,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _selectedTab == _HistoryTab.live
                    ? _buildLiveSessions(runningSessions)
                    : _buildHistorySessions(sessionsAsync),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveSessions(List<ActiveSession> runningSessions) {
    if (runningSessions.isEmpty) {
      return const _EmptyHistoryState(
        title: 'No live sessions',
        subtitle: 'Start a session to see it appear here while it is running.',
        icon: Icons.play_disabled_rounded,
      );
    }

    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: runningSessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final session = runningSessions[index];
        return AnimatedEntrance(
          index: index,
          child: _ActiveSessionCard(
            session: session,
            canOpenLive: _isVisibleActiveSession(session),
          ),
        );
      },
    );
  }

  Widget _buildHistorySessions(
      AsyncValue<List<SessionHistoryItem>> sessionsAsync) {
    return Column(
      children: [
        _HistoryFilterToggle(
          filter: _historyFilter,
          onChanged: (value) => setState(() => _historyFilter = value),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: sessionsAsync.when(
            loading: () => ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, __) => const _HistoryCardSkeleton(),
            ),
            error: (error, _) => _EmptyHistoryState(
              title: 'Couldn\'t load history',
              subtitle: 'Pull down to retry. ($error)',
              icon: Icons.cloud_off_rounded,
              onRetry: () => ref.invalidate(allSessionsProvider),
            ),
            data: (sessions) {
              final filtered = _historyFilter == _HistoryFilter.guest
                  ? sessions.where((s) => s.isGuest).toList()
                  : [...sessions];

              // Most recent first (the backend returns these unsorted).
              filtered.sort((a, b) {
                final aDate = a.createdAt;
                final bDate = b.createdAt;
                if (aDate == null && bDate == null) return 0;
                if (aDate == null) return 1; // unknown dates sink to the bottom
                if (bDate == null) return -1;
                return bDate.compareTo(aDate);
              });

              if (filtered.isEmpty) {
                return RefreshIndicator(
                  color: ThemeConstants.accent,
                  onRefresh: () => ref.refresh(allSessionsProvider.future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 40),
                      _EmptyHistoryState(
                        title: _historyFilter == _HistoryFilter.guest
                            ? 'No guest sessions'
                            : 'No saved sessions',
                        subtitle: _historyFilter == _HistoryFilter.guest
                            ? 'Guest sessions saved to the database will appear here.'
                            : 'Completed sessions saved to the database will appear here.',
                        icon: Icons.history_rounded,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: ThemeConstants.accent,
                onRefresh: () => ref.refresh(allSessionsProvider.future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return AnimatedEntrance(
                      index: index,
                      child: _HistorySessionCard(session: filtered[index]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Total session duration (seconds) for an intake — the longest protocol run.
int _intakeDurationSeconds(SessionHistoryItem session) {
  var maxSeconds = 0;
  for (final protocol in session.protocols) {
    final value = protocol.duration ?? 0;
    if (value > maxSeconds) maxSeconds = value;
  }
  return maxSeconds;
}

String _formatHistoryDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year}  $hour:$minute';
}

String _formatHistoryDuration(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${safeSeconds}s';
}

class _ActiveSessionCard extends ConsumerWidget {
  final ActiveSession session;
  final bool canOpenLive;
  const _ActiveSessionCard({required this.session, required this.canOpenLive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // session.status is the ActiveSession SessionStatus enum — compare against
    // that, not session_model's (the cross-enum compare was always false, so the
    // card always read 'Running').
    final status =
        session.status == SessionStatus.paused ? 'Paused' : 'Running';
    final perDeviceStatuses = session.deviceIds
        .map((id) => session.deviceStatuses[id] ?? session.status)
        .toList();

    // Control gating (parity with web):
    //   • own run        → tap to open the live screen (full control).
    //   • foreign WiFi    → remote-controllable via the cloud broker (no open).
    //   • foreign BLE     → read-only (can't reach a BLE device we aren't bonded to).
    final isWifi = session.transport == 'wifi';
    final canRemoteControl = !session.isOwn && isWifi;
    // Resolve the LOCAL active session this backend run maps to (own runs only);
    // re-opening must target the real local engine, not the backend sessionId.
    final localId = ref.read(ownBackendToLocalSessionProvider)[session.id];
    ActiveSession? localSession;
    if (localId != null) {
      for (final s in ref.read(activeSessionsProvider)) {
        if (s.id == localId) {
          localSession = s;
          break;
        }
      }
    }
    final canOpen = session.isOwn && canOpenLive && localSession != null;

    return GradientCard(
      onTap: () {
        // Own run → open the local live screen against the real engine.
        final local = localSession;
        if (canOpen && local != null) {
          context.pushNamed(
            RouteNames.session,
            extra: {
              'sessionId': local.id,
              'protocolId': local.protocolId,
              'deviceIds': local.deviceIds,
              'transport': local.transport == 'wifi' ? 'wifi' : 'ble',
              'advancedSettings': {},
              'advancedSettingsByDevice': {},
              'delayedDeviceId': null,
              'protocolByDeviceId': {},
              'skipEngineBootstrap': false,
              'sessionClockAnchorMs': local.createdAt.millisecondsSinceEpoch,
              // Restore Protocol Plus wiring so Stop cancels the server schedule.
              if (local.protocolPlusBindings.isNotEmpty) ...{
                'protocolPlusBindings': local.protocolPlusBindings,
                'protocolPlusId':
                    local.protocolPlusBindings.first['plusId'] ?? '',
              },
            },
          );
          return;
        }
        // Foreign WiFi run → open the live REMOTE VIEW (no local engine, no
        // restart; display + control come from the backend feed).
        if (canRemoteControl) {
          context.pushNamed(
            RouteNames.session,
            extra: {
              'remoteView': true,
              'backendSessionId': session.id,
              'sessionId': session.id,
              'protocolId': '',
              'deviceIds': session.deviceIds,
              'transport': session.transport,
              'skipEngineBootstrap': true,
            },
          );
        }
      },
      padding: const EdgeInsets.all(16),
      showShadow: false,
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
                child: Icon(
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.deviceIds.length} device(s) • ${session.transport.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeConstants.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Started ${_formatDate(session.createdAt)}',
                      style: TextStyle(
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
                  color: (session.status == SessionStatus.paused
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
                final isPaused = deviceStatus == SessionStatus.paused;
                final isRunning = deviceStatus == SessionStatus.running;
                final statusColor = isPaused
                    ? ThemeConstants.warning
                    : (isRunning
                        ? ThemeConstants.success
                        : ThemeConstants.textTertiary);
                final statusLabel =
                    isPaused ? 'Paused' : (isRunning ? 'Running' : 'Idle');

                final live = index < session.liveDevices.length
                    ? session.liveDevices[index]
                    : null;
                final remaining = live?.remainingSeconds;

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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ThemeConstants.textPrimary,
                          ),
                        ),
                      ),
                      // Sun/moon pad colors straight from the backend
                      // (web parity). Moon = left pad, Sun = right pad.
                      if (live != null) ...[
                        _PadDot(
                          icon: Icons.nightlight_round,
                          color: _padColor(live.moon),
                        ),
                        const SizedBox(width: 6),
                        _PadDot(
                          icon: Icons.wb_sunny_rounded,
                          color: _padColor(live.sun),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Per-device countdown straight from the backend (never
                      // computed on-device). Hidden when not provided.
                      if (remaining != null && remaining > 0) ...[
                        Text(
                          _formatRemaining(remaining),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ThemeConstants.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
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
          if (!session.isOwn) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  canRemoteControl
                      ? Icons.touch_app_outlined
                      : Icons.visibility_outlined,
                  size: 14,
                  color: ThemeConstants.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  canRemoteControl
                      ? 'Tap to open & control'
                      : 'View only (BLE session on another device)',
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ],
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

String _formatRemaining(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

/// Web-parity pad colors (Hydrawav3-ai liveSession.tsx): hot/red → red,
/// cold/blue → blue, anything else (disabled/off/empty) → grey.
Color _padColor(String? v) {
  if (v == null) return Colors.grey;
  final s = v.toLowerCase().trim();
  if (s.contains('hot') || s == 'red') return Colors.red;
  if (s.contains('cold') || s == 'blue') return Colors.blue;
  return Colors.grey;
}

/// A labelled pad chip (Moon = left pad, Sun = right pad) coloured from the
/// backend sun/moon string.
class _PadDot extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _PadDot({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Icon(icon, size: 12, color: color),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: ThemeConstants.accent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.textPrimary)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: ThemeConstants.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HistoryTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          // Match the Devices list segmented control: dark slate selected
          // segment with cream text/icons (web-parity), not an accent tint.
          color: selected
              ? ThemeConstants.segmentActiveBg
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: ThemeConstants.segmentActiveBg
                        .withValues(alpha: 0.22),
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
              size: 17,
              color:
                  selected ? ThemeConstants.onNav : ThemeConstants.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected
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

class _HistoryFilterToggle extends StatelessWidget {
  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onChanged;

  const _HistoryFilterToggle({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterPill(
          label: 'All',
          icon: Icons.all_inclusive_rounded,
          selected: filter == _HistoryFilter.all,
          onTap: () => onChanged(_HistoryFilter.all),
        ),
        const SizedBox(width: 8),
        _FilterPill(
          label: 'Guest only',
          icon: Icons.person_outline_rounded,
          selected: filter == _HistoryFilter.guest,
          onTap: () => onChanged(_HistoryFilter.guest),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.16)
              : ThemeConstants.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? ThemeConstants.accent
                  : ThemeConstants.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected
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

class _HistoryCardSkeleton extends StatelessWidget {
  const _HistoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border.withValues(alpha: 0.6)),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 40, height: 40, borderRadius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 130, height: 13, borderRadius: 6),
                SizedBox(height: 8),
                ShimmerBox(width: double.infinity, height: 11, borderRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySessionCard extends StatelessWidget {
  final SessionHistoryItem session;

  const _HistorySessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final protocolName = session.protocols.isNotEmpty
        ? (session.protocols.first.protocol ?? 'Session')
        : 'Session';
    final deviceCount = session.protocols
        .map((p) => p.deviceName)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;
    final durationLabel = _formatHistoryDuration(_intakeDurationSeconds(session));
    final dateLabel =
        session.createdAt != null ? _formatHistoryDate(session.createdAt!) : '—';
    final meta = StringBuffer('$dateLabel  •  $durationLabel');
    if (deviceCount > 0) {
      meta.write('  •  $deviceCount device(s)');
    }

    return GradientCard(
      onTap: () => context.push('/history/${session.id ?? ''}', extra: session),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      showShadow: false,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ThemeConstants.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 20,
              color: ThemeConstants.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  protocolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeConstants.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            color: ThemeConstants.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onRetry;

  const _EmptyHistoryState({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ThemeConstants.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ThemeConstants.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: ThemeConstants.textTertiary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: ThemeConstants.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded,
                    size: 18, color: ThemeConstants.accent),
                label: Text(
                  'Retry',
                  style: TextStyle(
                    color: ThemeConstants.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
