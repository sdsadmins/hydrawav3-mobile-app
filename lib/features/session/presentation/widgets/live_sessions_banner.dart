import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../devices/presentation/widgets/ref_palette.dart';
import '../../domain/active_session_model.dart';
import '../../services/session_sync_service.dart';
import '../providers/active_sessions_provider.dart';
import '../providers/live_sessions_provider.dart';

/// Open [session]'s live screen. An OWN run whose local engine is still alive
/// opens against that engine (full control); everything else — foreign WiFi,
/// foreign BLE, or an own run whose engine is gone — opens the remote view,
/// which renders from the backend feed and routes Pause All / Stop All through
/// the server. (Lifted verbatim from the History Live tab's card.)
void openLiveSession(BuildContext context, WidgetRef ref, ActiveSession session) {
  final localId = ref.read(ownBackendToLocalSessionProvider)[session.id];
  ActiveSession? local;
  if (localId != null) {
    for (final s in ref.read(activeSessionsProvider)) {
      if (s.id == localId) {
        local = s;
        break;
      }
    }
  }

  if (session.isOwn && isVisibleActiveSession(session) && local != null) {
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
          'protocolPlusId': local.protocolPlusBindings.first['plusId'] ?? '',
        },
      },
    );
    return;
  }

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

/// The live-session strip that sits directly above "Select User" on the session
/// page. Collapses to nothing when no session is running — live runs are
/// surfaced here, where sessions are started, rather than in Session History.
class LiveSessionsBanner extends ConsumerWidget {
  const LiveSessionsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A run this phone has already finished is NOT announced as live. The
    // backend keeps a session in `/sessions/active` until it is stopped, so this
    // card used to go on saying "1 session running" — and its devices stayed
    // "In use" — long after the device had stopped and the post-session question
    // had been answered. The engine now POSTs the stop on the terminal
    // transition, so the feed drops it within a poll; this filter just closes
    // the gap in between rather than being the fix on its own.
    final finishedIds = ref.watch(finishedOwnSessionIdsProvider);
    final sessions = ref
        .watch(liveSessionsProvider)
        .where(isVisibleActiveSession)
        .where((s) => !finishedIds.contains(s.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (sessions.isEmpty) return const SizedBox.shrink();

    final p = RefPalette.of(context);
    final multiple = sessions.length > 1;
    final accent = p.good;

    final title =
        multiple ? '${sessions.length} sessions running' : '1 session running';
    final subtitle = multiple
        ? 'Tap to view & switch'
        : '${_sessionLabel(sessions.first)} — tap to view';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => multiple
              ? _showLiveSessionPicker(context, ref, sessions)
              : openLiveSession(context, ref, sessions.first),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.55)),
              boxShadow: p.shadow,
            ),
            child: Row(
              children: [
                _LivePulse(color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: p.goodSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Session name for the banner/picker — the Protocol Plus template name for a
/// stacked run, else the protocol the backend reports.
String _sessionLabel(ActiveSession session) {
  final plus = session.protocolPlusName.trim();
  if (session.protocolPlusActive && plus.isNotEmpty) return plus;
  final name = session.protocolName.trim();
  return name.isEmpty ? 'Session' : name;
}

String _formatElapsed(Duration d) {
  final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Picker shown when more than one session is live — pick which one to open.
Future<void> _showLiveSessionPicker(
  BuildContext context,
  WidgetRef ref,
  List<ActiveSession> sessions,
) {
  final p = RefPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Running sessions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 10),
              for (final session in sessions) ...[
                _LiveSessionRow(
                  session: session,
                  palette: p,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openLiveSession(context, ref, session);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _LiveSessionRow extends StatelessWidget {
  final ActiveSession session;
  final RefPalette palette;
  final VoidCallback onTap;

  const _LiveSessionRow({
    required this.session,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final paused = session.status == SessionStatus.paused;
    final devices = session.deviceIds.length;
    final subline = [
      '$devices ${devices == 1 ? 'device' : 'devices'}',
      _formatElapsed(DateTime.now().difference(session.createdAt)),
      if (paused) 'Paused',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.cardline),
          ),
          child: Row(
            children: [
              _LivePulse(color: paused ? p.ink3 : p.good),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sessionLabel(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subline,
                      style: TextStyle(fontSize: 12.5, color: p.ink3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The green "live" dot, with the soft halo the handoff design uses.
class _LivePulse extends StatelessWidget {
  final Color color;
  const _LivePulse({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
