import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../../core/utils/extensions.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_plus_detail_provider.dart';
import '../providers/protocol_provider.dart';

/// The Protocol Library — ported from the UI spec's `renderLibrary()`
/// (app.js:2553).
///
/// Reached from More → Protocol Library. The wordmark header, token badge and
/// Active-devices rail this screen used to carry all moved to the Hub, so what
/// remains is purely the catalogue: goal chips, Protocol Plus stacks with
/// their sub-steps, then the individual protocols.
class ProtocolListScreen extends ConsumerStatefulWidget {
  const ProtocolListScreen({super.key});

  @override
  ConsumerState<ProtocolListScreen> createState() =>
      _ProtocolListScreenState();
}

class _ProtocolListScreenState extends ConsumerState<ProtocolListScreen> {
  /// Null = the "All" chip.
  String? _goalTagId;

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final protocolsAsync = ref.watch(protocolListProvider);
    final goalTagsAsync = ref.watch(goalTagListProvider);
    final plan = ref.watch(currentPlanProvider).valueOrNull;

    final goalTags = (goalTagsAsync.valueOrNull ?? [])
        .where((t) => t.isActive)
        .toList();

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.copper,
          backgroundColor: p.card,
          onRefresh: () async {
            ref.invalidate(protocolListProvider);
            ref.invalidate(goalTagListProvider);
            await ref.read(protocolListProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HwBackBar(
                        title: 'Protocol Library',
                        subtitle: _subtitle(
                          protocolsAsync.valueOrNull,
                          plan?.name,
                        ),
                        onBack: () => _back(context),
                      ),
                      if (goalTags.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        HwChipRow(
                          labels: [
                            'All',
                            for (final t in goalTags) _shortGoal(t.name),
                          ],
                          selectedIndex: _goalTagId == null
                              ? 0
                              : goalTags.indexWhere(
                                      (t) => t.id == _goalTagId) +
                                  1,
                          onSelected: (i) => setState(() {
                            _goalTagId = i == 0 ? null : goalTags[i - 1].id;
                          }),
                        ),
                      ],
                      const SizedBox(height: HwSpace.s2),
                    ],
                  ),
                ),
              ),
              ...protocolsAsync.when(
                loading: () => [const _LibrarySkeleton()],
                error: (e, _) => [
                  _Message(
                    "Couldn't load the protocol library.",
                    onRetry: () => ref.invalidate(protocolListProvider),
                  ),
                ],
                data: (all) => _body(all),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 108)),
            ],
          ),
        ),
      ),
    );
  }

  /// Stacks first, then protocols — each under its own eyebrow, exactly as the
  /// spec splits them.
  List<Widget> _body(List<Protocol> all) {
    final visible = _applyGoalFilter(all);
    if (visible == null) return [const _LibrarySkeleton()];

    final stacks = visible.where((p) => p.isProtocolPlus).toList()
      ..sort((a, b) => naturalCompare(a.templateName, b.templateName));
    final protocols = visible.where((p) => !p.isProtocolPlus).toList()
      ..sort((a, b) => naturalCompare(a.templateName, b.templateName));

    if (stacks.isEmpty && protocols.isEmpty) {
      return [
        const _Message(
          'Nothing under this goal yet — try another filter.',
        ),
      ];
    }

    return [
      if (stacks.isNotEmpty) ...[
        const _Eyebrow('Recommended stacks'),
        SliverList.builder(
          itemCount: stacks.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: _StackCard(stacks[i]),
          ),
        ),
      ],
      if (protocols.isNotEmpty) ...[
        const _Eyebrow('Protocols'),
        SliverList.builder(
          itemCount: protocols.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: _ProtocolCard(protocols[i]),
          ),
        ),
      ],
    ];
  }

  /// Intersects the full list with the goal-tag endpoint's ids. Returns null
  /// while that second call is still resolving, so the caller keeps the
  /// skeleton up rather than flashing an empty list.
  List<Protocol>? _applyGoalFilter(List<Protocol> all) {
    if (_goalTagId == null) return all;
    final ids =
        ref.watch(protocolSelectionOptionsProvider(_goalTagId)).valueOrNull;
    if (ids == null) return null;
    final idSet = ids.map((o) => o.id).toSet();
    return all.where((p) => idSet.contains(p.id)).toList();
  }

  String _subtitle(List<Protocol>? all, String? planName) {
    if (all == null) return 'Stacks & protocols by session goal';
    final stacks = all.where((p) => p.isProtocolPlus).length;
    final protocols = all.length - stacks;
    final plan = planName == null ? '' : ' · on $planName';
    return '$stacks stacks · $protocols protocols$plan';
  }

  /// The spec labels chips with the first word of the goal ("Performance &
  /// Readiness" → "Performance") so the row stays scannable.
  static String _shortGoal(String name) => name.split(' & ').first.trim();

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.settings);
    }
  }
}

// ---------------------------------------------------------------------------
// Stack card — a Protocol Plus sequence
// ---------------------------------------------------------------------------

class _StackCard extends ConsumerWidget {
  final Protocol stack;
  const _StackCard(this.stack);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final detail = ref.watch(protocolPlusDetailProvider(stack.id));
    final steps = detail.valueOrNull?.protocols ?? const <Protocol>[];
    final locked = !stack.active;

    return Opacity(
      opacity: locked ? .55 : 1,
      child: HwCard(
        onTap: locked
            ? () => _lockedNotice(context)
            : () => context.push('/protocols/${stack.id}'),
        padding: EdgeInsets.zero,
        // IntrinsicHeight bounds the row so the stripe can stretch to the
        // card's height. Without it, `stretch` inside a scroll view asks for
        // infinite height and the whole sliver fails to lay out.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `.stackcard` — a 4px validation stripe down the left edge.
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: steps.isNotEmpty ? p.good : p.mid,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(HwRadius.lg),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HwCardHeader(
                        stack.templateName,
                        trailing: locked
                            ? HwIcon(HwIcons.key, size: 16, color: p.ink3)
                            : HwPill(
                                '~${(stack.totalDurationSeconds / 60).round()} min',
                                tone: HwPillTone.copper,
                                tabular: true,
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        steps.isEmpty
                            ? 'Sequence'
                            : '${steps.map((s) => s.templateName).join(' → ')}'
                                ' · stack of ${steps.length}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: HwType.cap,
                          fontWeight: FontWeight.w600,
                          color: p.copperInk,
                        ),
                      ),
                      if (stack.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          stack.description,
                          style: TextStyle(
                              fontSize: HwType.cap,
                              height: 1.4,
                              color: p.ink3),
                        ),
                      ],
                      if (steps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (var i = 0; i < steps.length; i++)
                          _SubStep(index: i + 1, protocol: steps[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One numbered entry inside a stack — `.substep`, styles.css:600.
class _SubStep extends StatelessWidget {
  final int index;
  final Protocol protocol;
  const _SubStep({required this.index, required this.protocol});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: p.tanSoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: HwType.eyebrow,
                  fontWeight: FontWeight.w800,
                  color: p.copperInk,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: protocol.templateName,
                    style: TextStyle(
                      fontSize: HwType.sm,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                    children: [
                      TextSpan(
                        text: ' · ~'
                            '${(protocol.totalDurationSeconds / 60).round()} min',
                        style: TextStyle(
                          fontSize: HwType.cap,
                          fontWeight: FontWeight.w600,
                          color: p.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (protocol.description.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    protocol.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: HwType.cap, height: 1.4, color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Protocol card
// ---------------------------------------------------------------------------

class _ProtocolCard extends StatelessWidget {
  final Protocol protocol;
  const _ProtocolCard(this.protocol);

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final locked = !protocol.active;

    return Opacity(
      opacity: locked ? .55 : 1,
      child: HwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        onTap: locked
            ? () => _lockedNotice(context)
            : () => context.push('/protocols/${protocol.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HwCardHeader(
              protocol.templateName,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '~${(protocol.totalDurationSeconds / 60).round()}m',
                    style: TextStyle(
                      fontSize: HwType.cap,
                      color: p.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // The spec badges everything "Included"; this app has real
                  // plan gating, so say which it is.
                  locked
                      ? const HwPill('Locked', tone: HwPillTone.ghost)
                      : const HwPill('Included', tone: HwPillTone.good),
                ],
              ),
            ),
            if (protocol.goalTagName?.isNotEmpty == true) ...[
              const SizedBox(height: 3),
              Text(
                protocol.goalTagName!,
                style: TextStyle(
                  fontSize: HwType.cap,
                  fontWeight: FontWeight.w600,
                  color: p.copperInk,
                ),
              ),
            ],
            if (protocol.description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                protocol.description,
                style: TextStyle(
                    fontSize: HwType.cap, height: 1.4, color: p.ink3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _lockedNotice(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("This protocol isn't included in your plan."),
    ),
  );
}

// ---------------------------------------------------------------------------

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
        child: HwEyebrow(text),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _Message(this.text, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: HwType.sm, height: 1.5, color: p.ink2),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: HwSpace.s3),
              HwPress(
                onTap: onRetry!,
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: HwType.sm,
                    fontWeight: FontWeight.w700,
                    color: p.copperInk,
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

/// Breathing placeholders while the catalogue loads — never a spinner
/// (Principles §7).
class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return SliverList.builder(
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(HwRadius.lg),
            border: Border.all(color: p.cardline),
          ),
        ),
      ),
    );
  }
}
