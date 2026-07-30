import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../payments/presentation/providers/token_balance_provider.dart';

/// The AI Hub — three cards, ported from the UI spec's `renderAIHub()`
/// (app.js:2708).
///
/// Chat, reports and the guided assessment each get one entry point rather
/// than being scattered across the More list.
class AiHubScreen extends ConsumerWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final plan = ref.watch(currentPlanProvider).valueOrNull;
    final grant = ref.watch(planTokenGrantProvider).valueOrNull;

    // Reports left comes straight from the plan; the period total is derived
    // from the product's token grant, exactly as the plan sheet does it.
    final left = plan?.aiReportsAvailable;
    final total = plan?.totalForGrant(left, grant)?.round();

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
                title: 'AI Hub',
                subtitle: (left != null && total != null)
                    ? '${total - left} of $total AI reports used this month'
                    : 'Chat, reports & guided assessment',
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),

              // 1 — AI Assistant, on the dark hero fill.
              _HeroCard(
                title: 'AI Assistant',
                pill: 'Chat',
                body: 'Ask about protocols, placement, recovery — '
                    'streaming answers.',
                onTap: () => context.go(RoutePaths.assistant),
              ),

              // 2 — reports, per client. Reports belong to a person, so this
              // opens the client list and their reports are one tap in;
              // `/ai-reports` with no client would flatten every org report
              // into one anonymous list.
              HwCard(
                onTap: () => context.push(RoutePaths.aiReportClients),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HwCardHeader(
                      'AI Reports',
                      trailing: left == null
                          ? null
                          : HwPill('$left left', tone: HwPillTone.copper),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kinetic-chain reports with placements & at-home plans.',
                      style: TextStyle(
                          fontSize: HwType.sm, height: 1.45, color: p.ink2),
                    ),
                  ],
                ),
              ),

              // 3 — start a guided assessment. This used to land on the Session
              // tab because the wizard was only reachable inline from session
              // setup; it's now its own screen, so the card goes straight there.
              HwCard(
                onTap: () => context.push(RoutePaths.guidedAssessment),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HwCardHeader(
                      'Generate a report',
                      trailing: HwPill('~2 min'),
                    ),
                    SizedBox(height: 4),
                    _Body(
                      'Complete Area of Focus, Range of Motion, Daily '
                      'Activities, Sleep posture and Hardest position to '
                      'generate a report.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.settings);
    }
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: HwType.sm,
        height: 1.45,
        color: RefPalette.of(context).ink2,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String pill;
  final String body;
  final VoidCallback onTap;

  const _HeroCard({
    required this.title,
    required this.pill,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    const cream = Color(0xFFF2E9E2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: HwPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(HwSpace.s4),
          decoration: BoxDecoration(
            gradient: p.heroGrad,
            borderRadius: BorderRadius.circular(HwRadius.lg),
            boxShadow: p.shadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // `.tile-glow` — the soft radial bleed off the bottom-right.
              Positioned(
                right: -40,
                bottom: -52,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color.fromRGBO(255, 255, 255, .28),
                        Colors.transparent
                      ],
                      stops: [0, .7],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: HwType.md,
                            fontWeight: FontWeight.w600,
                            color: cream,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 255, 255, .15),
                          borderRadius:
                              BorderRadius.circular(HwRadius.pill),
                        ),
                        child: Text(
                          pill,
                          style: const TextStyle(
                            fontSize: HwType.eyebrow,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFDDCABF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: HwType.cap,
                      height: 1.45,
                      color: cream.withValues(alpha: .85),
                    ),
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
