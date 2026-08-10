import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../history/domain/session_history_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../providers/hub_prefs_provider.dart';
import '../providers/hub_stats_provider.dart';

// Ring colours are fixed literals in the spec (they read as a legend, not as
// theme roles) — app.js:4014.
const Color _kRingSessions = Color(0xFFA87B5C);
const Color _kRingPulse = Color(0xFF3F8F6B);
const Color _kRingDays = Color(0xFF4E7A8A);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final mode = uri.scheme == 'http' || uri.scheme == 'https'
      ? LaunchMode.inAppBrowserView
      : LaunchMode.externalApplication;
  await launchUrl(uri, mode: mode);
}

// ---------------------------------------------------------------------------
// 1 · Performance & Recovery tiles
// ---------------------------------------------------------------------------

/// The two entry tiles. Both deep-link into the Assistant, which already
/// accepts an `intent` query parameter and drives the guided flow from there.
class HubTiles extends StatelessWidget {
  const HubTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    // IntrinsicHeight bounds the row to its tallest child, which is what lets
    // `stretch` match both tiles. Without it, `stretch` inside a scroll view
    // asks for infinite height and the whole sliver fails to lay out.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Expanded on both sides is the Flutter equivalent of
          // `minmax(0,1fr) minmax(0,1fr)` — Principles §8 rule 1.
          Expanded(
            child: _Tile(
              icon: HwIcons.bolt,
              title: 'Performance',
              body: 'Sport & position → pad placements, in under a minute.',
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFD9B294),
                  Color(0xFFC69E83),
                  Color(0xFFA87B5C)
                ],
                stops: [0, .45, 1],
              ),
              fg: const Color(0xFF2B1D12),
              iconChip: const Color.fromRGBO(255, 255, 255, .32),
              onTap: () =>
                  context.go('${RoutePaths.assistant}?intent=performance'),
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: _Tile(
              icon: HwIcons.wave,
              title: 'Recovery',
              body: 'Where it feels tight → ROM check → targeted pads.',
              gradient: p.heroGrad,
              fg: const Color(0xFFF2E9E2),
              iconChip: const Color.fromRGBO(255, 255, 255, .18),
              onTap: () =>
                  context.go('${RoutePaths.assistant}?intent=recovery'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon;
  final String title;
  final String body;
  final Gradient gradient;
  final Color fg;
  final Color iconChip;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.body,
    required this.gradient,
    required this.fg,
    required this.iconChip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HwPress(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 148),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(HwRadius.lg),
          boxShadow: RefPalette.of(context).shadowLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // The soft glow bleeding off the bottom-right corner (`.tile-glow`).
            Positioned(
              right: -40,
              bottom: -52,
              child: Container(
                width: 130,
                height: 130,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color.fromRGBO(255, 255, 255, .28), Colors.transparent],
                    stops: [0, .7],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconChip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: HwIcon(icon, size: 20, color: fg)),
              ),
            ),
            Positioned(
              top: 16,
              right: 14,
              child: Opacity(
                opacity: .7,
                child: HwIcon(HwIcons.arrow, size: 20, color: fg),
              ),
            ),
            // Content is top-aligned below a reserved icon zone so titles line
            // up across both tiles however long the copy is (§8 rule 3).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 64, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: HwType.lg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.17,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      height: 1.35,
                      color: fg.withValues(alpha: .85),
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
}

// ---------------------------------------------------------------------------
// 2 · Quick Start & Outcome Pulse
// ---------------------------------------------------------------------------

class HubQuickPulse extends StatelessWidget {
  const HubQuickPulse({super.key});

  @override
  Widget build(BuildContext context) {
    // See HubTiles — `stretch` needs a bounded height to resolve against.
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _QuickStartCard()),
          SizedBox(width: HwSpace.s3),
          Expanded(child: _PulseCard()),
        ],
      ),
    );
  }
}

class _QuickStartCard extends ConsumerWidget {
  const _QuickStartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final defaultId = ref.watch(defaultProtocolIdProvider);

    // No default and nothing in recents → there is genuinely nothing to start.
    // Say so and point at the library rather than inventing a protocol.
    if (defaultId == null) {
      return HwCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HwCardHeader('Quick Start'),
            const SizedBox(height: HwSpace.s2),
            Text(
              'Run a session and it becomes your one-tap default.',
              style: TextStyle(
                  fontSize: HwType.cap, height: 1.4, color: p.ink2),
            ),
            const SizedBox(height: HwSpace.s3),
            _HubButton(
              label: 'Browse protocols',
              onTap: () => context.go(RoutePaths.protocols),
              filled: false,
            ),
          ],
        ),
      );
    }

    final protocol = ref.watch(protocolDetailProvider(defaultId));

    return HwCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HwCardHeader(
            'Quick Start',
            trailing: protocol.maybeWhen(
              data: (d) => HwPill(
                '~${(d.apiTotalDurationSeconds / 60).round()}m',
                tone: HwPillTone.copper,
                tabular: true,
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: HwSpace.s2),
          Text(
            protocol.maybeWhen(
              data: (d) => d.templateName,
              orElse: () => '—',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.copperInk,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'your default · Guest · first free unit',
            style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
          ),
          const SizedBox(height: HwSpace.s3),
          _HubButton(
            label: '▶ Start now',
            // Guest is the default for every org (v2 plan §3.1), so this hands
            // the Session tab a protocol and lets the practitioner pick a unit.
            onTap: () {
              ref.read(sessionClientModeProvider.notifier).state =
                  ClientMode.guest;
              ref.read(selectedClientProvider.notifier).state = null;
              context.go(RoutePaths.devices);
            },
          ),
        ],
      ),
    );
  }
}

class _PulseCard extends ConsumerWidget {
  const _PulseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final stats = ref.watch(hubStatsProvider).valueOrNull;
    final pct = stats?.pulsePct;

    return HwCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HwCardHeader(
            'Outcome Pulse',
            trailing: HwPill('proof', tone: HwPillTone.good),
          ),
          const SizedBox(height: HwSpace.s2),
          if (pct == null)
            Text(
              'First checks land after your next session.',
              style: TextStyle(
                  fontSize: HwType.cap, height: 1.4, color: p.ink2),
            )
          else ...[
            HwCountUp(
              pct,
              suffix: '%',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -1,
                color: p.good,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'improved this week · ${stats!.pulseTotal} checks',
              style: TextStyle(
                  fontSize: HwType.eyebrow, height: 1.35, color: p.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Game Day
// ---------------------------------------------------------------------------

class HubGameDay extends ConsumerWidget {
  const HubGameDay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final active = ref.watch(gameDayActiveProvider);

    if (!active) {
      return HwCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HwCardHeader(
              'Game day',
              trailing: _HubButton(
                label: 'Activate',
                compact: true,
                onTap: () => ref.read(gameDayActiveProvider.notifier).activate(),
              ),
            ),
            const SizedBox(height: HwSpace.s2),
            Text(
              "On the day it counts, track who's had their performance "
              "protocol — and who's still to go.",
              style: TextStyle(
                  fontSize: HwType.cap, height: 1.45, color: p.ink2),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HubGameReadyCard(),
        HwPress(
          onTap: () => ref.read(gameDayActiveProvider.notifier).end(),
          child: Padding(
            padding: const EdgeInsets.only(top: HwSpace.s2, left: 2),
            child: Text(
              'End game day',
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w600,
                color: p.ink3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HubGameReadyCard extends ConsumerWidget {
  const HubGameReadyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final board = ref.watch(gameReadyBoardProvider).valueOrNull;

    if (board == null) {
      return const HwCard(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: HwCardHeader('Game Ready'),
      );
    }

    return HwCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HwCardHeader(
            'Game Ready',
            trailing: board.remaining.isEmpty && board.hasRoster
                ? const HwPill('squad prepped ✓', tone: HwPillTone.good)
                : board.hasRoster
                    ? HwPill('${board.remaining.length} to go',
                        tone: HwPillTone.mid)
                    : null,
          ),
          const SizedBox(height: HwSpace.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HwCountUp(
                board.prepped.length,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -1.14,
                  color: p.ink,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'of ${board.total}',
                  style: TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600, color: p.ink3),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'performance-prepped today',
                    style: TextStyle(fontSize: HwType.cap, color: p.ink2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HwSpace.s3),
          HwBar(board.fraction),
          const SizedBox(height: HwSpace.s3),
          if (board.remaining.isNotEmpty) ...[
            Text(
              'Still to prep — tap to set up:',
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
            const SizedBox(height: HwSpace.s2),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount:
                    board.remaining.length > 10 ? 10 : board.remaining.length,
                separatorBuilder: (_, __) => const SizedBox(width: HwSpace.s2),
                itemBuilder: (_, i) => _PlayerCell(board.remaining[i]),
              ),
            ),
          ] else
            Text(
              board.hasRoster
                  ? 'Everyone on this squad has a performance protocol done '
                      'on their body.'
                  : 'No players on the roster yet — sessions run today will '
                      'pitch the board for you.',
              style: TextStyle(
                  fontSize: HwType.cap, height: 1.45, color: p.ink2),
            ),
        ],
      ),
    );
  }
}

class _PlayerCell extends ConsumerWidget {
  final Client client;
  const _PlayerCell(this.client);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: () {
        // Pre-fill the Session tab for this player, exactly as the spec's
        // `prefillSetup(id)` does.
        ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
        ref.read(selectedClientProvider.notifier).state = client;
        context.go(RoutePaths.devices);
      },
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: p.tanSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  _initials(client.displayName),
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                    color: p.copperInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              client.displayName.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 · This week
// ---------------------------------------------------------------------------

class HubWeek extends ConsumerWidget {
  const HubWeek({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final stats = ref.watch(hubStatsProvider).valueOrNull ?? const HubStats();
    final roster = ref.watch(clientListProvider).valueOrNull?.length ?? 0;

    return HwCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HwCardHeader(
            'This week',
            // The spec's honesty cue: these three are measured, and readiness
            // (still experimental) is deliberately not among them.
            trailing: Text(
              'measured, not estimated',
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
          ),
          const SizedBox(height: HwSpace.s2),
          Row(
            children: [
              HwRings([
                HwRingData(stats.sessionsToday.toDouble(),
                    (roster > 8 ? roster : 8).toDouble(), _kRingSessions),
                HwRingData(
                    (stats.pulsePct ?? 0).toDouble(), 100, _kRingPulse),
                HwRingData(stats.activeDays7d.toDouble(), 7, _kRingDays),
              ]),
              const SizedBox(width: HwSpace.s4),
              Expanded(
                child: Column(
                  children: [
                    _LegendRow(_kRingSessions, 'Sessions today',
                        '${stats.sessionsToday}'),
                    _LegendRow(_kRingPulse, 'Outcome Pulse',
                        stats.pulsePct == null ? '—' : '${stats.pulsePct}%'),
                    _LegendRow(_kRingDays, 'Active days · 7d',
                        '${stats.activeDays7d}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _LegendRow(this.color, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5 · Last session
// ---------------------------------------------------------------------------

class HubLastSession extends ConsumerWidget {
  const HubLastSession({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final last = ref.watch(hubStatsProvider).valueOrNull?.lastSession;
    // No history at all → the card simply isn't part of the Hub yet.
    if (last == null) return const SizedBox.shrink();

    final clients = ref.watch(clientListProvider).valueOrNull;
    final name = last.isGuest
        ? 'Guest'
        : clients
                ?.where((c) => c.id == last.clientId)
                .map((c) => c.displayName)
                .firstOrNull ??
            'Client';

    return HwCard(
      onTap: () => context.go(RoutePaths.history),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HwCardHeader(
            'Last session',
            trailing: Text(
              _relativeTime(last.createdAt),
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
          ),
          const SizedBox(height: HwSpace.s3),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: p.tanSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: TextStyle(
                      fontSize: HwType.base,
                      fontWeight: FontWeight.w700,
                      color: p.copperInk,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.base,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sessionLabel(last),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: HwType.eyebrow, color: p.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HwSpace.s2),
              _pulsePill(last),
            ],
          ),
        ],
      ),
    );
  }

  /// Whether the practitioner's before/after check came back better, worse, or
  /// was never captured — the same three states the spec's pill shows.
  Widget _pulsePill(SessionHistoryItem s) {
    var scored = 0;
    var improved = 0;
    for (final d in s.discomfortAreas) {
      if (d.discomfortBefore == null || d.discomfortAfter == null) continue;
      scored++;
      if (d.discomfortAfter! < d.discomfortBefore!) improved++;
    }
    if (scored == 0) return const HwPill('no check');
    return improved > 0
        ? const HwPill('improved ✓', tone: HwPillTone.good)
        : const HwPill('no change', tone: HwPillTone.low);
  }

  String _sessionLabel(SessionHistoryItem s) {
    if (s.protocols.isEmpty) return 'Session';
    final first = s.protocols.first;
    final parts = [first.protocol, first.bodyPart]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    return parts.isEmpty ? 'Session' : parts;
  }

  String _relativeTime(DateTime? at) {
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }
}

// ---------------------------------------------------------------------------
// 6 · AI Mobility Report
// ---------------------------------------------------------------------------

class HubMobilityCard extends StatelessWidget {
  const HubMobilityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      // Flat card surface — the copper border alone carries the emphasis.
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(HwRadius.lg),
        border: Border.all(color: p.copper, width: 1.5),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: p.copper,
                borderRadius: BorderRadius.circular(HwRadius.pill),
              ),
              child: const Text(
                '✦ AI MOBILITY REPORT',
                style: TextStyle(
                  fontSize: HwType.eyebrow,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.99,
                  color: Color(0xFF2B1D12),
                ),
              ),
            ),
          ),
          const SizedBox(height: HwSpace.s3),
          Text(
            'Uncover your full mobility picture',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1.24,
              letterSpacing: -0.19,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'A first-of-its-kind AI assessment maps your whole kinetic chain, '
            'links every area you flagged, and reveals mobility patterns '
            "you've never been able to see or understand before — with "
            'personalized at-home exercises and advisor insights.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: HwType.sm, height: 1.55, color: p.ink2),
          ),
          const SizedBox(height: 15),
          const Center(child: HwComingSoonBanner()),
          const SizedBox(height: 10),
          _HubButton(
            label: '▶ Generate my AI report',
            onTap: null,
          ),
          const SizedBox(height: 9),
          Text(
            'Takes ~3–5 minutes · goes far beyond the instant report',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: HwType.eyebrow,
              fontWeight: FontWeight.w600,
              color: p.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7 · Breath Readiness (Labs)
// ---------------------------------------------------------------------------

const String _kBreathTrackerUrl =
    'https://shivahydrawav3.github.io/cowork-os/parasympathetic-tracker-v5.html';

/// Support line for the Resources tile. The UI spec ships a placeholder number
/// (`tel:+18005550100`, app.js:659) which must never reach a practitioner's
/// dialler — until the real one is set here the tile opens the help centre,
/// where the live contact details are. Set this and it dials directly.
class HubLabsCard extends StatelessWidget {
  const HubLabsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    const cream = Color(0xFFF2E9E2);
    const tan = Color(0xFFDDCABF);

    return Container(
      padding: const EdgeInsets.all(HwSpace.s4),
      decoration: BoxDecoration(
        gradient: p.heroGrad,
        borderRadius: BorderRadius.circular(HwRadius.lg),
        boxShadow: p.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LABS · A FIRST, FOR MOST PEOPLE',
            style: TextStyle(
              fontSize: HwType.eyebrow,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.88,
              color: p.copper,
            ),
          ),
          const SizedBox(height: HwSpace.s2),
          const Text(
            'Ever measured your readiness from your own breath?',
            style: TextStyle(
              fontSize: HwType.lg,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: cream,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '60 seconds, lying down, phone resting on your belly. Your exhale, '
            'inhale and the pauses in between become a Readiness score — no '
            'wearable, nothing strapped on.',
            style: TextStyle(
              fontSize: HwType.cap,
              height: 1.55,
              color: cream.withValues(alpha: .85),
            ),
          ),
          const SizedBox(height: 14),
          // Both actions share one line. The spec splits them 1 : 1.3
          // (app.js:4045) — expressed as flex 10 : 13, since Expanded's flex
          // is an int and defaults to 1.
          Row(
            children: [
              // Ghost-on-dark, so it reads as secondary against the hero fill.
              Expanded(
                flex: 10,
                child: _HubButton(
                  label: 'How it works',
                  filled: false,
                  compactPadding: true,
                  borderColor: const Color.fromRGBO(221, 202, 191, .4),
                  labelColor: tan,
                  onTap: () => showBreathHowSheet(context),
                ),
              ),
              const SizedBox(width: HwSpace.s2),
              Expanded(
                flex: 13,
                child: _HubButton(
                  label: '▶ Try the experiment',
                  compactPadding: true,
                  onTap: () => _openExternal(_kBreathTrackerUrl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Experimental — breath-derived score under validation. Your body '
            'already knows; this just listens.',
            style: TextStyle(
                fontSize: HwType.eyebrow, height: 1.45, color: tan),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8 · Resources
// ---------------------------------------------------------------------------

class HubResources extends ConsumerWidget {
  const HubResources({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final activeLeases = ref
            .watch(clientListProvider)
            .valueOrNull
            ?.where((c) => c.isLeaseActive)
            .length ??
        0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HwEyebrow('Resources'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ResCard(
                  icon: HwIcons.book,
                  title: 'Learn about protocols',
                  sub: "What each does & what's inside",
                  onTap: () => context.go(RoutePaths.protocols),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: _ResCard(
                  icon: HwIcons.phone,
                  title: 'Call customer support',
                  sub: 'Tap for contact options',
                  onTap: () => _openExternal('https://hydrawav3.com/help-center'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ResCard(
                  icon: HwIcons.briefcase,
                  title: 'Business resources',
                  sub: 'hydrawav3.com/help-center',
                  onTap: () =>
                      _openExternal('https://hydrawav3.com/help-center'),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: _ResCard(
                  icon: HwIcons.bag,
                  title: 'Buy more products',
                  sub: 'hydrawav3.com/buy',
                  onTap: () => _openExternal('https://hydrawav3.com/buy'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        // Rental Economics is a full-width row, not a fifth tile.
        HwCard(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          onTap: () => _openExternal('https://hydrawav3.com/economics'),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.tanSoft,
                  borderRadius: BorderRadius.circular(HwRadius.sm),
                ),
                child: Center(
                  child:
                      HwIcon(HwIcons.chart, size: 18, color: p.copperInk),
                ),
              ),
              const SizedBox(width: HwSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rental Economics',
                      style: TextStyle(
                        fontSize: HwType.base,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The numbers behind renting units — payback, margins & '
                      'ROI · hydrawav3.com/economics',
                      style: TextStyle(
                        fontSize: HwType.eyebrow,
                        height: 1.35,
                        color: p.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HwSpace.s2),
              HwIcon(HwIcons.chev, size: 18, color: p.ink3),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Rent & Earn — its own green identity, deliberately distinct from the
        // copper system because it's the one commercial surface on the Hub.
        HwPress(
          onTap: () => context.go(RoutePaths.users),
          child: Container(
            padding: const EdgeInsets.all(HwSpace.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HwRadius.lg),
              boxShadow: p.shadow,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomRight,
                colors: [Color(0xFF274135), Color(0xFF1E2E2A), Color(0xFF192826)],
                stops: [0, .6, 1],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.good,
                    borderRadius: BorderRadius.circular(HwRadius.pill),
                  ),
                  child: const Text(
                    'PASSIVE INCOME',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: Color(0xFF0E1A14),
                    ),
                  ),
                ),
                const SizedBox(height: HwSpace.s3),
                const Text(
                  'Send a unit home. Earn while they recover.',
                  style: TextStyle(
                    fontSize: HwType.lg,
                    fontWeight: FontWeight.w700,
                    height: 1.28,
                    color: Color(0xFFEAF3EC),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Turn an idle device into recurring income — lease it to a '
                  'client for home use, lock it to their account in seconds, '
                  'and get paid while they do the work. Your unit earns even '
                  'while you sleep.',
                  style: TextStyle(
                    fontSize: HwType.cap,
                    height: 1.5,
                    color: Color(0xCCEAF3EC),
                  ),
                ),
                const SizedBox(height: HwSpace.s3),
                _HubButton(
                  // The active-lease count appends to the label, it doesn't
                  // replace "Rent & Earn".
                  label: activeLeases > 0
                      ? 'Start earning · Rent & Earn · $activeLeases active'
                      : 'Start earning · Rent & Earn',
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5FB088), Color(0xFF3F8F6B)],
                  ),
                  onTap: () => context.go(RoutePaths.users),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResCard extends StatelessWidget {
  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  const _ResCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.tanSoft,
              borderRadius: BorderRadius.circular(HwRadius.sm),
            ),
            child: Center(child: HwIcon(icon, size: 18, color: p.copperInk)),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            style: TextStyle(
              fontSize: HwType.sm,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(
                fontSize: HwType.eyebrow, height: 1.35, color: p.ink3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared button
// ---------------------------------------------------------------------------

/// The copper primary button (`--sun-grad`), its ghost variant, and the green
/// Rent & Earn override — one shape, per Principles §5.
class _HubButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool compact;
  final Gradient? gradient;

  /// Ghost-variant overrides, for buttons sitting on a dark card where the
  /// default copper-on-cream hairline would disappear.
  final Color? borderColor;
  final Color? labelColor;

  /// Tighter side padding for buttons sharing a row, so two labels fit on one
  /// line instead of the wider one squeezing the other (Principles §8 rule 2).
  final bool compactPadding;

  const _HubButton({
    required this.label,
    required this.onTap,
    this.filled = true,
    this.compact = false,
    this.gradient,
    this.borderColor,
    this.labelColor,
    this.compactPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final enabled = onTap != null;
    final button = Container(
      width: compact ? null : double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compactPadding ? 8 : (compact ? 14 : 16),
        vertical: compact ? 8 : 11,
      ),
      decoration: BoxDecoration(
        gradient: filled ? (gradient ?? p.sunGrad) : null,
        borderRadius: BorderRadius.circular(HwRadius.sm),
        border: filled ? null : Border.all(color: borderColor ?? p.copper, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        // A button label is always one line; it ellipsises rather than
        // wrapping and pushing the row taller than its sibling.
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: HwType.sm,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : (labelColor ?? p.copperInk),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : .55,
      child: enabled ? HwPress(onTap: onTap!, child: button) : button,
    );
  }
}

/// `breathHowSheet()` — app.js:3514. Explains the breath-readiness experiment
/// in three steps before sending anyone to it.
Future<void> showBreathHowSheet(BuildContext context) {
  final p = RefPalette.of(context);
  const steps = [
    (
      '1',
      'Lie down, phone on your belly',
      'Anywhere quiet. The screen guides you — just breathe normally for '
          'about 60 seconds.'
    ),
    (
      '2',
      'Your breath becomes numbers',
      'Exhale length, inhale length, and the natural pauses between breaths. '
          'Longer exhales and pauses = a more recovered, rest-ready state.'
    ),
    (
      '3',
      'See your Readiness score',
      'A single score with a live view of every breath. Run it before and '
          'after a session and watch what changes — involuntarily.'
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Shown from inside the ShellRoute — see showOrgSwitchSheet.
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
              Text(
                'Readiness from breath — how it works',
                style: TextStyle(
                  fontSize: HwType.lg,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Your phone's motion sensors can feel your belly rise and "
                "fall. That's enough to read your breathing — and your "
                'breathing tells the story of your nervous system.',
                style: TextStyle(
                    fontSize: HwType.eyebrow, height: 1.5, color: p.ink2),
              ),
              const SizedBox(height: 14),
              for (final (n, title, body) in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: p.tanSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            n,
                            style: TextStyle(
                              fontSize: HwType.sm,
                              fontWeight: FontWeight.w800,
                              color: p.copperInk,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: HwType.base,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: HwType.eyebrow,
                                height: 1.5,
                                color: p.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Most people have never seen their own breath measured. It '
                'takes one minute to change that.',
                style: TextStyle(
                    fontSize: HwType.eyebrow, height: 1.5, color: p.ink2),
              ),
              const SizedBox(height: 14),
              _HubButton(
                label: '▶ Try the experiment · ~1 min',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openExternal(_kBreathTrackerUrl);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Experimental — under validation. Wellness insight, not a '
                'medical measurement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: HwType.eyebrow, height: 1.45, color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
