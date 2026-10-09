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
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/org_switch_sheet.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../history/data/history_repository.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../payments/presentation/widgets/token_balance_badge.dart';
import '../../../session/domain/active_session_model.dart';
// Needed again if the Active devices card is re-enabled in _HubBody.
// import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/presentation/widgets/live_sessions_banner.dart';
import '../../../session/presentation/widgets/smoothed_countdown.dart';
import '../providers/hub_prefs_provider.dart';
import '../widgets/hub_modules.dart';
import '../widgets/hub_motion.dart';

/// The Hub — nav tab 0, ported from the v6 practitioner-app prototype
/// (hydrawav3-app `hydrawav3-pro-v6.html`: the v4 Hub, v5 `10-hub.js` section
/// headings / sticky bar / S·M·L sizes, v5.1 merged header, v6 bell).
///
/// Every number on this screen comes from a live provider. Where the data
/// doesn't exist yet the card renders its empty-state copy; nothing here is
/// seeded or estimated.
class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  final _scroll = ScrollController();

  /// Drives the wordmark fade/parallax and the sticky bar. Kept in a
  /// ValueNotifier so scrolling repaints small widgets, not the whole Hub.
  final _scrollOffset = ValueNotifier<double>(0);

  /// The section currently under the sticky bar (scroll-spy).
  final _current = ValueNotifier<HubModule?>(null);

  final _sectionKeys = {for (final m in HubModule.values) m: GlobalKey()};
  final _stackKey = GlobalKey();

  static const double _barHeight = 52;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrollOffset.dispose();
    _current.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scrollOffset.value = _scroll.offset;
    _spy();
  }

  List<HubModule> get _visible => ref.read(hubOrderProvider);

  /// Picks the last section whose top has passed under the bar; at the very
  /// bottom of the page the last section wins even if it is short.
  void _spy() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;
    final line = MediaQuery.paddingOf(context).top + _barHeight + 20;
    HubModule? cur;
    for (final m in _visible) {
      final box =
          _sectionKeys[m]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero, ancestor: stackBox).dy;
      if (cur == null || top <= line) cur = m;
      if (top > line) break;
    }
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 4 &&
        _visible.isNotEmpty) {
      cur = _visible.last;
    }
    if (cur != _current.value) _current.value = cur;
  }

  void _jumpTo(HubModule m) {
    final ctx = _sectionKeys[m]!.currentContext;
    if (ctx == null) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final box = ctx.findRenderObject() as RenderBox;
    final stackBox = _stackKey.currentContext!.findRenderObject() as RenderBox;
    final top = box.localToGlobal(Offset.zero, ancestor: stackBox).dy;
    final target = (_scroll.offset +
            top -
            MediaQuery.paddingOf(context).top -
            _barHeight -
            8)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (still) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 420), curve: HwMotion.ease);
    }
  }

  void _toTop() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 420), curve: HwMotion.ease);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(allSessionsProvider);
    ref.invalidate(clientListProvider);
    ref.invalidate(notificationsProvider);
    await ref.read(allSessionsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final editing = ref.watch(hubEditModeProvider);

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        key: _stackKey,
        children: [
          // Drifting copper glow behind everything (light theme).
          const Positioned.fill(child: HubAmbientGlow()),
          RefreshIndicator(
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
                      // 18px gutters on a phone; on a tablet the content sits
                      // in the centred 786px "wide" column (97-tablet.js).
                      // 108px at the bottom clears the nav.
                      padding: EdgeInsets.fromLTRB(
                        HwTablet.sidePadding(context),
                        0,
                        HwTablet.sidePadding(context),
                        108,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Wordmark(offset: _scrollOffset),
                          // The greeting assembles once per visit: avatar
                          // pops, the text slides in, the buttons pop.
                          const HubReveal(
                            lift: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [_GreetingBar(), _ContextChips()],
                            ),
                          ),
                          if (editing)
                            const _HubEditList()
                          else
                            _HubBody(sectionKeys: _sectionKeys),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _StickyBar(
            offset: _scrollOffset,
            current: _current,
            editing: editing,
            onTop: _toTop,
            onJump: _jumpTo,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header chrome
// ---------------------------------------------------------------------------

/// The brand wordmark, which fades out over the first 70px of scroll and
/// parallaxes up as it goes.
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
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -math.min(math.max(t, 0), 90) * 0.35),
            child: child,
          ),
        );
      },
      // Same wordmark size as the Session Plan header: 236px wide.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Center(
          child: SizedBox(
            width: 236,
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
        ),
      ),
    );
  }
}

/// One Hub header (v5.1): identity block (greeting + date) on the left, the
/// notification bell and Customize Hub on the right.
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
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HubPop(
            startMs: 120,
            child: Semantics(
              button: true,
              label: 'Account & settings',
              child: HwPress(
                onTap: () => context.go(RoutePaths.settings),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontSize: HwType.md,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2B1D12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s3),
          Expanded(
            child: HubSlideIn(
              startMs: 180,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
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
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w600,
                        color: p.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          const HubPop(startMs: 300, child: _Bell()),
          const SizedBox(width: HwSpace.s2),
          HubPop(
            startMs: 340,
            child: _HeaderIconButton(
              icon: editing ? HwIcons.check : HwIcons.sliders,
              label: editing ? 'Done customizing' : 'Customize Hub',
              active: editing,
              onTap: () =>
                  ref.read(hubEditModeProvider.notifier).state = !editing,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? badge;

  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: HwPress(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? p.copper : p.line,
                    width: active ? 1.5 : 1,
                  ),
                  boxShadow: p.shadow,
                ),
                child: Center(
                  child: HwIcon(icon,
                      size: 19, color: active ? p.copperInk : p.ink2),
                ),
              ),
              if (badge != null) Positioned(top: 7, right: 7, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}

/// v6: the bell returns to the Hub header. The bell itself is ink; the dot is
/// the only copper, because the dot is what asks you to act.
class _Bell extends ConsumerWidget {
  const _Bell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final n = ref.watch(unreadNotificationCountProvider);
    return _HeaderIconButton(
      icon: HwIcons.bell,
      label:
          n > 0 ? 'Notifications, $n unread' : 'Notifications, all caught up',
      onTap: () => context.go(RoutePaths.notifications),
      badge: n == 0
          ? null
          : Container(
              constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
              padding: EdgeInsets.symmetric(horizontal: n > 9 ? 3 : 0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                ),
                borderRadius: BorderRadius.circular(HwRadius.pill),
                border: Border.all(color: p.card, width: 2),
              ),
              child: n > 9
                  ? const Text(
                      '9+',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2B1D12),
                      ),
                    )
                  : null,
            ),
    );
  }
}

/// The context row under the greeting: organization + plan credits.
class _ContextChips extends StatelessWidget {
  const _ContextChips();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(2, 0, 2, 14),
      child: Row(
        children: [
          Flexible(child: HubSlideIn(startMs: 260, child: _OrgChip())),
          SizedBox(width: 8),
          // The shared plan badge — tapping opens the plan sheet in place.
          HubPop(startMs: 360, child: TokenBalanceBadge()),
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
      // Switching happens right here in a sheet — the practitioner stays on
      // the Hub instead of bouncing to another tab.
      onTap: () => showOrgSwitchSheet(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.chipBg,
              borderRadius: BorderRadius.circular(HwRadius.pill),
              border: Border.all(color: p.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: p.good, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    org,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.cap,
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky condensed header (v5 `.v5h-bar`): appears once the greeting has
// scrolled away, names the section you're in, and jumps between sections.
// ---------------------------------------------------------------------------

class _StickyBar extends ConsumerStatefulWidget {
  final ValueNotifier<double> offset;
  final ValueNotifier<HubModule?> current;
  final bool editing;
  final VoidCallback onTop;
  final ValueChanged<HubModule> onJump;

  const _StickyBar({
    required this.offset,
    required this.current,
    required this.editing,
    required this.onTop,
    required this.onJump,
  });

  @override
  ConsumerState<_StickyBar> createState() => _StickyBarState();
}

class _StickyBarState extends ConsumerState<_StickyBar> {
  bool _menu = false;

  static const double _threshold = 190;

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final visible = ref.watch(hubOrderProvider);

    return ValueListenableBuilder<double>(
      valueListenable: widget.offset,
      builder: (context, off, _) {
        final show = off > _threshold;
        if (!show && _menu) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _menu = false);
          });
        }
        return Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            ignoring: !show,
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, -1.05),
              duration: const Duration(milliseconds: 280),
              curve: HwMotion.ease,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: HwMotion.t2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(
                          HwTablet.sidePadding(context),
                          top,
                          HwTablet.sidePadding(context, phone: 14),
                          0),
                      decoration: BoxDecoration(
                        color: p.bg.withValues(alpha: .96),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(31, 43, 51, .08),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: _HubScreenState._barHeight,
                            child: Row(
                              children: [
                                _HubPill(onTap: () {
                                  setState(() => _menu = false);
                                  widget.onTop();
                                }),
                                const SizedBox(width: 10),
                                Container(width: 1, height: 20, color: p.line),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ValueListenableBuilder<HubModule?>(
                                    valueListenable: widget.current,
                                    builder: (context, cur, _) {
                                      final title = widget.editing
                                          ? 'Customize Hub'
                                          : (cur == null
                                              ? ''
                                              : kHubModuleMeta[cur]!.label);
                                      final pos = cur == null
                                          ? ''
                                          : '${visible.indexOf(cur) + 1}/${visible.length}';
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: widget.editing
                                            ? null
                                            : () =>
                                                setState(() => _menu = !_menu),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 280),
                                                transitionBuilder:
                                                    (child, anim) =>
                                                        FadeTransition(
                                                  opacity: anim,
                                                  child: SlideTransition(
                                                    position: Tween(
                                                      begin:
                                                          const Offset(0, .35),
                                                      end: Offset.zero,
                                                    ).animate(anim),
                                                    child: child,
                                                  ),
                                                ),
                                                child: Text(
                                                  title,
                                                  key: ValueKey(title),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: HwType.md,
                                                    fontWeight: FontWeight.w800,
                                                    color: p.ink,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (!widget.editing) ...[
                                              const SizedBox(width: 6),
                                              AnimatedRotation(
                                                turns: _menu ? .5 : 0,
                                                duration: HwMotion.t2,
                                                child: HwIcon(HwIcons.caret,
                                                    size: 14,
                                                    color: p.copperInk),
                                              ),
                                            ],
                                            const Spacer(),
                                            Text(
                                              widget.editing ? '' : pos,
                                              style: TextStyle(
                                                fontSize: HwType.cap,
                                                fontWeight: FontWeight.w700,
                                                color: p.ink3,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Copper hairline, fading out at both ends.
                          const SizedBox(
                            height: 1.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color.fromRGBO(198, 158, 131, 0),
                                    Color(0xFFC69E83),
                                    Color(0xFFC69E83),
                                    Color.fromRGBO(198, 158, 131, 0),
                                  ],
                                  stops: [0, .3, .7, 1],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_menu)
                      _JumpMenu(
                        sections: visible,
                        current: widget.current.value,
                        onPick: (m) {
                          setState(() => _menu = false);
                          widget.onJump(m);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HubPill extends StatelessWidget {
  final VoidCallback onTap;
  const _HubPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back to top',
      child: HwPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFDEB393),
                    Color(0xFFC69E83),
                    Color(0xFFB27D5C)
                  ],
                ),
                borderRadius: BorderRadius.circular(HwRadius.pill),
              ),
              child: const Text(
                'HUB',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.15,
                  color: Color(0xFF2B1D12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JumpMenu extends StatelessWidget {
  final List<HubModule> sections;
  final HubModule? current;
  final ValueChanged<HubModule> onPick;

  const _JumpMenu({
    required this.sections,
    required this.current,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
          boxShadow: p.shadowLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in sections)
              HwPress(
                scale: .98,
                onTap: () => onPick(m),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: m == current ? p.tanSoft : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    kHubModuleMeta[m]!.label,
                    style: TextStyle(
                      fontSize: HwType.base,
                      fontWeight: FontWeight.w600,
                      color: m == current
                          ? (dark
                              ? const Color(0xFFDDCABF)
                              : const Color(0xFF6E4A33))
                          : p.ink,
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
// Body — live/offline notices, then the customizable module stack
// ---------------------------------------------------------------------------

class _HubBody extends ConsumerWidget {
  final Map<HubModule, GlobalKey> sectionKeys;
  const _HubBody({required this.sectionKeys});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(hubLayoutProvider);
    final order = ref.watch(hubOrderProvider);
    final online = ref.watch(isOnlineProvider);
    // Active devices card hidden from the Hub for now (kept, not deleted —
    // uncomment these two lines to bring it back).
    // final live = ref.watch(liveSessionsProvider);

    final children = <Widget>[
      if (!online) const _OfflineBanner(),
      // if (live.isNotEmpty) _ActiveDevicesCard(live),
    ];
    Widget section(int i, HubModule m, {required EdgeInsets padding}) {
      return Padding(
        key: sectionKeys[m],
        padding: padding,
        child: Semantics(
          container: true,
          label: kHubModuleMeta[m]!.label,
          // Springs up as it scrolls into view; the ones on screen at first
          // paint stagger 90ms apart.
          child: HubReveal(order: i, child: HubModuleView(m, layout.sizeOf(m))),
        ),
      );
    }

    // Tablet: the Hub becomes a board — widgets side by side, as many
    // columns as fit at 340px each, with the first widget (Quick Start)
    // keeping the full width (97-tablet.js §2).
    if (HwTablet.of(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          HwAutoGrid(
            fullWidth: const {0},
            children: [
              for (final (i, m) in order.indexed)
                section(i, m, padding: EdgeInsets.zero),
            ],
          ),
        ],
      );
    }

    for (final (i, m) in order.indexed) {
      final size = layout.sizeOf(m);
      final first = children.isEmpty;
      // Sections breathe: 24px between widgets, 14 above a compact row.
      children.add(section(i, m,
          padding: EdgeInsets.only(
              top: first ? 0 : (size == HubSize.small ? 14 : 24))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: p.midSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          HwIcon(HwIcons.offline, size: 16, color: p.mid),
          const SizedBox(width: HwSpace.s2),
          Expanded(
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(
                    text: 'Offline',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(
                    text: ' · showing cached data. Sessions still run over '
                        'Bluetooth.'),
              ]),
              style: TextStyle(fontSize: HwType.cap, height: 1.4, color: p.mid),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live runs, straight off the backend feed the nav badge already uses. Quick
/// Start marks its own units Live; this card also covers WiFi units and runs
/// started from the web or another phone.
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
    final p = RefPalette.of(context);
    // One row per running unit — a Duo/Studio run shows both pads separately.
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color.fromRGBO(63, 143, 107, .35)),
        boxShadow: p.shadow,
      ),
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
  /// [remaining] exactly as given rather than ticking it down locally.
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
    return HwRow(
      leading: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7FC2A3), Color(0xFF3F8F6B)],
          ),
        ),
        child: Center(
          child: Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: SmoothedCountdown(
        remaining: Duration(seconds: remaining < 0 ? 0 : remaining),
        frozen: frozen,
        builder: (context, liveRemaining) => HwPill(
          _ActiveDevicesCard._mmss(liveRemaining.inSeconds),
          tone: HwPillTone.good,
          tabular: true,
        ),
      ),
      // Straight into the live session (own engine if this phone owns it, the
      // remote view otherwise) — the fastest way to a manual Stop, which
      // matters most for a run that outlived its timer (see the overrun
      // watchdog in live_sessions_provider.dart).
      onTap: () => openLiveSession(context, ref, session),
    );
  }
}

// ---------------------------------------------------------------------------
// Customize Hub — reorder, S / M / L per tile, hide / restore
// ---------------------------------------------------------------------------

class _HubEditList extends ConsumerWidget {
  const _HubEditList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final layout = ref.watch(hubLayoutProvider);
    final notifier = ref.read(hubLayoutProvider.notifier);
    final visible = layout.visible;
    final hidden = HubModule.values.where(layout.hidden.contains).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MotionSwitchCard(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: p.tanSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text.rich(
            const TextSpan(children: [
              TextSpan(
                text: 'Customize your Hub. ',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: 'Drag ⠿ to reorder, pick S / M / L for each tile, or '
                    'hide it. Hidden tiles restore below.',
              ),
            ]),
            style: TextStyle(
                fontSize: HwType.cap, height: 1.5, color: p.copperInk),
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
            final meta = kHubModuleMeta[m]!;
            final size = layout.sizeOf(m);
            return Padding(
              key: ValueKey(m),
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.line),
                  boxShadow: p.shadow,
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: SizedBox(
                        width: 36,
                        height: 44,
                        child: Center(
                          child: HwIcon(HwIcons.drag, size: 18, color: p.ink3),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.label,
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
                            kHubSizeCaption[size]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: HwType.cap, color: p.ink3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SizeSegment(
                      value: size,
                      dark: dark,
                      onChanged: (s) => notifier.setSize(m, s),
                    ),
                    const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: 'Hide ${meta.label}',
                      child: HwPress(
                        onTap: () => notifier.setHidden(m, true),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: p.line),
                              ),
                              child: Center(
                                child:
                                    HwIcon(HwIcons.x, size: 14, color: p.ink3),
                              ),
                            ),
                          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
            child: Text(
              'HIDDEN TILES',
              style: TextStyle(
                fontSize: HwType.eyebrow,
                fontWeight: FontWeight.w800,
                letterSpacing: .88,
                color: p.ink3,
              ),
            ),
          ),
          for (final m in hidden)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: .85,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    children: [
                      HwIcon(kHubModuleMeta[m]!.icon, size: 19, color: p.ink3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          kHubModuleMeta[m]!.label,
                          style: TextStyle(
                            fontSize: HwType.base,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                      ),
                      HwPress(
                        onTap: () => notifier.setHidden(m, false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: p.tanSoft,
                            borderRadius: BorderRadius.circular(HwRadius.pill),
                          ),
                          child: Text(
                            'Restore',
                            style: TextStyle(
                              fontSize: HwType.cap,
                              fontWeight: FontWeight.w700,
                              color: p.copperInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        HwPress(
          onTap: () => ref.read(hubEditModeProvider.notifier).state = false,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFDEB393),
                  Color(0xFFC69E83),
                  Color(0xFFB27D5C)
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: HwType.base,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2B1D12),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        HwPress(
          onTap: notifier.reset,
          child: SizedBox(
            height: 44,
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
        ),
      ],
    );
  }
}

/// S / M / L radio segment (v5 `.v5h-eseg`).
class _SizeSegment extends StatelessWidget {
  final HubSize value;
  final bool dark;
  final ValueChanged<HubSize> onChanged;

  const _SizeSegment({
    required this.value,
    required this.dark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    const letters = {
      HubSize.small: 'S',
      HubSize.medium: 'M',
      HubSize.large: 'L'
    };
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in HubSize.values)
            Semantics(
              selected: s == value,
              button: true,
              label: kHubSizeCaption[s],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: HwMotion.t2,
                  width: 30,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: s == value
                        ? (dark
                            ? const LinearGradient(
                                colors: [Color(0xFFDEB393), Color(0xFFB27D5C)])
                            : p.heroGrad)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      letters[s]!,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w800,
                        color: s == value
                            ? (dark
                                ? const Color(0xFF2B1D12)
                                : const Color(0xFFF2E9E2))
                            : p.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Hub animations" — the switch at the top of Customize Hub.
class _MotionSwitchCard extends ConsumerWidget {
  const _MotionSwitchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = ref.watch(hubMotionProvider);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
        boxShadow: p.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF32414D), Color(0xFF243039)]
                    : const [Color(0xFFEFE4D9), Color(0xFFDCCBBD)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: HwIcon(HwIcons.star,
                  size: 17,
                  color:
                      dark ? const Color(0xFFD8C6B6) : const Color(0xFF6B4A32)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hub animations',
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  reduced
                      ? 'Reduced motion is on in your device settings'
                      : 'Gentle motion as cards appear, graphs draw and you '
                          'tap',
                  style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: on && !reduced,
            activeTrackColor: const Color(0xFFC69E83),
            onChanged: reduced
                ? null
                : (v) => ref.read(hubMotionProvider.notifier).set(v),
          ),
        ],
      ),
    );
  }
}
