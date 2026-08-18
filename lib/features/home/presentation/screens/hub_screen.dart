import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/connectivity_service.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/org_switch_sheet.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../history/data/history_repository.dart';
import '../../../payments/presentation/widgets/token_balance_badge.dart';
import '../../../session/domain/active_session_model.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/presentation/providers/pending_outcomes_provider.dart';
import '../../../session/presentation/widgets/live_sessions_banner.dart';
import '../../../session/presentation/widgets/smoothed_countdown.dart';
import '../providers/hub_prefs_provider.dart';
import '../providers/hub_stats_provider.dart';
import '../widgets/hub_modules.dart';

/// The Hub — nav tab 0, ported from the UI handoff spec's `renderHome`.
///
/// Every number on this screen comes from a live provider. Where the data
/// doesn't exist yet the card renders the spec's empty-state copy or drops out
/// entirely; nothing here is seeded or estimated.
class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  final _scroll = ScrollController();

  /// Drives the wordmark fade/parallax. Kept in a ValueNotifier so scrolling
  /// repaints one small widget instead of the whole Hub.
  final _scrollOffset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _scrollOffset.value = _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(allSessionsProvider);
    ref.invalidate(clientListProvider);
    await ref.read(allSessionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final editing = ref.watch(hubEditModeProvider);

    return Scaffold(
      backgroundColor: p.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: p.copper,
        backgroundColor: p.card,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  // 18px gutters, and 108px at the bottom to clear the nav.
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Wordmark(offset: _scrollOffset),
                      const _GreetingBar(),
                      const _DateTokenRow(),
                      if (editing)
                        const _HubEditList()
                      else
                        const _HubBody(),
                    ],
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

// ---------------------------------------------------------------------------
// Header chrome
// ---------------------------------------------------------------------------

/// The brand wordmark, which fades out over the first 70px of scroll and
/// parallaxes up as it goes (app.js:4211).
class _Wordmark extends StatelessWidget {
  final ValueNotifier<double> offset;
  const _Wordmark({required this.offset});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<double>(
      valueListenable: offset,
      builder: (context, t, child) {
        final opacity = (1 - t / 70).clamp(0.0, 1.0);
        if (opacity == 0) return const SizedBox(height: 0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -math.min(t, 90) * 0.35),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: ClipRect(
          child: Align(
            alignment: Alignment.center,
            heightFactor: 0.62,
            child: SvgPicture.asset(
              dark
                  ? 'assets/images/Hydrawav3_White_Logo.svg'
                  : 'assets/images/Hydrawav3_Black_Logo.svg',
              fit: BoxFit.fitWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingBar extends ConsumerWidget {
  const _GreetingBar();

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final auth = ref.watch(authStateProvider);
    final editing = ref.watch(hubEditModeProvider);

    final name = (auth.user?.displayName ?? '').trim();
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final initials = name.isEmpty
        ? '?'
        : name
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          HwPress(
            onTap: () => context.go(RoutePaths.settings),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: p.sunGrad,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          // The greeting stays on one line and ellipsises; the org chip lives
          // on its own row beneath so a long org name can never wrap it
          // (Principles §8 rule 4).
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  firstName.isEmpty
                      ? _greeting()
                      : '${_greeting()}, $firstName',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HwType.lg,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 3),
                const _OrgChip(),
              ],
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          HwPress(
            onTap: () => ref.read(hubEditModeProvider.notifier).state = !editing,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: editing ? p.copper : p.cardline,
                  width: editing ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: HwIcon(
                  editing ? HwIcons.check : HwIcons.sliders,
                  size: 19,
                  color: editing ? p.copperInk : p.ink2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgChip extends ConsumerWidget {
  const _OrgChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final org = ref.watch(authStateProvider).selectedOrgName;
    if (org == null || org.isEmpty) return const SizedBox.shrink();

    return HwPress(
      // Switching happens right here in a sheet — the spec deliberately keeps
      // the practitioner on the Hub instead of bouncing them to another tab.
      onTap: () => showOrgSwitchSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: p.chipBg,
          borderRadius: BorderRadius.circular(HwRadius.pill),
          border: Border.all(color: p.cardline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: p.copper,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                org,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HwType.eyebrow,
                  fontWeight: FontWeight.w700,
                  color: p.ink2,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Opacity(
              opacity: .6,
              child: HwIcon(HwIcons.caret, size: 12, color: p.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTokenRow extends ConsumerWidget {
  const _DateTokenRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, HwSpace.s3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DateFormat('EEEE, MMMM d').format(DateTime.now()),
              style: TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
            ),
          ),
          // The shared plan badge — same pill on every screen that carries it.
          // Tapping opens the plan sheet in place; the full plan screen is one
          // step further, behind that sheet's CTA.
          const TokenBalanceBadge(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — conditional cards, then the customizable module stack
// ---------------------------------------------------------------------------

class _HubBody extends ConsumerWidget {
  const _HubBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(hubLayoutProvider);
    final online = ref.watch(isOnlineProvider);
    final live = ref.watch(liveSessionsProvider);
    final pending = ref
        .watch(pendingOutcomesProvider)
        .where((e) => e.answers == null)
        .length;
    final guestToday =
        ref.watch(hubStatsProvider).valueOrNull?.guestToday ?? 0;

    final cards = <Widget>[
      if (!online) const _OfflineBanner(),
      if (live.isNotEmpty) _ActiveDevicesCard(live),
      if (pending > 0) _PendingChecksCard(pending),
      if (guestToday >= 3) _GuestNudge(guestToday),
      for (final m in layout.visible)
        layout.isSmall(m) ? _CompactModule(m) : _module(m),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++)
          HwStagger(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: cards[i],
            ),
          ),
      ],
    );
  }

  Widget _module(HubModule m) {
    switch (m) {
      case HubModule.perfrec:
        return const HubTiles();
      case HubModule.quickpulse:
        return const HubQuickPulse();
      case HubModule.gameday:
        return const HubGameDay();
      case HubModule.week:
        return const HubWeek();
      case HubModule.lastsession:
        return const HubLastSession();
      case HubModule.mobility:
        return const HubMobilityCard();
      case HubModule.labs:
        return const HubLabsCard();
      case HubModule.resources:
        return const HubResources();
    }
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: p.midSoft,
        borderRadius: BorderRadius.circular(HwRadius.lg),
      ),
      child: Row(
        children: [
          HwIcon(HwIcons.offline, size: 16, color: p.mid),
          const SizedBox(width: HwSpace.s2),
          Expanded(
            child: Text(
              'Offline — showing cached data. Sessions still run over '
              'Bluetooth.',
              style: TextStyle(
                fontSize: HwType.cap,
                height: 1.4,
                color: p.mid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live runs, straight off the backend feed the nav badge already uses.
class _ActiveDevicesCard extends StatelessWidget {
  final List<ActiveSession> sessions;
  const _ActiveDevicesCard(this.sessions);

  static String _mmss(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // One row per running unit — a Duo/Studio run shows both pads separately,
    // as the spec's device rail does.
    final rows = <Widget>[];
    for (final s in sessions) {
      if (s.liveDevices.isEmpty) {
        rows.add(_DeviceRow(
          title: s.protocolName,
          subtitle: s.deviceNames.values.join(', '),
          remaining: s.totalDurationSeconds - s.elapsedSeconds,
          session: s,
          frozen: s.status == SessionStatus.paused,
        ));
        continue;
      }
      for (final d in s.liveDevices) {
        rows.add(_DeviceRow(
          title: d.protocol?.isNotEmpty == true ? d.protocol! : s.protocolName,
          subtitle: [d.deviceName, d.bodyPart]
              .where((e) => e != null && e.isNotEmpty)
              .join(' · '),
          remaining: d.remainingSeconds,
          session: s,
          frozen: d.status == SessionStatus.paused,
        ));
      }
    }

    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HwCardHeader(
            'Active devices',
            trailing: HwPill('${rows.length} running', tone: HwPillTone.good),
          ),
          for (final r in rows) r,
        ],
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  final String title;
  final String subtitle;
  final int remaining;
  final ActiveSession session;

  /// True while this device's session is paused — [SmoothedCountdown] shows
  /// [remaining] exactly as given rather than ticking it down locally, so a
  /// paused row's countdown doesn't keep advancing on this screen either.
  final bool frozen;

  const _DeviceRow({
    required this.title,
    required this.subtitle,
    required this.remaining,
    required this.session,
    required this.frozen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    return HwRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: p.sunGrad,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Center(
          child: Text('〰', style: TextStyle(color: Colors.white)),
        ),
      ),
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: SmoothedCountdown(
        remaining: Duration(seconds: remaining < 0 ? 0 : remaining),
        frozen: frozen,
        builder: (context, liveRemaining) => HwPill(
          _ActiveDevicesCard._mmss(liveRemaining.inSeconds),
          tone: HwPillTone.copper,
          tabular: true,
        ),
      ),
      // Straight into the live session (own engine if this phone owns it, the
      // remote view otherwise) rather than the devices list — this row is a
      // live run, and the fastest way to a manual Stop is to open it directly.
      // Matters most for a run that outlived its timer (see the overrun
      // watchdog in live_sessions_provider.dart): that self-heals on its own,
      // but if it hasn't caught up yet this is the manual way out.
      onTap: () => openLiveSession(context, ref, session),
    );
  }
}

class _PendingChecksCard extends ConsumerWidget {
  final int count;
  const _PendingChecksCard(this.count);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    return HwCard(
      accented: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: HwRow(
        leading: HwIcon(HwIcons.chat, size: 19, color: p.copperInk),
        title: '$count session${count == 1 ? '' : 's'} need a quick check',
        subtitle: 'One check each — builds your proof board',
        trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
        onTap: () => context.go(RoutePaths.history),
      ),
    );
  }
}

class _GuestNudge extends StatelessWidget {
  final int count;
  const _GuestNudge(this.count);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(HwSpace.s4),
      decoration: BoxDecoration(
        color: p.tanSoft,
        borderRadius: BorderRadius.circular(HwRadius.lg),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: HwType.cap,
            height: 1.5,
            color: p.copperInk,
          ),
          children: [
            TextSpan(
              text: '$count guest sessions today. ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: 'Tag players and the Game Ready board fills itself — one '
                  "tap on any session's after-screen.",
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact module rows + edit mode
// ---------------------------------------------------------------------------

/// Metadata for the compact ("small") rendering of a resizable module and for
/// the edit list.
class _ModuleMeta {
  final String label;
  final String sub;
  final String icon;
  const _ModuleMeta(this.label, this.sub, this.icon);
}

const Map<HubModule, _ModuleMeta> _kModuleMeta = {
  HubModule.perfrec: _ModuleMeta(
      'Performance & Recovery', 'Guided placement flows', HwIcons.bolt),
  HubModule.quickpulse: _ModuleMeta(
      'Quick Start & Pulse', 'Fast Guest start & proof', HwIcons.play),
  HubModule.gameday:
      _ModuleMeta('Game Day', 'Track the game-day roster', HwIcons.target),
  HubModule.week:
      _ModuleMeta('This week', 'Sessions · Pulse · active days', HwIcons.chart),
  HubModule.lastsession:
      _ModuleMeta('Last session', 'Your most recent session', HwIcons.clock),
  HubModule.mobility:
      _ModuleMeta('AI Mobility Report', 'Map your kinetic chain', HwIcons.star),
  HubModule.labs: _ModuleMeta(
      'Breath Readiness', '60-second breath readiness', HwIcons.flask),
  HubModule.resources: _ModuleMeta(
      'Resources', 'Library, support, rentals', HwIcons.book),
};

class _CompactModule extends ConsumerWidget {
  final HubModule module;
  const _CompactModule(this.module);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final meta = _kModuleMeta[module]!;
    final comingSoon = module == HubModule.mobility;

    return HwCard(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      onTap: comingSoon ? null : () => _open(context, ref),
      child: HwRow(
        leading: HwIcon(meta.icon, size: 19, color: p.copperInk),
        title: meta.label,
        subtitle: meta.sub,
        trailing: comingSoon
            ? const HwComingSoonBanner(compact: true)
            : HwIcon(HwIcons.chev, size: 18, color: p.ink3),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    if (module == HubModule.gameday) {
      context.go(RoutePaths.users);
      return;
    }
    if (module == HubModule.lastsession) {
      context.go(RoutePaths.history);
      return;
    }
    if (module == HubModule.labs) {
      showBreathHowSheet(context);
    }
  }
}

class _HubEditList extends ConsumerWidget {
  const _HubEditList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final layout = ref.watch(hubLayoutProvider);
    final notifier = ref.read(hubLayoutProvider.notifier);
    final visible = layout.visible;
    final hidden =
        layout.order.where((m) => layout.hidden.contains(m)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(HwSpace.s4),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: p.tanSoft,
            borderRadius: BorderRadius.circular(HwRadius.lg),
          ),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  fontSize: HwType.cap, height: 1.5, color: p.copperInk),
              children: const [
                TextSpan(
                  text: 'Customize your Hub. ',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: 'Drag to reorder, resize, or hide tiles — hidden ones '
                      'restore below.',
                ),
              ],
            ),
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: visible.length,
          onReorder: (from, to) {
            // The visible list can be a subset of the full order, so map the
            // visible indices back onto positions in `layout.order`.
            final fromIdx = layout.order.indexOf(visible[from]);
            final toIdx = to >= visible.length
                ? layout.order.length
                : layout.order.indexOf(visible[to]);
            notifier.reorder(fromIdx, toIdx);
          },
          itemBuilder: (context, i) {
            final m = visible[i];
            final meta = _kModuleMeta[m]!;
            final resizable = kResizableModules.contains(m);
            return Padding(
              key: ValueKey(m),
              padding: const EdgeInsets.only(bottom: HwSpace.s2),
              child: HwCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(right: HwSpace.s3),
                        child:
                            HwIcon(HwIcons.drag, size: 18, color: p.ink3),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.label,
                            style: TextStyle(
                              fontSize: HwType.base,
                              fontWeight: FontWeight.w600,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            resizable
                                ? (layout.isSmall(m)
                                    ? 'Compact row'
                                    : 'Large tile')
                                : 'Fixed size',
                            style: TextStyle(
                                fontSize: HwType.eyebrow, color: p.ink3),
                          ),
                        ],
                      ),
                    ),
                    if (resizable)
                      HwPress(
                        onTap: () => notifier.toggleSize(m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(HwRadius.sm),
                            border: Border.all(color: p.cardline),
                          ),
                          child: Text(
                            layout.isSmall(m) ? 'Make large' : 'Make small',
                            style: TextStyle(
                              fontSize: HwType.eyebrow,
                              fontWeight: FontWeight.w700,
                              color: p.ink2,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: HwSpace.s2),
                    HwPress(
                      onTap: () => notifier.setHidden(m, true),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(HwRadius.sm),
                          border: Border.all(color: p.cardline),
                        ),
                        child: Center(
                          child:
                              HwIcon(HwIcons.x, size: 15, color: p.ink3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: HwSpace.s4),
          const HwEyebrow('Hidden tiles'),
          for (final m in hidden)
            Padding(
              padding: const EdgeInsets.only(bottom: HwSpace.s2),
              child: HwCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                child: HwRow(
                  leading: HwIcon(_kModuleMeta[m]!.icon,
                      size: 19, color: p.ink3),
                  title: _kModuleMeta[m]!.label,
                  trailing: HwPress(
                    onTap: () => notifier.setHidden(m, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: p.tanSoft,
                        borderRadius: BorderRadius.circular(HwRadius.sm),
                      ),
                      child: Text(
                        'Restore',
                        style: TextStyle(
                          fontSize: HwType.eyebrow,
                          fontWeight: FontWeight.w700,
                          color: p.copperInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: HwSpace.s4),
        HwPress(
          onTap: () => ref.read(hubEditModeProvider.notifier).state = false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: p.sunGrad,
              borderRadius: BorderRadius.circular(HwRadius.sm),
            ),
            child: const Center(
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: HwType.sm,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        HwPress(
          onTap: notifier.reset,
          child: Center(
            child: Text(
              'Reset to default layout',
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
