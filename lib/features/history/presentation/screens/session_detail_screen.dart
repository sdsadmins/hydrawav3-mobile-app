import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../data/history_repository.dart';
import '../../domain/session_history_model.dart';

/// One session's record — the UI spec's `openHistDetail()` (app.js:2680).
///
/// Normally the list hands over the model via `extra`; the id path is the
/// fallback for a deep link or a cold start.
class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  final SessionHistoryItem? item;

  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item != null) return _Detail(session: item!);

    final sessionsAsync = ref.watch(allSessionsProvider);
    return sessionsAsync.when(
      loading: () => const _Status('Loading session…'),
      error: (_, __) => const _Status("Couldn't load this session."),
      data: (sessions) {
        for (final s in sessions) {
          if (s.id == sessionId) return _Detail(session: s);
        }
        return const _Status('Session not found.');
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  final SessionHistoryItem session;
  const _Detail({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final clients = ref.watch(clientListProvider).valueOrNull ?? const [];
    final name = session.isGuest
        ? 'Guest'
        : clients
                .where((c) => c.id == session.clientId)
                .map((c) => c.displayName)
                .firstOrNull ??
            'Client';

    final first = session.protocols.isEmpty ? null : session.protocols.first;
    final at = session.createdAt?.toLocal();

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Session detail',
                subtitle: at == null ? null : _stamp(at),
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),

              // Facts — the spec's five non-interactive rows.
              HwRowGroup(children: [
                _Fact('Client', name),
                _Fact('Session', first?.protocol ?? '—'),
                _Fact('Body area', first?.bodyPart ?? '—'),
                _Fact(
                  'Duration',
                  first?.duration == null
                      ? '—'
                      : '${((first!.duration ?? 0) / 60).round()} min',
                ),
                _Fact('Device', first?.deviceName ?? '—'),
              ]),

              // Every scored area, before → after.
              if (session.discomfortAreas.isNotEmpty) ...[
                const SizedBox(height: HwSpace.s2),
                const HwEyebrow('Outcome check'),
                HwCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in session.discomfortAreas)
                        _DiscomfortRow(d),
                    ],
                  ),
                ),
              ],

              if (session.sessionNotes?.isNotEmpty == true) ...[
                const SizedBox(height: HwSpace.s2),
                const HwEyebrow('Notes'),
                HwCard(
                  child: Text(
                    session.sessionNotes!,
                    style: TextStyle(
                        fontSize: HwType.sm, height: 1.5, color: p.ink2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _stamp(DateTime at) {
    two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} · '
        '${two(at.hour)}:${two(at.minute)}';
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.history);
    }
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwRow(
      title: label,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: HwType.cap, color: p.ink2),
        ),
      ),
    );
  }
}

/// `{before} → {after}` with the after-value coloured by its zone — the spec's
/// delta treatment, per body area.
class _DiscomfortRow extends StatelessWidget {
  final HistoryDiscomfort area;
  const _DiscomfortRow(this.area);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final before = area.discomfortBefore;
    final after = area.discomfortAfter;
    final label = [area.bodyPart, area.side]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.isEmpty ? 'Area' : label,
              style: TextStyle(
                fontSize: HwType.base,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
          ),
          if (before == null || after == null)
            const HwPill('not scored')
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$before',
                  style: TextStyle(
                    fontSize: HwType.lg,
                    fontWeight: FontWeight.w600,
                    color: p.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('→', style: TextStyle(color: p.copper)),
                ),
                Text(
                  '$after',
                  style: TextStyle(
                    fontSize: HwType.xl,
                    fontWeight: FontWeight.w800,
                    color: after < before
                        ? p.good
                        : (after > before ? p.low : p.mid),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String message;
  const _Status(this.message);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Session detail',
                onBack: () => _Detail._back(context),
              ),
              const SizedBox(height: 60),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HwType.sm, color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
