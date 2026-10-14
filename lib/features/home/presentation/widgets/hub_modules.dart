import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../../core/theme/widgets/hw_tablet.dart';
import '../../../ble/data/ble_repository.dart';
import '../../../ble/domain/ble_device_model.dart';
import '../../../ble/presentation/providers/ble_connection_provider.dart';
import '../../../clients/domain/client_model.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../devices/data/device_repository.dart';
import '../../../devices/presentation/screens/device_list_screen.dart'
    show sessionDefaultsForProtocol;
import '../../../pad_placement/domain/recovery_engine_models.dart';
import '../../../protocols/domain/protocol_model.dart';
import '../../../protocols/presentation/providers/protocol_provider.dart';
import '../../../session/domain/active_session_model.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../../session/presentation/providers/active_sessions_provider.dart';
import '../../../session/presentation/providers/busy_devices_provider.dart';
import '../../../session/presentation/providers/live_sessions_provider.dart';
import '../../../session/presentation/providers/pending_outcomes_provider.dart';
import '../../../session/presentation/widgets/live_sessions_banner.dart';
import '../../../session/services/protocol_plus_controller.dart'
    show SessionDeviceSelection, launchSession;
import '../providers/hub_prefs_provider.dart';
import '../providers/hub_stats_provider.dart';
import 'hub_motion.dart';

// ===========================================================================
// The v6 Hub widgets — ported from the hydrawav3-app prototype
// (`hydrawav3-pro-v6.html` v4 layer, `hydrawav3-v5/10-hub.js`,
// `hydrawav3-v6/40-copper.js`).
//
// One grammar everywhere: a card whose heading lives inside it (warm icon
// tile · title · helper · optional link, over a copper-led underline), then
// the body. Every module renders Small (one-line row), Medium (condensed) or
// Large (full widget), picked in Customize Hub.
//
// v6 colour rule: copper means "act on this" or "this is selected". Icon tiles
// and markers use the warm tan tint; labels and numbers are ink.
// ===========================================================================

/// v6 tokens the shared palette doesn't carry.
class _V6 {
  final bool dark;
  const _V6(this.dark);

  static _V6 of(BuildContext context) =>
      _V6(Theme.of(context).brightness == Brightness.dark);

  /// `--warm-tile`: decorative icon tiles and section marks.
  Gradient get warmTile => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xFF32414D), Color(0xFF243039)]
            : const [Color(0xFFEFE4D9), Color(0xFFDCCBBD)],
      );

  /// `--warm-ink`: the glyph on a warm tile.
  Color get warmInk => dark ? const Color(0xFFD8C6B6) : const Color(0xFF6B4A32);

  /// Links and small copper actions, legible on the surface.
  Color get link => dark ? const Color(0xFFC69E83) : const Color(0xFF8A5F42);

  /// `--pro-activate`: the Default protocol strip in Quick Start.
  Color get protoBg => dark ? const Color(0xFF2A2521) : const Color(0xFFF0E4DE);

  /// The unselected device puck.
  Color get puckOff => dark ? const Color(0xFF2A3037) : const Color(0xFFEDE5DD);
  Color get puckOffDot =>
      dark ? const Color(0xFF6B7280) : const Color(0xFFB8AA9C);

  static const Color cream = Color(0xFFF2E9E2);
  static const Color tan = Color(0xFFDDCABF);
  static const Color copperText = Color(0xFF2B1D12);

  /// `--sun-grad` as v6 draws it: 100deg, three stops.
  static const Gradient sun = LinearGradient(
    begin: Alignment(-1, -.2),
    end: Alignment(1, .2),
    colors: [Color(0xFFDEB393), Color(0xFFC69E83), Color(0xFFB27D5C)],
    stops: [0, .45, 1],
  );

  /// `--perf-grad`: the Athlete Readiness card.
  static const Gradient perf = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD6AC8E), Color(0xFFBF9375), Color(0xFF9B7660)],
    stops: [0, .5, 1],
  );

  /// `.btn.primary` shadow — the action keeps its weight (40-copper).
  static const List<BoxShadow> actionShadow = [
    BoxShadow(
      color: Color.fromRGBO(168, 123, 92, .55),
      blurRadius: 20,
      spreadRadius: -8,
      offset: Offset(0, 8),
    ),
  ];
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

// ---------------------------------------------------------------------------
// Module metadata (labels for the section bar, the jump menu and Customize)
// ---------------------------------------------------------------------------

class HubModuleMeta {
  final String label;
  final String icon;
  const HubModuleMeta(this.label, this.icon);
}

const Map<HubModule, HubModuleMeta> kHubModuleMeta = {
  HubModule.quick: HubModuleMeta('Quick Start', HwIcons.play),
  HubModule.recovery: HubModuleMeta('Support Recovery', HwIcons.wave),
  HubModule.athlete:
      HubModuleMeta('Athlete Readiness & Performance', HwIcons.bolt),
  HubModule.gameprep: HubModuleMeta('Game Prep', HwIcons.target),
  HubModule.usage: HubModuleMeta('Usage Statistics', HwIcons.chart),
  HubModule.learn: HubModuleMeta('Learn About Protocols', HwIcons.book),
  HubModule.lease: HubModuleMeta('Lease a Device', HwIcons.home2),
};

const Map<HubSize, String> kHubSizeCaption = {
  HubSize.small: 'Small · compact row',
  HubSize.medium: 'Medium · condensed',
  HubSize.large: 'Large · full widget',
};

/// Renders one Hub module at its chosen size.
class HubModuleView extends StatelessWidget {
  final HubModule module;
  final HubSize size;
  const HubModuleView(this.module, this.size, {super.key});

  @override
  Widget build(BuildContext context) {
    switch (module) {
      case HubModule.quick:
        return HubQuickStart(size);
      case HubModule.recovery:
        return HubRecovery(size);
      case HubModule.athlete:
        return HubAthlete(size);
      case HubModule.gameprep:
        return HubGamePrep(size);
      case HubModule.usage:
        return HubUsage(size);
      case HubModule.learn:
        return HubLearn(size);
      case HubModule.lease:
        return HubLease(size);
    }
  }
}

// ---------------------------------------------------------------------------
// Section shell: card surface + embedded heading
// ---------------------------------------------------------------------------

enum _Surface { plain, hero, perf, lease }

class _Section extends StatelessWidget {
  final _Surface surface;
  final String title;
  final String icon;
  final String helper;
  final String? linkLabel;
  final VoidCallback? onLink;
  final Widget body;
  final EdgeInsets padding;

  /// Optional decoration painted behind the content (the Lease art).
  final Widget? backdrop;

  const _Section({
    this.surface = _Surface.plain,
    required this.title,
    required this.icon,
    required this.helper,
    this.linkLabel,
    this.onLink,
    required this.body,
    this.padding = const EdgeInsets.all(14),
    this.backdrop,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    final decoration = switch (surface) {
      _Surface.plain => BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
          boxShadow: p.shadow,
        ),
      _Surface.hero => BoxDecoration(
          gradient: p.heroGrad,
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
      _Surface.perf => BoxDecoration(
          gradient: _V6.perf,
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
      _Surface.lease => BoxDecoration(
          gradient: p.heroGrad,
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
    };

    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            surface: surface,
            title: title,
            icon: icon,
            helper: helper,
            linkLabel: linkLabel,
            onLink: onLink,
          ),
          body,
        ],
      ),
    );

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: surface == _Surface.lease || backdrop != null
          ? Stack(
              children: [
                if (surface == _Surface.lease)
                  // The copper glow in the top-right corner of the Lease card.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topRight,
                          radius: 1.1,
                          colors: [
                            Color.fromRGBO(198, 158, 131, .34),
                            Color.fromRGBO(198, 158, 131, 0),
                          ],
                          stops: [0, .55],
                        ),
                      ),
                    ),
                  ),
                if (backdrop != null) backdrop!,
                content,
              ],
            )
          : content,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final _Surface surface;
  final String title;
  final String icon;
  final String helper;
  final String? linkLabel;
  final VoidCallback? onLink;

  const _SectionHeading({
    required this.surface,
    required this.title,
    required this.icon,
    required this.helper,
    this.linkLabel,
    this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final onDark = surface == _Surface.hero || surface == _Surface.lease;
    final onPerf = surface == _Surface.perf;

    final titleColor = onDark
        ? _V6.cream
        : onPerf
            ? _V6.copperText
            : p.ink;
    final helperColor = onDark
        ? _V6.cream.withValues(alpha: .65)
        : onPerf
            ? _V6.copperText.withValues(alpha: .72)
            : p.ink3;
    final linkColor = onDark
        ? _V6.tan
        : onPerf
            ? const Color(0xFF5A3B25)
            : v.link;
    final lead = onPerf ? _V6.copperText : p.copper;
    final tail = onPerf
        ? const Color.fromRGBO(43, 29, 18, .22)
        : const Color.fromRGBO(198, 158, 131, .3);

    final markDecoration = onDark
        ? BoxDecoration(
            color: const Color.fromRGBO(255, 255, 255, .14),
            borderRadius: BorderRadius.circular(12),
          )
        : onPerf
            ? BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, .4),
                borderRadius: BorderRadius.circular(12),
              )
            : BoxDecoration(
                gradient: v.warmTile,
                borderRadius: BorderRadius.circular(12),
              );
    final markInk = onDark
        ? _V6.cream
        : onPerf
            ? const Color(0xFF5E3A22)
            : v.warmInk;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HubPop(
                startMs: 180,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: markDecoration,
                  child: Center(child: HwIcon(icon, size: 19, color: markInk)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HubSlideIn(
                      startMs: 140,
                      child: Text(
                        title,
                        style: TextStyle(
                          // Type at arm's length on a tablet (97-tablet §7).
                          fontSize: HwTablet.of(context) ? 21 : 19,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -.19,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      helper,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.sm,
                        height: 1.35,
                        color: helperColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (linkLabel != null && onLink != null) ...[
                const SizedBox(width: 8),
                HwPress(
                  onTap: onLink!,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          linkLabel!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: linkColor,
                          ),
                        ),
                        const SizedBox(width: 2),
                        HwIcon(HwIcons.chev, size: 14, color: linkColor),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Copper-led underline: a solid 44px lead, then a fade. It draws in
          // from the left as the section arrives.
          HubDraw(
            startMs: 250,
            child: SizedBox(
              height: 1.5,
              child: Row(
                children: [
                  Container(width: 44, color: lead),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tail, tail.withValues(alpha: .05)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lighter heading above a Small row: uppercase label + a fading rule.
class HubSmallLabel extends StatelessWidget {
  final String label;
  const HubSmallLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w700,
                letterSpacing: .96,
                color: p.ink3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: SizedBox(
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color.fromRGBO(198, 158, 131, .45),
                    Color.fromRGBO(198, 158, 131, 0),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small size: one compact row with the widget's primary action.
class _SmallRow extends StatelessWidget {
  final String label;
  final String icon;
  final String title;
  final String sub;
  final List<Widget> actions;

  const _SmallRow({
    required this.label,
    required this.icon,
    required this.title,
    required this.sub,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSmallLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.line),
            boxShadow: p.shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: v.warmTile,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: HwIcon(icon, size: 17, color: v.warmInk)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.sm,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                actions[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `.v5h-smbtn` — the pill action on a Small row.
class _PillAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _PillAction(this.label, {this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final enabled = onTap != null;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: primary ? _V6.sun : null,
        color: primary ? null : p.card2,
        borderRadius: BorderRadius.circular(HwRadius.pill),
        border: primary ? null : Border.all(color: p.line),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: TextStyle(
            fontSize: HwType.cap,
            fontWeight: FontWeight.w700,
            color: primary ? _V6.copperText : p.ink,
          ),
        ),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: enabled ? HwPress(onTap: onTap!, child: pill) : pill,
    );
  }
}

/// `.btn.primary` — copper action, dark ink label.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  final bool play;
  final bool arrow;
  final EdgeInsets padding;

  /// A light sweep crosses the button every few seconds (Start Now).
  final bool shimmer;

  /// The arrow nudges sideways every few seconds (Lease).
  final bool nudge;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.expand = true,
    this.play = false,
    this.arrow = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    this.shimmer = false,
    this.nudge = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    const arrowIcon = HwIcon(HwIcons.arrow, size: 16, color: _V6.copperText);
    Widget button = Container(
      width: expand ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        gradient: _V6.sun,
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled ? _V6.actionShadow : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (play) ...[
            const HwIcon(HwIcons.play, size: 14, color: _V6.copperText),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: HwType.base,
                fontWeight: FontWeight.w800,
                color: _V6.copperText,
              ),
            ),
          ),
          if (arrow) ...[
            const SizedBox(width: 6),
            nudge ? const HubNudge(child: arrowIcon) : arrowIcon,
          ],
        ],
      ),
    );
    if (shimmer && enabled) {
      button = HubShimmer(radius: BorderRadius.circular(14), child: button);
    }
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: enabled ? HwPress(onTap: onTap!, child: button) : button,
    );
  }
}

// ===========================================================================
// 1 · Quick Start
// ===========================================================================

/// Paired BLE units; Quick Start lists the ones currently connected.
final hubPairedDevicesProvider = StreamProvider<List<PairedDevice>>((ref) {
  return ref.read(bleRepositoryProvider).watchPairedDevices();
});

class _Unit {
  final PairedDevice device;
  final bool busy;
  final ActiveSession? session;
  const _Unit(this.device, this.busy, this.session);
  String get id => device.id;
}

class _QuickState {
  final List<_Unit> units;
  final Set<String> selected;
  final String? protocolId;
  final Protocol? protocol;
  const _QuickState(this.units, this.selected, this.protocolId, this.protocol);
}

/// Units ready to run (connected over Bluetooth and not in a session) out of
/// every paired unit — the Hub's Quick Start count, for the Assistant's
/// greeting card.
({int ready, int total}) watchHubUnitsReady(WidgetRef ref) {
  final paired = ref.watch(hubPairedDevicesProvider).valueOrNull ?? const [];
  final q = _watchQuick(ref);
  return (ready: q.units.where((u) => !u.busy).length, total: paired.length);
}

_QuickState _watchQuick(WidgetRef ref) {
  final paired = ref.watch(hubPairedDevicesProvider).valueOrNull ?? const [];
  final provisioning = ref.watch(bleProvisioningIdsProvider);
  final live = ref.watch(liveSessionsProvider);

  final units = <_Unit>[];
  for (final d in paired) {
    if (provisioning.contains(d.id)) continue;
    if (ref.watch(bleDeviceStatusProvider(d.id)) !=
        BleConnectionStatus.connected) {
      continue;
    }
    final variants = macAddressVariants(d.id).toSet();
    ActiveSession? session;
    for (final s in live) {
      final ids = {...s.deviceIds, for (final ld in s.liveDevices) ld.deviceId};
      if (ids.any(variants.contains)) {
        session = s;
        break;
      }
    }
    final busy = session != null || ref.watch(isDeviceBusyProvider(d.id));
    units.add(_Unit(d, busy, session));
  }

  final free = units.where((u) => !u.busy).map((u) => u.id).toSet();
  final chosen = ref.watch(hubQuickStartUnitsProvider);
  // Until the practitioner touches the list, arm the first free unit (v4
  // `v4AutoArm`) so a single-unit start is one tap.
  final selected = chosen == null
      ? (free.isEmpty ? <String>{} : {units.firstWhere((u) => !u.busy).id})
      : chosen.intersection(free);

  final protocolId = ref.watch(defaultProtocolIdProvider);
  final protocol = protocolId == null
      ? null
      : ref.watch(protocolDetailProvider(protocolId)).valueOrNull;

  return _QuickState(units, selected, protocolId, protocol);
}

void _toggleUnit(WidgetRef ref, _QuickState s, String id) {
  final next = {...s.selected};
  next.contains(id) ? next.remove(id) : next.add(id);
  ref.read(hubQuickStartUnitsProvider.notifier).state = next;
}

/// Start Now: a Guest session on every armed unit, running the default
/// protocol, launched right here through the same [launchSession] the Session
/// tab uses (Protocol Plus stacks included) — which then opens the live
/// session. The Session tab's guards apply: a unit that turned busy is
/// skipped, and the plan's concurrent-device limit is enforced.
Future<void> _quickStart(
    BuildContext context, WidgetRef ref, _QuickState s) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  final protocolId = s.protocolId;
  if (protocolId == null) {
    say('Choose a default protocol first.');
    await showDefaultProtocolSheet(context);
    return;
  }

  final busy = ref.read(activeSessionsProvider.notifier).getBusyDevices();
  final ids = [
    for (final u in s.units)
      if (s.selected.contains(u.id) && !u.busy && !busy.contains(u.id)) u.id,
  ];
  if (ids.isEmpty) {
    say('Those units are already running. Select a free unit to start.');
    return;
  }

  final limit = ref.read(planDeviceLimitProvider).valueOrNull;
  if (limit != null && limit > 0) {
    final running = ref.read(liveDeviceCountProvider);
    if (running + ids.length > limit) {
      say('Your plan allows $limit device(s) at a time ($running already '
          'running). Stop a device or upgrade your plan to run more.');
      return;
    }
  }

  final protocol = await ref.read(protocolDetailProvider(protocolId).future);
  if (!context.mounted) return;

  // Quick Start is Guest-only (no intake), over Bluetooth.
  ref.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
  ref.read(selectedClientProvider.notifier).state = null;
  await launchSession(
    ref,
    context,
    selections: [
      for (final id in ids)
        SessionDeviceSelection(
          deviceId: id,
          protocol: protocol,
          advanced: sessionDefaultsForProtocol(protocol),
        ),
    ],
    transport: 'ble',
  );
  ref.read(recentProtocolIdsProvider.notifier).recordUsed(protocol.id);
  // Next time the card re-arms from scratch rather than remembering units
  // that are now running.
  ref.read(hubQuickStartUnitsProvider.notifier).state = null;
}

String _startLabel(int n) => n > 1 ? 'Start $n units' : 'Start Now';

int _mins(Protocol p) => (p.totalDurationSeconds / 60).round();

class HubQuickStart extends ConsumerStatefulWidget {
  final HubSize size;
  const HubQuickStart(this.size, {super.key});

  @override
  ConsumerState<HubQuickStart> createState() => _HubQuickStartState();
}

class _HubQuickStartState extends ConsumerState<HubQuickStart> {
  bool _showAll = false;

  /// True while a launch is in flight — the button reads "Starting…" and
  /// ignores further taps, so one press can't start the units twice.
  bool _starting = false;

  Future<void> _start(_QuickState s) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await _quickStart(context, ref, s);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Start failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _watchQuick(ref);
    final helper =
        '${s.units.length} connected · ${s.selected.length} selected · Guest';
    final start = s.selected.isEmpty || _starting ? null : () => _start(s);

    if (widget.size == HubSize.small) {
      return _SmallRow(
        label: 'Quick Start',
        icon: HwIcons.play,
        title: s.protocol?.templateName ?? 'Choose a default protocol',
        sub: '${s.selected.length} of ${s.units.length} units selected',
        actions: [
          _PillAction(
            _starting
                ? 'Starting…'
                : s.selected.length > 1
                    ? 'Start ${s.selected.length}'
                    : 'Start',
            onTap: start,
            primary: true,
          ),
        ],
      );
    }

    final protoStrip = _DefaultProtocolStrip(state: s);

    if (widget.size == HubSize.medium) {
      return _Section(
        title: 'Quick Start',
        icon: HwIcons.play,
        helper: helper,
        linkLabel: 'Session Plan',
        onLink: () => context.go(RoutePaths.devices),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            protoStrip,
            Row(
              children: [
                Expanded(
                  child: _SelectedChip(
                    selected: s.selected.length,
                    total: s.units.length,
                    onTap: () => context.go(RoutePaths.devices),
                  ),
                ),
                const SizedBox(width: 10),
                _PrimaryButton(
                  label: _starting
                      ? 'Starting…'
                      : s.selected.length > 1
                          ? 'Start ${s.selected.length}'
                          : 'Start Now',
                  onTap: start,
                  expand: false,
                  play: true,
                  shimmer: true,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Large: selected + running units first, then fill to 3 rows.
    var visible = s.units;
    if (!_showAll && visible.length > 3) {
      int rank(_Unit u) => u.busy ? 0 : (s.selected.contains(u.id) ? 1 : 2);
      visible = [...visible]..sort((a, b) => rank(a) - rank(b));
      visible = visible.take(3).toList();
    }

    return _Section(
      title: 'Quick Start',
      icon: HwIcons.play,
      helper: helper,
      linkLabel: 'Session Plan',
      onLink: () => context.go(RoutePaths.devices),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          protoStrip,
          if (s.units.isEmpty)
            const _NoUnits()
          else
            for (final (i, u) in visible.indexed)
              HubCascade(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _UnitRow(
                    unit: u,
                    selected: s.selected.contains(u.id),
                    onTap: u.busy
                        ? (u.session != null
                            ? () => openLiveSession(context, ref, u.session!)
                            : () => context.go(RoutePaths.devices))
                        : () => _toggleUnit(ref, s, u.id),
                  ),
                ),
              ),
          if (s.units.length > 3)
            _MoreUnitsButton(
              label:
                  _showAll ? 'Show fewer' : 'Show all ${s.units.length} units',
              onTap: () => setState(() => _showAll = !_showAll),
            ),
          const SizedBox(height: 10),
          HubCascade(
            index: 0,
            startMs: 600,
            child: _PrimaryButton(
              label: _starting ? 'Starting…' : _startLabel(s.selected.length),
              onTap: start,
              play: true,
              shimmer: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultProtocolStrip extends ConsumerWidget {
  final _QuickState state;
  const _DefaultProtocolStrip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final proto = state.protocol;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HwPress(
        onTap: () => showDefaultProtocolSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: v.protoBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFC69E83), Color(0xFFA87B5C)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: HwIcon(HwIcons.flask, size: 14, color: _V6.copperText),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEFAULT PROTOCOL',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .84,
                        color: p.ink3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      proto?.templateName ??
                          (state.protocolId == null
                              ? 'Choose a default protocol'
                              : 'Loading…'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (proto != null) ...[
                const SizedBox(width: 8),
                Text(
                  '~${_mins(proto)} min',
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ],
              const SizedBox(width: 4),
              HwIcon(HwIcons.chev, size: 16, color: p.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitRow extends ConsumerWidget {
  final _Unit unit;
  final bool selected;
  final VoidCallback onTap;
  const _UnitRow(
      {required this.unit, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final battery = ref.watch(bleBatteryLevelsProvider).valueOrNull?[unit.id];
    final on = selected && !unit.busy;
    final sub = unit.busy
        ? 'Running · tap to view'
        : '${on ? 'Selected' : 'Tap to select'} · Bluetooth';

    return HwPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: HwMotion.t3,
        curve: HwMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: on
              ? (Theme.of(context).brightness == Brightness.dark
                  ? const Color.fromRGBO(198, 158, 131, .10)
                  : const Color(0xFFFBF6F2))
              : p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on || unit.busy
                ? const Color.fromRGBO(198, 158, 131, .55)
                : p.line,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            _Puck(on: on, busy: unit.busy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unit.device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.base,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11.5, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _LocateButton(unit: unit),
            const SizedBox(width: 6),
            if (unit.busy)
              const HwPill('Live', tone: HwPillTone.good)
            else if (battery != null)
              Text(
                '$battery%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: battery <= 20 ? p.low : p.ink3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The selection marker: a small top-down device puck, lit copper when the
/// unit is armed and green while it runs (v5 `.v5h-dev .v4-check`).
class _Puck extends StatelessWidget {
  final bool on;
  final bool busy;
  const _Puck({required this.on, required this.busy});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final puck = _buildPuck(context);
    if (still) return puck;
    // Arming a unit pops the puck (`v5mCheck`: .5 → 1.2 → 1); disarming
    // settles it back (`v5mSettle`). Keyed on the state, so it plays per flip.
    return TweenAnimationBuilder<double>(
      key: ValueKey(on),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: on ? 500 : 350),
      builder: (context, t, child) {
        final s = on
            ? (t < .6 ? .5 + .7 * (t / .6) : 1.2 - .2 * ((t - .6) / .4))
            : .85 + .15 * t;
        return Transform.scale(scale: s, child: child);
      },
      child: puck,
    );
  }

  Widget _buildPuck(BuildContext context) {
    final v = _V6.of(context);
    final lit = on || busy;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? null : v.puckOff,
        gradient: busy
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7FC2A3), Color(0xFF3F8F6B)],
              )
            : on
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                  )
                : null,
        boxShadow: on
            ? const [
                BoxShadow(
                  color: Color.fromRGBO(185, 142, 113, .16),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      // A running unit's puck wears a dashed white rim over the green, which
      // reads as gear teeth — the prototype's `.v4-dev.busy .v4-check`
      // (`border-style: dashed` on a 3px white border).
      child: CustomPaint(
        foregroundPainter: busy ? const _GearRimPainter() : null,
        child: Center(
          child: AnimatedScale(
            scale: lit ? 1.15 : 1,
            duration: const Duration(milliseconds: 450),
            curve: HwMotion.spring,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lit ? Colors.white : v.puckOffDot,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White dashes around the edge of a running unit's puck (see [_Puck]).
class _GearRimPainter extends CustomPainter {
  const _GearRimPainter();

  /// Dashes around the rim; at 26px this matches the prototype's spacing.
  static const int _teeth = 8;
  static const double _width = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - _width / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..color = Colors.white;
    const step = 2 * math.pi / _teeth;
    for (var i = 0; i < _teeth; i++) {
      // Half of each step is dash, half is gap — the green shows through.
      canvas.drawArc(rect, -math.pi / 2 + i * step, step / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(_GearRimPainter old) => false;
}

/// Plays the chime on a unit so the practitioner can find it (BLE
/// `{"beeping": true}`), with the ping rings the prototype draws.
class _LocateButton extends ConsumerStatefulWidget {
  final _Unit unit;
  const _LocateButton({required this.unit});

  @override
  ConsumerState<_LocateButton> createState() => _LocateButtonState();
}

class _LocateButtonState extends ConsumerState<_LocateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );
  bool _sending = false;

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.unit.busy) {
      messenger.showSnackBar(SnackBar(
          content: Text('${widget.unit.device.name} is running a session')));
      return;
    }
    if (_sending) return;
    _sending = true;
    _ping.forward(from: 0);
    messenger.showSnackBar(SnackBar(
        content:
            Text('Locating ${widget.unit.device.name}: listen for the chime')));
    try {
      await ref
          .read(deviceRepositoryProvider)
          .locateDeviceViaBle(widget.unit.id, beeping: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Locate failed: $e')));
    } finally {
      _sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final disabled = widget.unit.busy;
    return Opacity(
      opacity: disabled ? .45 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _locate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedBuilder(
              animation: _ping,
              builder: (context, _) {
                final pinging = _ping.isAnimating;
                return Container(
                  padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: pinging ? p.tanSoft : p.card2,
                    borderRadius: BorderRadius.circular(HwRadius.pill),
                    border: Border.all(color: pinging ? p.copper : p.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CustomPaint(
                          painter: _PingPainter(_ping.value, p.copper),
                          child: Center(
                            child:
                                HwIcon(HwIcons.target, size: 15, color: v.link),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Locate',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: pinging ? v.link : p.ink2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PingPainter extends CustomPainter {
  final double t;
  final Color color;
  _PingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    // Two rings, the second trailing by ~0.3 of the cycle.
    for (final offset in const [0.0, .24]) {
      final k = ((t - offset) / .72).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final r = size.width / 2 * (.55 + 1.95 * k);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: .95 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_PingPainter old) => old.t != t;
}

class _SelectedChip extends StatelessWidget {
  final int selected;
  final int total;
  final VoidCallback onTap;
  const _SelectedChip(
      {required this.selected, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.card2,
          borderRadius: BorderRadius.circular(HwRadius.pill),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected > 0 ? p.good : Colors.transparent,
                border:
                    selected > 0 ? null : Border.all(color: p.ink3, width: 1.5),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_plural(selected, 'unit')} selected '),
                  TextSpan(
                    text: 'of $total',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      fontWeight: FontWeight.w600,
                      color: p.ink3,
                    ),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HwType.sm,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoUnits extends StatelessWidget {
  const _NoUnits();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('No units connected. ',
              style: TextStyle(fontSize: HwType.sm, color: p.ink2)),
          GestureDetector(
            onTap: () => context.go(RoutePaths.devices),
            child: Text(
              'Connect a unit',
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w600,
                color: v.link,
                decoration: TextDecoration.underline,
                decorationColor: v.link,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreUnitsButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreUnitsButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(p.line, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: p.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// Pick the org's Quick Start default protocol (also in More → Session
/// defaults).
Future<void> showDefaultProtocolSheet(BuildContext context) {
  return showHwSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (ctx, ref, _) {
        final p = RefPalette.of(ctx);
        final selected = ref.watch(defaultProtocolIdProvider);
        final list = ref.watch(protocolListProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Default protocol',
              style: TextStyle(
                fontSize: HwType.lg,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Quick Start runs this on every armed unit.',
              style: TextStyle(fontSize: HwType.cap, color: p.ink3),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: list.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    "Couldn't load protocols. Check your connection and try "
                    'again.',
                    style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                  ),
                ),
                data: (protocols) {
                  final usable = protocols.where((x) => x.active).toList();
                  if (usable.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No protocols available for this organization yet.',
                        style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final proto in usable)
                        HwRow(
                          leading:
                              HwIcon(HwIcons.flask, size: 18, color: p.ink3),
                          title: proto.templateName,
                          titleMaxLines: 2,
                          subtitle: '~${_mins(proto)} min',
                          trailing: proto.id == selected
                              ? const HwPill('Default', tone: HwPillTone.copper)
                              : null,
                          onTap: () {
                            ref
                                .read(defaultProtocolIdProvider.notifier)
                                .set(proto.id);
                            Navigator.pop(sheetContext);
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

// ===========================================================================
// 2 · Support Recovery
// ===========================================================================

class _RecoveryFocus {
  final RecoveryGoal goal;
  final String label;
  final String sub;
  final String icon;
  const _RecoveryFocus(this.goal, this.label, this.sub, this.icon);
}

const List<_RecoveryFocus> _kRecovery = [
  _RecoveryFocus(RecoveryGoal.discomfort, 'Discomfort', 'Where it feels tight',
      HwIcons.target),
  _RecoveryFocus(RecoveryGoal.rangeOfMotion, 'Joint Mobility',
      'More range in a joint', HwIcons.rotate),
  _RecoveryFocus(RecoveryGoal.performanceRecovery, 'Post-Workout',
      'Recover after training', HwIcons.bolt),
  _RecoveryFocus(
      RecoveryGoal.lymphatic, 'Lymphatic', 'Support fluid flow', HwIcons.drop),
];

/// One tap into the Assistant's recovery flow with the pathway already chosen.
void _openRecovery(BuildContext context, WidgetRef ref, RecoveryGoal goal) {
  ref.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
  ref.read(selectedClientProvider.notifier).state = null;
  context.go('${RoutePaths.assistant}?intent=recovery&goal=${goal.value}');
}

class HubRecovery extends ConsumerWidget {
  final HubSize size;
  const HubRecovery(this.size, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (size == HubSize.small) {
      return _SmallRow(
        label: 'Support Recovery',
        icon: HwIcons.wave,
        title: 'Pick a recovery focus',
        sub: 'Discomfort · mobility · post-workout · lymphatic',
        actions: [
          _PillAction('Choose',
              primary: true, onTap: () => _recoverySheet(context, ref)),
        ],
      );
    }

    return _Section(
      surface: _Surface.hero,
      title: 'Support Recovery',
      icon: HwIcons.wave,
      helper: 'Pick a focus to get pad placements',
      padding: size == HubSize.medium
          ? const EdgeInsets.all(12)
          : const EdgeInsets.all(14),
      body: size == HubSize.medium
          ? Row(
              children: [
                for (var i = 0; i < _kRecovery.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: HubCascade(
                      index: i,
                      tile: true,
                      startMs: 300,
                      stepMs: 80,
                      child: _RecoveryChip(
                        focus: _kRecovery[i],
                        onTap: () =>
                            _openRecovery(context, ref, _kRecovery[i].goal),
                      ),
                    ),
                  ),
                ],
              ],
            )
          : _Grid2(
              children: [
                for (final (i, f) in _kRecovery.indexed)
                  HubCascade(
                    index: i,
                    tile: true,
                    startMs: 300,
                    stepMs: 80,
                    child: _RecoveryTile(
                      focus: f,
                      onTap: () => _openRecovery(context, ref, f.goal),
                    ),
                  ),
              ],
            ),
    );
  }

  void _recoverySheet(BuildContext context, WidgetRef ref) {
    showHwSheet<void>(
      context: context,
      builder: (sheetContext) {
        final p = RefPalette.of(sheetContext);
        final v = _V6.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Support Recovery',
              style: TextStyle(
                fontSize: HwType.lg,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a focus to get pad placements',
              style: TextStyle(fontSize: HwType.cap, color: p.ink3),
            ),
            const SizedBox(height: 12),
            for (final f in _kRecovery)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HwPress(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openRecovery(context, ref, f.goal);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: p.line),
                    ),
                    child: Row(
                      children: [
                        _WarmTile(icon: f.icon, size: 30, v: v),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.label,
                                  style: TextStyle(
                                    fontSize: HwType.sm,
                                    fontWeight: FontWeight.w700,
                                    color: p.ink,
                                  )),
                              Text(f.sub,
                                  style: TextStyle(
                                      fontSize: HwType.cap, color: p.ink3)),
                            ],
                          ),
                        ),
                        HwIcon(HwIcons.chev, size: 16, color: p.ink3),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WarmTile extends StatelessWidget {
  final String icon;
  final double size;
  final _V6 v;
  const _WarmTile({required this.icon, required this.size, required this.v});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: v.warmTile,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Center(child: HwIcon(icon, size: size * .53, color: v.warmInk)),
    );
  }
}

/// Two equal columns whose rows share the tallest tile's height.
class _Grid2 extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const _Grid2({required this.children, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[i]),
            SizedBox(width: gap),
            Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _RecoveryTile extends StatelessWidget {
  final _RecoveryFocus focus;
  final VoidCallback onTap;
  const _RecoveryTile({required this.focus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = _V6.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WarmTile(icon: focus.icon, size: 30, v: v),
            const SizedBox(height: 8),
            Text(
              focus.label,
              style: const TextStyle(
                fontSize: HwType.base,
                fontWeight: FontWeight.w600,
                color: _V6.cream,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              focus.sub,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: _V6.cream.withValues(alpha: .65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryChip extends StatelessWidget {
  final _RecoveryFocus focus;
  final VoidCallback onTap;
  const _RecoveryChip({required this.focus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = _V6.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 9),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .1)),
        ),
        child: Column(
          children: [
            _WarmTile(icon: focus.icon, size: 30, v: v),
            const SizedBox(height: 5),
            Text(
              focus.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w600,
                color: _V6.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 3 · Athlete Readiness & Performance
// ===========================================================================

void _athleteGuest(BuildContext context, WidgetRef ref) {
  ref.read(sessionClientModeProvider.notifier).state = ClientMode.guest;
  ref.read(selectedClientProvider.notifier).state = null;
  context.go('${RoutePaths.assistant}?intent=performance');
}

Future<void> _athletePickPlayer(BuildContext context, WidgetRef ref) {
  return showHwSheet<void>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (ctx, ref2, _) {
        final p = RefPalette.of(ctx);
        final clients = ref2.watch(clientListProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select a player',
              style: TextStyle(
                fontSize: HwType.lg,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Their sport and position lead straight to pad placements.',
              style: TextStyle(fontSize: HwType.cap, color: p.ink3),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: clients.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    "Couldn't load your roster. Check your connection and "
                    'try again.',
                    style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No one on file yet. Start with Guest Mode, or add '
                        'people from the Users tab.',
                        style: TextStyle(fontSize: HwType.sm, color: p.ink2),
                      ),
                    );
                  }
                  // Players first — this card is about sport readiness.
                  final sorted = [...list]..sort((a, b) {
                      if (a.isPlayer != b.isPlayer) return a.isPlayer ? -1 : 1;
                      return a.displayName
                          .toLowerCase()
                          .compareTo(b.displayName.toLowerCase());
                    });
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in sorted)
                        HwRow(
                          leading: _AvatarInitials(c.displayName),
                          title: c.displayName,
                          titleMaxLines: 1,
                          subtitle: c.isPlayer ? 'Player' : 'Client',
                          trailing:
                              HwIcon(HwIcons.chev, size: 16, color: p.ink3),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            ref2
                                .read(sessionClientModeProvider.notifier)
                                .state = ClientMode.client;
                            ref2.read(selectedClientProvider.notifier).state =
                                c;
                            context.go(
                                '${RoutePaths.assistant}?intent=performance');
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _AvatarInitials extends StatelessWidget {
  final String name;
  const _AvatarInitials(this.name);

  @override
  Widget build(BuildContext context) {
    final v = _V6.of(context);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(gradient: v.warmTile, shape: BoxShape.circle),
      child: Center(
        child: Text(
          _initials(name),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: v.warmInk,
          ),
        ),
      ),
    );
  }
}

class HubAthlete extends ConsumerWidget {
  final HubSize size;
  const HubAthlete(this.size, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onFile = ref.watch(clientListProvider).valueOrNull?.length ?? 0;

    if (size == HubSize.small) {
      return _SmallRow(
        label: 'Athlete Readiness & Performance',
        icon: HwIcons.bolt,
        title: 'Readiness & performance',
        sub: '${_plural(onFile, 'player')} on file',
        actions: [
          _PillAction('Guest',
              primary: true, onTap: () => _athleteGuest(context, ref)),
          _PillAction('Player', onTap: () => _athletePickPlayer(context, ref)),
        ],
      );
    }

    final medium = size == HubSize.medium;
    return _Section(
      surface: _Surface.perf,
      title: 'Athlete Readiness & Performance',
      icon: HwIcons.bolt,
      helper: 'Sport & position → pad placements',
      padding: medium ? const EdgeInsets.all(12) : const EdgeInsets.all(14),
      body: medium
          ? Row(
              children: [
                Expanded(
                  child: _PerfInline(
                    icon: HwIcons.guest,
                    label: 'Guest Mode',
                    onTap: () => _athleteGuest(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PerfInline(
                    icon: HwIcons.users,
                    label: 'Select Player',
                    count: onFile,
                    onTap: () => _athletePickPlayer(context, ref),
                  ),
                ),
              ],
            )
          : _Grid2(
              gap: 10,
              children: [
                HubCascade(
                  index: 0,
                  tile: true,
                  startMs: 300,
                  stepMs: 80,
                  child: _PerfOption(
                    icon: HwIcons.guest,
                    label: 'Guest Mode',
                    sub: 'Start now, no profile',
                    onTap: () => _athleteGuest(context, ref),
                  ),
                ),
                HubCascade(
                  index: 1,
                  tile: true,
                  startMs: 300,
                  stepMs: 80,
                  child: _PerfOption(
                    icon: HwIcons.users,
                    label: 'Select Player',
                    sub: '$onFile on file',
                    onTap: () => _athletePickPlayer(context, ref),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PerfOption extends StatelessWidget {
  final String icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _PerfOption(
      {required this.icon,
      required this.label,
      required this.sub,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, .55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: HwIcon(icon, size: 17, color: _V6.copperText),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _V6.copperText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11.5,
                color: _V6.copperText.withValues(alpha: .75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerfInline extends StatelessWidget {
  final String icon;
  final String label;
  final int? count;
  final VoidCallback onTap;
  const _PerfInline(
      {required this.icon,
      required this.label,
      this.count,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, .32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color.fromRGBO(255, 255, 255, .45)),
        ),
        child: Row(
          children: [
            HwIcon(icon, size: 17, color: _V6.copperText),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _V6.copperText,
                ),
              ),
            ),
            if (count != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, .5),
                  borderRadius: BorderRadius.circular(HwRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: HwType.cap,
                    fontWeight: FontWeight.w700,
                    color: _V6.copperText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 3b · Game Prep (v5 `20-gameprep.js`)
// ===========================================================================

/// Pastel avatar tints, cycled by roster position.
const List<(Color, Color)> _kPrepTints = [
  (Color(0xFFF6E7A9), Color(0xFF6B5636)),
  (Color(0xFFF1D4C4), Color(0xFF7A5142)),
  (Color(0xFFCFE0EA), Color(0xFF35576B)),
  (Color(0xFFD8E1CE), Color(0xFF48583F)),
];

/// Copper for everyone still to prep, green once prepped — no alarm reds.
Color _prepTone(bool prepped, bool dark) => prepped
    ? (dark ? const Color(0xFF6FBF98) : const Color(0xFF3F8E6E))
    : (dark ? const Color(0xFFD8B79C) : const Color(0xFFA87B5C));

String _prepStatus(GamePrepRow r) {
  if (r.prepped) {
    return 'Prepped ✓ · ${DateFormat('h:mm a').format(r.today!.createdAt!)}';
  }
  final d = r.daysSince;
  if (d == null) return 'Ready for first session';
  if (d == 0) return 'Resume today';
  return '$d day${d == 1 ? '' : 's'} since last';
}

String _prepMomentum(int done, int total) {
  if (done >= total) return 'Squad prepped. Great work.';
  if (done == 0) return '$total to prep. Start with whoever is up next.';
  return '${total - done} to go · ${(done / total * 100).round()}% of the '
      'squad ready';
}

String _playerSub(Client c) => [
      if ((c.sport ?? '').trim().isNotEmpty) c.sport!.trim(),
      if (c.jerseyNumber != null) '#${c.jerseyNumber}',
    ].join(' · ');

/// Game Prep's Start: straight to the Session tab with the player selected.
void _prepStart(BuildContext context, WidgetRef ref, Client c) {
  ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
  ref.read(selectedClientProvider.notifier).state = c;
  context.go(RoutePaths.devices);
}

class HubGamePrep extends ConsumerWidget {
  final HubSize size;
  const HubGamePrep(this.size, {super.key});

  static const String _helper = 'Who still needs a session before game time';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final team = ref.watch(gamePrepTeamProvider);
    final data =
        ref.watch(gamePrepProvider(team)).valueOrNull ?? const GamePrepData();
    final gameDay = ref.watch(gameDayActiveProvider);

    if (size == HubSize.small) {
      return _SmallRow(
        label: 'Game Prep',
        icon: HwIcons.target,
        title: data.total == 0
            ? 'No players on the roster yet'
            : '${data.prepped.length} of ${data.total} prepped today',
        sub: data.total == 0
            ? 'Add your team in Users'
            : _prepMomentum(data.prepped.length, data.total),
        actions: [
          _PillAction(
            data.total == 0 ? 'Users' : 'Players',
            onTap: () => context.go(RoutePaths.users),
          ),
        ],
      );
    }

    if (data.total == 0) {
      return _Section(
        title: 'Game Prep',
        icon: HwIcons.target,
        helper: _helper,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No players on the roster yet. Add your team in Users to track '
              "who's prepped before game time.",
              style: TextStyle(fontSize: HwType.sm, height: 1.5, color: p.ink3),
            ),
            const SizedBox(height: 10),
            _PillAction('Open Users',
                onTap: () => context.go(RoutePaths.users)),
          ],
        ),
      );
    }

    final filter = ref.watch(gamePrepFilterProvider);
    final list = switch (filter) {
      GamePrepFilter.done => data.prepped,
      GamePrepFilter.all => [...data.left, ...data.prepped],
      GamePrepFilter.prep => data.left,
    };
    final done = data.prepped.length;
    final pct = done / data.total;
    final todo = _prepTone(false, v.dark);

    final section = _Section(
      title: 'Game Prep',
      icon: HwIcons.target,
      helper: _helper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    HwCountUp(
                      done,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1,
                        color: todo,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'of ${data.total} prepped today',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: HwType.sm, color: p.ink3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _GameDayButton(
                on: gameDay,
                onTap: () {
                  final n = ref.read(gameDayActiveProvider.notifier);
                  gameDay ? n.end() : n.activate();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PrepBar(fraction: pct),
          const SizedBox(height: 8),
          Text(
            _prepMomentum(done, data.total),
            style: TextStyle(
              fontSize: HwType.cap,
              fontWeight: FontWeight.w700,
              color: p.ink2,
            ),
          ),
          const SizedBox(height: 12),
          if (data.teams.length > 1) ...[
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final t in [null, ...data.teams])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _TeamChip(
                        label: t ?? 'All teams',
                        on: team == t,
                        onTap: () =>
                            ref.read(gamePrepTeamProvider.notifier).state = t,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _PrepSegment(
            value: filter,
            counts: {
              GamePrepFilter.prep: data.left.length,
              GamePrepFilter.done: data.prepped.length,
              GamePrepFilter.all: data.total,
            },
            onChanged: (f) =>
                ref.read(gamePrepFilterProvider.notifier).state = f,
          ),
          if (list.isNotEmpty && HwTablet.of(context)) ...[
            // Tablet: the rail stops hiding what would fit (97-tablet §5).
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 10,
              children: [
                for (var i = 0; i < list.length; i++)
                  HubCascade(
                    index: i,
                    startMs: 260,
                    stepMs: 60,
                    child: _PrepCard(
                      row: list[i],
                      upNext: i == 0 &&
                          !list[i].prepped &&
                          filter != GamePrepFilter.done,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              filter == GamePrepFilter.done
                  ? 'Tap a player to see their focus card.'
                  : 'Longest since a session first. Tap a player for their '
                      'focus card, or Start to go straight to Session Plan.',
              style:
                  TextStyle(fontSize: HwType.cap, height: 1.4, color: p.ink3),
            ),
          ] else if (list.isNotEmpty) ...[
            // The row bleeds to the card edges, like the prototype's.
            Transform.translate(
              offset: const Offset(-14, 0),
              child: SizedBox(
                height: 222,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: MediaQuery.sizeOf(context).width,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => HubCascade(
                      index: i,
                      startMs: 260,
                      stepMs: 60,
                      child: _PrepCard(
                        row: list[i],
                        upNext: i == 0 &&
                            !list[i].prepped &&
                            filter != GamePrepFilter.done,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              filter == GamePrepFilter.done
                  ? 'Tap a player to see their focus card.'
                  : 'Longest since a session first. Tap a player for their '
                      'focus card, or Start to go straight to Session Plan.',
              style:
                  TextStyle(fontSize: HwType.cap, height: 1.4, color: p.ink3),
            ),
          ] else if (filter == GamePrepFilter.prep)
            _SquadPrepped(team: team)
          else
            Text(
              'No one prepped yet today. Start with whoever is up next.',
              style: TextStyle(fontSize: HwType.sm, height: 1.5, color: p.ink3),
            ),
        ],
      ),
    );

    if (!gameDay) return section;
    // Game day: a copper ring marks the widget that now leads the Hub.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(198, 158, 131, .55), spreadRadius: 2),
        ],
      ),
      child: section,
    );
  }
}

class _GameDayButton extends ConsumerStatefulWidget {
  final bool on;
  final VoidCallback onTap;
  const _GameDayButton({required this.on, required this.onTap});

  @override
  ConsumerState<_GameDayButton> createState() => _GameDayButtonState();
}

class _GameDayButtonState extends ConsumerState<_GameDayButton>
    with SingleTickerProviderStateMixin {
  // The white dot beats while game day is on (`v5gBeat`, 1.6s).
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final motion = hubMotionOn(context, ref);
    if (widget.on && motion && !_beat.isAnimating) _beat.repeat();
    if ((!widget.on || !motion) && _beat.isAnimating) _beat.stop();

    return Semantics(
      button: true,
      toggled: widget.on,
      child: HwPress(
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: widget.on ? _V6.sun : null,
              color: widget.on ? null : p.card,
              borderRadius: BorderRadius.circular(HwRadius.pill),
              border: widget.on ? null : Border.all(color: p.line, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _beat,
                  builder: (context, _) {
                    final s = math.sin(_beat.value * math.pi);
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.on
                            ? Colors.white
                            : p.ink3.withValues(alpha: .5),
                        boxShadow: widget.on && _beat.isAnimating
                            ? [
                                BoxShadow(
                                  color: Colors.white
                                      .withValues(alpha: .7 * (1 - s)),
                                  spreadRadius: 5 * s,
                                ),
                              ]
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 7),
                Text(
                  widget.on ? 'Game day on' : 'Start game day',
                  style: TextStyle(
                    fontSize: HwType.cap,
                    fontWeight: FontWeight.w700,
                    color: widget.on ? _V6.copperText : p.ink2,
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

class _PrepBar extends StatelessWidget {
  final double fraction;
  const _PrepBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final full = fraction >= 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(HwRadius.pill),
      child: Container(
        height: 7,
        color: dark ? const Color(0xFF2A2F36) : const Color(0xFFF0E5D6),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: const Cubic(.22, .61, .36, 1),
          builder: (_, v, __) => FractionallySizedBox(
            widthFactor: v == 0 ? 0.0001 : v,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(HwRadius.pill),
                gradient: LinearGradient(
                  colors: full
                      ? const [Color(0xFF8FCBAE), Color(0xFF3F8E6E)]
                      : const [
                          Color(0xFFDDCABF),
                          Color(0xFFC69E83),
                          Color(0xFFA87B5C),
                        ],
                  stops: full ? null : const [0, .6, 1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TeamChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onBg = dark ? const Color(0xFFDDCABF) : const Color(0xFF1F2B33);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? onBg : Colors.transparent,
          borderRadius: BorderRadius.circular(HwRadius.pill),
          border: Border.all(color: on ? onBg : p.line, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: HwType.cap,
            fontWeight: FontWeight.w700,
            color: on ? (dark ? const Color(0xFF1A1A1A) : _V6.cream) : p.ink2,
          ),
        ),
      ),
    );
  }
}

/// To prep · Prepped · All (v5.1 pill segment: the selected tab is copper).
class _PrepSegment extends StatelessWidget {
  final GamePrepFilter value;
  final Map<GamePrepFilter, int> counts;
  final ValueChanged<GamePrepFilter> onChanged;

  const _PrepSegment({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  static const _labels = {
    GamePrepFilter.prep: 'To prep',
    GamePrepFilter.done: 'Prepped',
    GamePrepFilter.all: 'All',
  };

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(HwRadius.pill),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          for (final f in GamePrepFilter.values) ...[
            if (f.index > 0) const SizedBox(width: 3),
            Expanded(
              child: Semantics(
                selected: f == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(f),
                  child: AnimatedContainer(
                    duration: HwMotion.t2,
                    constraints: const BoxConstraints(minHeight: 38),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: f == value ? _V6.sun : null,
                      borderRadius: BorderRadius.circular(HwRadius.pill),
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${_labels[f]}  '),
                        TextSpan(
                          text: '${counts[f]}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: f == value
                                ? _V6.copperText.withValues(alpha: .7)
                                : p.ink2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w800,
                        color: f == value ? _V6.copperText : p.ink3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrepCard extends ConsumerWidget {
  final GamePrepRow row;
  final bool upNext;
  const _PrepCard({required this.row, required this.upNext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (tintBg, tintInk) = _kPrepTints[row.index % _kPrepTints.length];
    final c = row.client;
    final sev = _prepTone(row.prepped, dark);
    final sub = _playerSub(c);
    final radius = BorderRadius.circular(22);

    final Color bg;
    final Color border;
    if (row.prepped) {
      bg = const Color.fromRGBO(63, 142, 110, .06);
      border = const Color.fromRGBO(63, 142, 110, .35);
    } else if (upNext) {
      bg = dark
          ? const Color.fromRGBO(192, 157, 132, .1)
          : const Color(0xFFFBF7F1);
      border = const Color(0xFFC69E83);
    } else {
      bg = dark
          ? const Color.fromRGBO(192, 157, 132, .1)
          : const Color(0xFFFBF7F1);
      border = dark
          ? const Color.fromRGBO(192, 157, 132, .3)
          : const Color(0xFFEADFD2);
    }

    Widget card = HwPress(
      onTap: () => _showAthleteFocus(context, ref, row),
      child: Container(
        width: 156,
        // A fixed height, so Start sits on the card's floor both in the
        // phone's sideways rail and in the tablet's wrapping rows.
        height: 190,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: border, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(color: tintBg, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      _initials(c.displayName),
                      style: TextStyle(
                        fontSize: HwType.cap,
                        fontWeight: FontWeight.w800,
                        color: tintInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName.split(RegExp(r'\s+')).first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: HwType.sm,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.ink3),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: sev, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _prepStatus(row).toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .44,
                      height: 1.2,
                      color: dark ? const Color(0xFFBFC9D2) : p.ink2,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            _PrepGo(
              again: row.prepped,
              onTap: () => _prepStart(context, ref, c),
            ),
          ],
        ),
      ),
    );

    if (upNext) {
      card = Stack(
        clipBehavior: Clip.none,
        children: [
          HubPulse(radius: radius, child: card),
          Positioned(
            top: -5,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFDEB393), Color(0xFFB27D5C)]),
                borderRadius: BorderRadius.circular(HwRadius.pill),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(169, 130, 95, .4),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'UP NEXT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .88,
                  color: _V6.copperText,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // Same footprint as the pulsing card so the row lines up.
      card = Padding(padding: const EdgeInsets.all(6), child: card);
    }
    return card;
  }
}

class _PrepGo extends StatelessWidget {
  final bool again;
  final VoidCallback onTap;
  const _PrepGo({required this.again, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3F8E6E);
    final fg = again ? green : _V6.copperText;
    return HwPress(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: again
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                ),
          borderRadius: BorderRadius.circular(12),
          border: again
              ? Border.all(
                  color: const Color.fromRGBO(63, 142, 110, .35), width: 1.5)
              : null,
          boxShadow: again
              ? null
              : const [
                  BoxShadow(
                    color: Color.fromRGBO(192, 157, 132, .65),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                again ? 'AGAIN' : 'START',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .66,
                  color: fg,
                ),
              ),
            ),
            HwIcon(HwIcons.arrow, size: 14, color: fg),
          ],
        ),
      ),
    );
  }
}

class _SquadPrepped extends StatelessWidget {
  final String? team;
  const _SquadPrepped({required this.team});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(63, 142, 110, .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: Color(0xFF3F8E6E), shape: BoxShape.circle),
            child: const Center(
              child: HwIcon(HwIcons.check, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Squad prepped',
                    style: TextStyle(
                      fontSize: HwType.sm,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    )),
                Text(
                  'Everyone${team != null ? ' on this team' : ''} has a '
                  'completed session today.',
                  style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The athlete focus card: who they are, where they stand today, their last
/// session, and the way in. (The prototype's readiness dial and trend are left
/// out — the app has no readiness measurement to show honestly.)
Future<void> _showAthleteFocus(
    BuildContext context, WidgetRef ref, GamePrepRow row) {
  final c = row.client;
  final sub = _playerSub(c);
  final last = row.last;
  final lastLabel = last == null || last.protocols.isEmpty
      ? (last == null ? 'No sessions yet' : 'Session')
      : [last.protocols.first.protocol, last.protocols.first.bodyPart]
          .where((e) => e != null && e.isNotEmpty)
          .join(' · ');
  String lastWhen() {
    final at = last!.createdAt!;
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day) ==
            DateTime(now.year, now.month, now.day)
        ? 'Today'
        : DateFormat('EEE, MMM d').format(at);
    return '$day · ${DateFormat('h:mm a').format(at)}';
  }

  return showHwSheet<void>(
    context: context,
    builder: (sheetContext) {
      final p = RefPalette.of(sheetContext);
      final dark = Theme.of(sheetContext).brightness == Brightness.dark;
      final sev = _prepTone(row.prepped, false);
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -24,
                    right: -16,
                    child: HubFloat(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromRGBO(255, 255, 255, .15),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ATHLETE FOCUS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color:
                                          _V6.copperText.withValues(alpha: .8),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.displayName,
                                    style: const TextStyle(
                                      fontFamily: 'Georgia',
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (sub.isNotEmpty)
                                    Text(
                                      sub.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: HwType.cap,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                        color: _V6.copperText
                                            .withValues(alpha: .85),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Close',
                              child: HwPress(
                                onTap: () => Navigator.pop(sheetContext),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.fromRGBO(255, 255, 255, .2),
                                  ),
                                  child: const Center(
                                    child: HwIcon(HwIcons.x,
                                        size: 15, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 255, 255, .92),
                            borderRadius: BorderRadius.circular(HwRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: sev, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _prepStatus(row).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .44,
                                  color: sev,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.line2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LAST SESSION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Color(0xFFC09D84),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastLabel.isEmpty ? 'Session' : lastLabel,
                    style: TextStyle(
                      fontSize: HwType.sm,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    last == null
                        ? 'Start their first session below.'
                        : lastWhen(),
                    style: TextStyle(fontSize: HwType.cap, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            HwPress(
              onTap: () {
                Navigator.pop(sheetContext);
                _prepStart(context, ref, c);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFDEB393), Color(0xFFB27D5C)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(169, 130, 95, .8),
                      blurRadius: 20,
                      spreadRadius: -8,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      row.prepped ? 'START ANOTHER SESSION' : 'START SESSION',
                      style: const TextStyle(
                        fontSize: HwType.sm,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: _V6.copperText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const HwIcon(HwIcons.arrow,
                        size: 15, color: _V6.copperText),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            HwPress(
              onTap: () {
                Navigator.pop(sheetContext);
                context.pushNamed(
                  RouteNames.clientDetail,
                  extra: {'clientId': c.id, 'title': c.displayName},
                );
              },
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HwIcon(HwIcons.users,
                        size: 15,
                        color: dark
                            ? const Color(0xFFDDCABF)
                            : const Color(0xFF8A5F42)),
                    const SizedBox(width: 6),
                    Text(
                      'Open player profile',
                      style: TextStyle(
                        fontSize: HwType.sm,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? const Color(0xFFDDCABF)
                            : const Color(0xFF8A5F42),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ===========================================================================
// 4 · Usage Statistics
// ===========================================================================

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

Iterable<PulseCheck> _inWindow(List<PulseCheck> all, UsageWindow w) {
  if (w == UsageWindow.all) return all;
  final from = _day(DateTime.now())
      .subtract(Duration(days: w == UsageWindow.d7 ? 6 : 29));
  return all.where((c) => !c.at.isBefore(from));
}

class _Bucket {
  final String label;
  final int? pct;
  final int total;

  /// No check-ins in this period: [pct] is the last score carried forward,
  /// so the line runs on without claiming a new reading here.
  final bool carried;
  const _Bucket(this.label, this.pct, this.total, {this.carried = false});
}

/// Periods with no check-ins hold the last known score, so the line runs
/// across the whole window instead of stopping at gaps. The score before the
/// window opens seeds it: the latest check-in day before [windowStart].
List<_Bucket> _carryForward(
    List<_Bucket> raw, List<PulseCheck> all, DateTime? windowStart) {
  int? last;
  if (windowStart != null) {
    final before = all.where((c) => _day(c.at).isBefore(windowStart)).toList();
    if (before.isNotEmpty) {
      final lastDay =
          before.map((c) => _day(c.at)).reduce((a, b) => a.isAfter(b) ? a : b);
      last = scoreOf(before.where((c) => _day(c.at) == lastDay)).pct;
    }
  }
  return [
    for (final b in raw)
      if (b.pct != null)
        () {
          last = b.pct;
          return b;
        }()
      else if (last != null)
        _Bucket(b.label, last, 0, carried: true)
      else
        b,
  ];
}

/// v5 `series(win)`: 7 daily points, 6 five-day points, or one per month.
List<_Bucket> _series(List<PulseCheck> all, UsageWindow w) {
  final today = _day(DateTime.now());
  _Bucket bucket(String label, bool Function(DateTime) inside) {
    final s = scoreOf(all.where((c) => inside(_day(c.at))));
    return _Bucket(label, s.pct, s.total);
  }

  switch (w) {
    case UsageWindow.d7:
      return _carryForward([
        for (var o = 6; o >= 0; o--)
          () {
            final d = today.subtract(Duration(days: o));
            return bucket(DateFormat('EEE').format(d), (x) => x == d);
          }(),
      ], all, today.subtract(const Duration(days: 6)));
    case UsageWindow.d30:
      return _carryForward([
        for (var j = 0; j < 6; j++)
          () {
            final from = today.subtract(Duration(days: 29 - 5 * j));
            final to = today.subtract(Duration(days: 25 - 5 * j));
            return bucket(DateFormat('MMM d').format(to),
                (x) => !x.isBefore(from) && !x.isAfter(to));
          }(),
      ], all, today.subtract(const Duration(days: 29)));
    case UsageWindow.all:
      final now = DateTime(today.year, today.month);
      var cur =
          all.isEmpty ? now : DateTime(all.first.at.year, all.first.at.month);
      final multiYear = cur.year != now.year;
      final out = <_Bucket>[];
      for (var guard = 0; guard < 240 && !cur.isAfter(now); guard++) {
        final m = cur;
        final label = DateFormat('MMM').format(m) +
            (multiYear ? " '${(m.year % 100).toString().padLeft(2, '0')}" : '');
        out.add(bucket(label, (x) => x.year == m.year && x.month == m.month));
        cur = DateTime(cur.year, cur.month + 1);
      }
      return _carryForward(out, all, null);
  }
}

/// Whole hours from 10 up, otherwise one decimal ("3.5", "2" not "2.0").
String _hoursLabel(double h) {
  if (h >= 10) return '${h.round()}';
  final tenths = (h * 10).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : (tenths / 10).toStringAsFixed(1);
}

class HubUsage extends ConsumerWidget {
  final HubSize size;
  const HubUsage(this.size, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(hubStatsProvider).valueOrNull ?? const HubStats();
    final win = ref.watch(usageWindowProvider);
    final pending = ref
        .watch(pendingOutcomesProvider)
        .where((e) => e.answers == null)
        .length;
    final sc = scoreOf(_inWindow(stats.checks, win));
    void openHistory() => context.go(RoutePaths.history);

    if (size == HubSize.small) {
      return _SmallRow(
        label: 'Usage Statistics',
        icon: HwIcons.chart,
        title:
            sc.pct != null ? '${sc.pct}% improvement score' : 'No checks yet',
        sub: '${win.label} · ${_hoursLabel(stats.hoursUsed)} h used',
        actions: [_PillAction('Details', onTap: openHistory)],
      );
    }

    return _Section(
      title: 'Usage Statistics',
      icon: HwIcons.chart,
      helper: 'How you use Hydrawav3 · measured, not estimated',
      linkLabel: 'History',
      onLink: openHistory,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoreBlock(pct: sc.pct, total: sc.total, yes: sc.yes, window: win),
          _WindowChips(all: stats.checks, active: win),
          if (size == HubSize.large) ...[
            const SizedBox(height: 14),
            _GraphKey(window: win, hasData: sc.total > 0, above: true),
            const SizedBox(height: 4),
            _ScoreGraph(series: _series(stats.checks, win)),
            if (sc.total > 0) _GraphKey(window: win, hasData: true),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: HubCascade(
                      index: 0,
                      child: _StatTile(
                        big: Text.rich(TextSpan(children: [
                          TextSpan(text: _hoursLabel(stats.hoursUsed)),
                          const TextSpan(
                            text: ' h',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ])),
                        label: 'Hours used',
                        sub: _plural(stats.sessionsTotal, 'completed session'),
                        onTap: openHistory,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HubCascade(
                      index: 1,
                      child: _StatTile(
                        small: true,
                        // Protocol names run long ("Deep-Tension Recovery ·
                        // Lower Back Plus"): up to three lines, a step smaller
                        // past ~24 characters, then an ellipsis. Both tiles
                        // keep one shared height (IntrinsicHeight above).
                        big: Text(
                          stats.topProtocol?.name ?? '—',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (stats.topProtocol?.name.length ?? 0) > 24
                                ? 13
                                : 14,
                          ),
                        ),
                        label: 'Most used protocol',
                        sub: stats.topProtocol == null
                            ? 'no sessions yet'
                            : _plural(stats.topProtocol!.count, 'session'),
                        onTap: () => context.go(RoutePaths.protocols),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (pending > 0) _PendingChecks(count: pending, onTap: openHistory),
        ],
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  final int? pct;
  final int total;
  final int yes;
  final UsageWindow window;
  const _ScoreBlock({
    required this.pct,
    required this.total,
    required this.yes,
    required this.window,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final numStyle = TextStyle(
      fontSize: 38,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1.14,
      color: p.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMPROVEMENT SCORE',
          style: TextStyle(
            fontSize: HwType.cap,
            fontWeight: FontWeight.w700,
            letterSpacing: .72,
            color: p.ink3,
          ),
        ),
        const SizedBox(height: 2),
        if (pct == null)
          Text('—', style: numStyle)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              HwCountUp(pct!, style: numStyle),
              Text(
                '%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
            ],
          ),
        const SizedBox(height: 1),
        const SizedBox(height: 2),
        // Say what the number is: the share of post-session check-ins where
        // the answer was that the session helped.
        Text.rich(
          total == 0
              ? TextSpan(
                  text: 'No post-session check-ins in the ${window.caption} '
                      'yet. The score fills in as clients answer after '
                      'each session.',
                )
              : TextSpan(children: [
                  TextSpan(
                    text: '$yes of $total',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: p.ink2,
                    ),
                  ),
                  TextSpan(
                    text: ' post-session check-in${total == 1 ? '' : 's'} '
                        'said the session helped · ${window.caption}',
                  ),
                ]),
          style: TextStyle(fontSize: HwType.cap, height: 1.4, color: p.ink3),
        ),
      ],
    );
  }
}

/// Words for the graph: a title above it ("Score by day"), and below it what
/// a point means and why some days have none.
class _GraphKey extends StatelessWidget {
  final UsageWindow window;
  final bool hasData;
  final bool above;
  const _GraphKey({
    required this.window,
    required this.hasData,
    this.above = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    if (above) {
      return Text(
        'Score by ${window.bucket}',
        style: TextStyle(
          fontSize: HwType.cap,
          fontWeight: FontWeight.w700,
          color: p.ink2,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.card,
                border: Border.all(color: p.copper, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Each dot is the share of that ${window.bucket}\'s check-ins '
              'that said the session helped. Where there\'s no dot there were '
              'no check-ins, so the line holds the last score.',
              style: TextStyle(fontSize: 11, height: 1.4, color: p.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowChips extends ConsumerWidget {
  final List<PulseCheck> all;
  final UsageWindow active;
  const _WindowChips({required this.all, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final w in UsageWindow.values)
            () {
              final s = scoreOf(_inWindow(all, w));
              final on = w == active;
              return HwPress(
                onTap: () => ref.read(usageWindowProvider.notifier).set(w),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: on
                          ? (v.dark
                              ? const Color.fromRGBO(198, 158, 131, .16)
                              : p.tanSoft)
                          : p.card,
                      borderRadius: BorderRadius.circular(HwRadius.pill),
                      border: Border.all(color: on ? p.copper : p.line),
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${w.chip}  '),
                        TextSpan(
                          text: s.pct != null ? '${s.pct}%' : '—',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: on
                                ? (v.dark ? _V6.tan : const Color(0xFF6E4A33))
                                : p.ink2,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ]),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: on ? v.link : p.ink3,
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// The Improvement Score line graph (v5 `graphSVG`): 0/50/100 grid, smooth
/// line with a copper wash, a dot per bucket, and the latest point haloed and
/// labelled. It draws in once when it appears.
class _ScoreGraph extends ConsumerStatefulWidget {
  final List<_Bucket> series;
  const _ScoreGraph({required this.series});

  @override
  ConsumerState<_ScoreGraph> createState() => _ScoreGraphState();
}

/// The graph's entrance, on the prototype's timeline (15-hubmotion): the line
/// draws from 350ms over 1.3s, the wash fades in from 700ms, each point pops
/// 110ms after the last from 500ms, the latest point and its label land at
/// 1.5s — then the halo keeps pulsing every 2.2s.
class _ScoreGraphState extends ConsumerState<_ScoreGraph>
    with TickerProviderStateMixin {
  static const int _total = 2000;
  late final AnimationController _draw;
  late final AnimationController _halo;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _total));
    _halo = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
  }

  String _key = '';

  @override
  void dispose() {
    _draw.dispose();
    _halo.dispose();
    super.dispose();
  }

  void _play(bool motion) {
    final key = widget.series.map((b) => '${b.label}${b.pct}').join('|');
    if (key == _key) return;
    _key = key;
    _halo.stop();
    if (!motion) {
      _draw.value = 1;
      _halo.value = 0;
      return;
    }
    _draw.forward(from: 0).whenComplete(() {
      if (mounted) _halo.repeat();
    });
  }

  double _iv(int start, int len, [Curve curve = Curves.linear]) {
    final t = ((_draw.value * _total - start) / len).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    if (!series.any((b) => b.pct != null)) {
      return CustomPaint(
        painter: _DashedBorderPainter(p.line, 12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HwIcon(HwIcons.chart, size: 16, color: p.copper),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Scores appear after post-session checks',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: HwType.sm, color: p.ink3),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _play(hubMotionOn(context, ref));
    const pop = Cubic(.34, 1.56, .64, 1);
    const smooth = Cubic(.22, .61, .36, 1);
    final points = series.where((b) => b.pct != null).length;

    // The prototype's graph bleeds 4px past the card padding on each side.
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth + 8;
        final h = w * 128 / 320;
        return SizedBox(
          height: h,
          child: OverflowBox(
            maxWidth: w,
            minWidth: w,
            child: AnimatedBuilder(
              animation: Listenable.merge([_draw, _halo]),
              builder: (_, __) => CustomPaint(
                size: Size(w, h),
                painter: _GraphPainter(
                  series: series,
                  line: _iv(350, 1300, smooth),
                  wash: _iv(700, 1000),
                  dots: [
                    for (var i = 0; i < points; i++)
                      _iv(500 + i * 110, 450, pop),
                  ],
                  last: _iv(1500, 500, pop),
                  halo: _halo.isAnimating ? _halo.value : -1,
                  grid: p.line,
                  ink3: p.ink3,
                  card: p.card,
                  label: v.link,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<_Bucket> series;

  /// 0–1 progress of each entrance moment (1 = settled).
  final double line;
  final double wash;
  final List<double> dots;
  final double last;

  /// 0–1 phase of the halo pulse around the latest point; -1 = at rest.
  final double halo;

  final Color grid;
  final Color ink3;
  final Color card;
  final Color label;

  _GraphPainter({
    required this.series,
    required this.line,
    required this.wash,
    required this.dots,
    required this.last,
    required this.halo,
    required this.grid,
    required this.ink3,
    required this.card,
    required this.label,
  });

  static const double _w = 320, _h = 128, _l = 28, _r = 12, _t = 18, _b = 22;
  static const Color _copper = Color(0xFFC69E83);

  void _text(Canvas c, String s, Offset at, TextStyle style, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right || TextAlign.end => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    // `at.dy` is the SVG baseline; TextPainter paints from the top.
    tp.paint(
        c,
        Offset(
            dx,
            at.dy -
                tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w);
    const w = _w - _l - _r, h = _h - _t - _b;
    final n = series.length;
    double xAt(int i) => _l + (n == 1 ? w / 2 : i * w / (n - 1));
    double yAt(int pct) => _t + (1 - pct / 100) * h;

    // Same face as the rest of the app (the canvas has no inherited style).
    final axis = TextStyle(
        fontFamily: 'Roboto',
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: ink3);

    // Grid + y labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in const [0, 50, 100]) {
      final y = yAt(v);
      for (var x = _l; x < _w - _r; x += 7) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 3, _w - _r), y), gridPaint);
      }
      _text(canvas, '$v%', Offset(_l - 6, y + 3), axis, TextAlign.right);
    }

    // X labels: every bucket up to 7, otherwise ~6 evenly plus the last.
    final every = n <= 7 ? 1 : (n / 6).ceil();
    for (var i = 0; i < n; i++) {
      final show = i == n - 1 ||
          (i % every == 0 && (every == 1 || n - 1 - i >= (every / 2).ceil()));
      if (show) {
        _text(canvas, series[i].label, Offset(xAt(i), _h - 6), axis,
            TextAlign.center);
      }
    }

    final pts = <Offset>[];
    final vals = <int>[];
    final real = <bool>[];
    for (var i = 0; i < n; i++) {
      final pct = series[i].pct;
      if (pct == null) continue;
      pts.add(Offset(xAt(i), yAt(pct)));
      vals.add(pct);
      real.add(!series[i].carried);
    }
    if (pts.isEmpty) {
      canvas.restore();
      return;
    }
    const base = _t + h;

    if (pts.length > 1) {
      double cl(double v) => v.clamp(_t, base);
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 0; i < pts.length - 1; i++) {
        final p0 = i > 0 ? pts[i - 1] : pts[i];
        final p1 = pts[i], p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
        // Keep each segment's bend between its own two values, so a flat
        // stretch never dips or bulges past a reading it doesn't have.
        final lo = math.min(p1.dy, p2.dy), hi = math.max(p1.dy, p2.dy);
        double seg(double v) => cl(v).clamp(lo, hi);
        path.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          seg(p1.dy + (p2.dy - p0.dy) / 6),
          p2.dx - (p3.dx - p1.dx) / 6,
          seg(p2.dy - (p3.dy - p1.dy) / 6),
          p2.dx,
          p2.dy,
        );
      }

      // Wash under the line fades in behind it.
      final area = Path.from(path)
        ..lineTo(pts.last.dx, base)
        ..lineTo(pts.first.dx, base)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, _t),
            const Offset(0, base),
            [
              _copper.withValues(alpha: .34 * wash),
              _copper.withValues(alpha: 0),
            ],
          ),
      );

      if (line > 0) {
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _copper;
        for (final m in path.computeMetrics()) {
          canvas.drawPath(m.extractPath(0, m.length * line), stroke);
        }
      }
    }

    // Every point but the latest: hollow copper rings, popping in turn.
    for (var i = 0; i < pts.length - 1; i++) {
      if (!real[i]) continue; // carried forward: no new reading here
      final s = i < dots.length ? dots[i] : 1.0;
      if (s <= 0) continue;
      canvas.drawCircle(pts[i], 3 * s, Paint()..color = card);
      canvas.drawCircle(
        pts[i],
        3 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _copper,
      );
    }

    if (last > 0) {
      final p = pts.last;
      // Resting halo, plus the pulse ring expanding out of it.
      canvas.drawCircle(
          p, 9 * last, Paint()..color = _copper.withValues(alpha: .22));
      if (halo >= 0) {
        canvas.drawCircle(
          p,
          9 * (1 + 1.6 * halo),
          Paint()..color = _copper.withValues(alpha: .45 * (1 - halo)),
        );
      }
      canvas.drawCircle(
          p, 4.8 * last, Paint()..color = const Color(0xFFA87B5C));
      canvas.drawCircle(
        p,
        4.8 * last,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = card,
      );
      final lx = p.dx.clamp(_l + 14, _w - _r - 14);
      canvas.save();
      final anchor = Offset(lx, math.max(11, p.dy - 12));
      canvas.translate(anchor.dx, anchor.dy - 4);
      canvas.scale(last.clamp(0.0, 1.2));
      canvas.translate(-anchor.dx, -(anchor.dy - 4));
      _text(
        canvas,
        '${vals.last}%',
        anchor,
        TextStyle(
            fontFamily: 'Roboto',
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: label),
        TextAlign.center,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}

class _StatTile extends StatelessWidget {
  final Widget big;
  final bool small;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _StatTile({
    required this.big,
    this.small = false,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: p.card2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: small ? 14 : 24,
                fontWeight: small ? FontWeight.w700 : FontWeight.w800,
                letterSpacing: small ? 0 : -.48,
                height: small ? 1.25 : 1.05,
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: big,
            ),
            const Spacer(),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 11, height: 1.25, color: p.ink2)),
            const SizedBox(height: 1),
            Text(sub, style: TextStyle(fontSize: 10.5, color: p.ink3)),
          ],
        ),
      ),
    );
  }
}

class _PendingChecks extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _PendingChecks({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final fg = v.dark ? _V6.tan : const Color(0xFF6E4A33);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: HwPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: p.tanSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              HwIcon(HwIcons.chat, size: 15, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_plural(count, 'session')} need a quick check',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              HwIcon(HwIcons.chev, size: 15, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 5 · Learn About Protocols
// ===========================================================================

/// Protocol stacks (Protocol Plus) are what the carousel teaches; with none on
/// the account it falls back to the plain protocol library. The practitioner's
/// default protocol leads, marked ★ (the prototype's flagship stack).
({List<Protocol> items, String? starred}) _learnItems(
    List<Protocol> all, String? defaultId) {
  final active = all.where((p) => p.active).toList();
  final stacks = active.where((p) => p.isProtocolPlus).toList();
  final items = stacks.isNotEmpty ? stacks : active;
  final def = defaultId == null
      ? null
      : active.where((p) => p.id == defaultId).firstOrNull;
  if (def == null) return (items: items, starred: null);
  return (
    items: [def, ...items.where((p) => p.id != def.id)],
    starred: def.id,
  );
}

class HubLearn extends ConsumerStatefulWidget {
  final HubSize size;
  const HubLearn(this.size, {super.key});

  @override
  ConsumerState<HubLearn> createState() => _HubLearnState();
}

class _HubLearnState extends ConsumerState<HubLearn> {
  int _index = 0;

  /// +1 when moving forward, -1 back — picks the slide-in direction.
  int _dir = 1;

  /// Show more / Show less applies to every slide, as in the prototype.
  bool _open = false;

  void _go(int to, int n) {
    final next = to.clamp(0, n - 1);
    if (next == _index) return;
    setState(() {
      _dir = next > _index ? 1 : -1;
      _index = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(protocolListProvider).valueOrNull ?? const [];
    final learn = _learnItems(all, ref.watch(defaultProtocolIdProvider));
    final items = learn.items;
    final byId = {for (final p in all) p.id: p};
    final n = items.length;
    void openLibrary() => context.go(RoutePaths.protocols);
    final isStacks = items.any((p) => p.isProtocolPlus);
    final noun = isStacks ? 'stack' : 'protocol';

    if (widget.size == HubSize.small) {
      return _SmallRow(
        label: 'Learn About Protocols',
        icon: HwIcons.book,
        title: _plural(n, isStacks ? 'protocol stack' : 'protocol'),
        sub: n > 0 ? items.first.templateName : 'Browse the library',
        actions: [_PillAction('Browse', onTap: openLibrary)],
      );
    }

    final medium = widget.size == HubSize.medium;
    final helper = medium
        ? 'Highlighted $noun · $n in the library'
        : '${_plural(n, noun)} · swipe to browse';

    Widget body;
    if (n == 0) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'No protocol stacks yet.',
          style: TextStyle(
              fontSize: HwType.sm, color: RefPalette.of(context).ink2),
        ),
      );
    } else if (medium) {
      body = _LearnSlide(
        protocol: items.first,
        byId: byId,
        starred: items.first.id == learn.starred,
        highlighted: true,
        open: false,
        onToggle: null,
        onTap: openLibrary,
      );
    } else {
      final idx = _index.clamp(0, n - 1);
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A swipeable slide whose height follows its content, so nothing is
          // cut off and Show more can open the card to full length.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -150) _go(idx + 1, n);
              if (v > 150) _go(idx - 1, n);
            },
            child: AnimatedSize(
              duration: still ? Duration.zero : HwMotion.t4,
              curve: HwMotion.ease,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration:
                    still ? Duration.zero : const Duration(milliseconds: 320),
                switchInCurve: HwMotion.ease,
                switchOutCurve: HwMotion.ease,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, if (current != null) current],
                ),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(items[idx].id);
                  final from = Offset(incoming ? .25 * _dir : -.25 * _dir, 0);
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position:
                          Tween(begin: from, end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: _LearnSlide(
                  key: ValueKey(items[idx].id),
                  protocol: items[idx],
                  byId: byId,
                  starred: items[idx].id == learn.starred,
                  open: _open,
                  onToggle: () => setState(() => _open = !_open),
                  onTap: openLibrary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _CarouselControls(
            index: idx,
            count: n,
            onPrev: idx > 0 ? () => _go(idx - 1, n) : null,
            onNext: idx < n - 1 ? () => _go(idx + 1, n) : null,
          ),
        ],
      );
    }

    return _Section(
      title: 'Learn About Protocols',
      icon: HwIcons.book,
      helper: helper,
      linkLabel: 'Library',
      onLink: openLibrary,
      body: body,
    );
  }
}

class _LearnSlide extends StatelessWidget {
  final Protocol protocol;
  final Map<String, Protocol> byId;
  final bool starred;
  final bool highlighted;
  final bool open;

  /// Null hides Show more (the Medium size shows the summary only).
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  const _LearnSlide({
    super.key,
    required this.protocol,
    required this.byId,
    required this.starred,
    this.highlighted = false,
    required this.open,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final v = _V6.of(context);
    final steps = [
      for (final id in protocol.protocolPlusIds)
        if (byId[id] != null) byId[id]!,
    ];
    final stepCount =
        protocol.isProtocolPlus ? protocol.protocolPlusIds.length : 0;
    final goal = (protocol.goalTagName ?? '').split(' & ').first.trim();
    final meta = [
      '~${_mins(protocol)} min',
      if (stepCount > 0) _plural(stepCount, 'step'),
    ].join(' · ');
    final desc = protocol.description.trim();
    final hasMore =
        desc.isNotEmpty || steps.any((s) => s.description.trim().isNotEmpty);

    return HwPress(
      onTap: onTap,
      scale: .985,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: p.card2,
          borderRadius: BorderRadius.circular(14),
          border: highlighted
              ? Border.all(
                  color: const Color.fromRGBO(198, 158, 131, .55), width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (goal.isNotEmpty)
                  Flexible(child: HwPill(goal, tone: HwPillTone.copper)),
                const Spacer(),
                const SizedBox(width: 8),
                Text(
                  meta,
                  style: TextStyle(
                    fontSize: HwType.cap,
                    color: p.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              starred ? '${protocol.templateName} ★' : protocol.templateName,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: p.ink,
              ),
            ),
            if (steps.isNotEmpty) ...[
              // The arc: the stack's stages in order.
              const SizedBox(height: 2),
              Text(
                steps.map((s) => s.templateName).join(' → '),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: v.link,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    if (i > 0)
                      Text('→', style: TextStyle(fontSize: 11, color: p.ink3)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.line),
                      ),
                      child: Text(
                        steps[i].templateName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Show more: what the stack does, then each step and how it feels.
            AnimatedSize(
              duration: HwMotion.t4,
              curve: HwMotion.ease,
              alignment: Alignment.topCenter,
              child: !open || onToggle == null
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (desc.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
                            child: Text(
                              desc,
                              style: TextStyle(
                                fontSize: HwType.sm,
                                height: 1.5,
                                color: p.ink2,
                              ),
                            ),
                          ),
                        for (var i = 0; i < steps.length; i++)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: p.line2)),
                            ),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: '${i + 1}. ${steps[i].templateName}  ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: p.ink,
                                  ),
                                ),
                                TextSpan(
                                  text: steps[i].description.trim(),
                                  style: TextStyle(color: p.ink2),
                                ),
                              ]),
                              style:
                                  const TextStyle(fontSize: 12.5, height: 1.4),
                            ),
                          ),
                      ],
                    ),
            ),
            if (onToggle != null && hasMore)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          open ? 'Show less' : 'Show more',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: v.link,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: open ? .5 : 0,
                          duration: HwMotion.t2,
                          child: HwIcon(HwIcons.caret, size: 12, color: v.link),
                        ),
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

/// Progress track + "3 / 28" + both arrows, always visible (disabled at the
/// ends) — v5 replaced v4's dot row, which pushed the arrows off the card.
class _CarouselControls extends StatelessWidget {
  final int index;
  final int count;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _CarouselControls({
    required this.index,
    required this.count,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    Widget arrow(String icon, VoidCallback? onTap, String semantics) {
      final box = Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: p.line),
          ),
          child: Center(child: HwIcon(icon, size: 14, color: p.ink2)),
        ),
      );
      return Semantics(
        button: true,
        label: semantics,
        child: Opacity(
          opacity: onTap == null ? .35 : 1,
          child: onTap == null ? box : HwPress(onTap: onTap, child: box),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(HwRadius.pill),
            child: Container(
              height: 4,
              color: p.line,
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: HwMotion.t4,
                curve: HwMotion.ease,
                widthFactor: count == 0 ? 0 : (index + 1) / count,
                child: Container(color: p.copper),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          child: Text(
            '${count == 0 ? 0 : index + 1} / $count',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: HwType.cap,
              fontWeight: FontWeight.w700,
              color: p.ink3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 4),
        arrow(HwIcons.back, onPrev, 'Previous protocol'),
        arrow(HwIcons.chev, onNext, 'Next protocol'),
      ],
    );
  }
}

// ===========================================================================
// 6 · Lease a Device
// ===========================================================================

class HubLease extends ConsumerWidget {
  final HubSize size;
  const HubLease(this.size, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref
            .watch(clientListProvider)
            .valueOrNull
            ?.where((c) => c.isLeaseActive)
            .length ??
        0;
    // Leases are set up per client, from their profile in Users.
    void openLeases() => context.go(RoutePaths.users);
    final status = n > 0
        ? _plural(n, 'active lease')
        : 'Keep recovery going between visits';

    if (size == HubSize.small) {
      return _SmallRow(
        label: 'Lease a Device',
        icon: HwIcons.home2,
        title: 'Send a unit home',
        sub: status,
        actions: [_PillAction('Lease', primary: true, onTap: openLeases)],
      );
    }

    if (size == HubSize.medium) {
      return _Section(
        surface: _Surface.lease,
        title: 'Lease a Device',
        icon: HwIcons.home2,
        helper: 'Keep recovery going between visits',
        linkLabel: 'Leases',
        onLink: openLeases,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        body: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(198, 158, 131, .2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: HwIcon(HwIcons.home2, size: 20, color: _V6.tan),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send a Hydrawav3 unit home',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.md,
                      fontWeight: FontWeight.w700,
                      color: _V6.cream,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      color: _V6.cream.withValues(alpha: .72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PrimaryButton(
              label: 'Lease',
              onTap: openLeases,
              expand: false,
              arrow: true,
              nudge: true,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            ),
          ],
        ),
      );
    }

    return _Section(
      surface: _Surface.lease,
      title: 'Lease a Device',
      icon: HwIcons.home2,
      helper: 'Keep recovery going between visits',
      linkLabel: 'Leases',
      onLink: openLeases,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      backdrop: const Positioned(
        right: -6,
        bottom: -8,
        child: HubFloat(
          child: Opacity(
            opacity: .2,
            child: HwIcon(HwIcons.home2, size: 150, color: Color(0xFFC69E83)),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 230,
            child: Text(
              'Send a Hydrawav3 unit home.',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -.22,
                color: _V6.cream,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 230,
            child: Text(
              'Keep recovery going between visits.',
              style: TextStyle(
                fontSize: HwType.base,
                color: _V6.cream.withValues(alpha: .78),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PrimaryButton(
                label: 'Lease a unit',
                onTap: openLeases,
                expand: false,
                arrow: true,
                nudge: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              ),
              if (n > 0) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _plural(n, 'active lease'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _V6.cream.withValues(alpha: .7),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Game Ready board — no longer a Hub module in v6, still shown on Users.
// ===========================================================================

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
              style:
                  TextStyle(fontSize: HwType.cap, height: 1.45, color: p.ink2),
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
              // Full name, not just the first word — wraps within the
              // narrow cell rather than being cut down to one name part.
              client.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
