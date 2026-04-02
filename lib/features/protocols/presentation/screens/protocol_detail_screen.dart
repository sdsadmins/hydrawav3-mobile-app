import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../../../core/utils/extensions.dart';
import '../providers/protocol_provider.dart';

class ProtocolDetailScreen extends ConsumerWidget {
  final String protocolId;
  const ProtocolDetailScreen({super.key, required this.protocolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(protocolDetailProvider(protocolId));

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Protocol Details')),
      body: async.when(
        loading: () => const HwLoading(),
        error: (e, _) => HwErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(protocolDetailProvider(protocolId))),
        data: (p) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedEntrance(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.templateName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.3)),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(p.description, style: const TextStyle(fontSize: 14, color: ThemeConstants.textSecondary, height: 1.5)),
                ],
              ],
            )),
            const SizedBox(height: 16),
            AnimatedEntrance(index: 1, child: Row(children: [
              StatChip(icon: Icons.timer_outlined, value: p.totalDuration.formatted),
              const SizedBox(width: 8),
              StatChip(icon: Icons.repeat_rounded, value: '${p.cycles.length}', label: 'cycles'),
              const SizedBox(width: 8),
              StatChip(icon: Icons.play_circle_outline_rounded, value: '${p.sessions}', label: 'sessions'),
            ])),
            const SizedBox(height: 24),
            AnimatedEntrance(index: 2, child: const SectionHeader(title: 'Cycles')),
            ...p.cycles.asMap().entries.map((e) {
              final i = e.key; final c = e.value;
              return AnimatedEntrance(index: i + 3, child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GradientCard(padding: const EdgeInsets.all(16), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GlowIconBox(icon: Icons.loop_rounded, size: 36, iconSize: 18),
                      const SizedBox(width: 12),
                      Text('Cycle ${i + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    ]),
                    const SizedBox(height: 12),
                    _R('Duration', '${c.durationSeconds.toInt()}s'), _R('Repetitions', '${c.repetitions}'),
                    _R('Hot PWM', '${c.hotPwm.toInt()}'), _R('Cold PWM', '${c.coldPwm.toInt()}'),
                    if (c.leftFunction.isNotEmpty) _R('Left', c.leftFunction),
                    if (c.rightFunction.isNotEmpty) _R('Right', c.rightFunction),
                  ],
                )),
              ));
            }),
            const SizedBox(height: 20),
            AnimatedEntrance(index: p.cycles.length + 3, child: GestureDetector(
              onTap: () => context.push(RoutePaths.session, extra: {'protocolId': p.id, 'deviceIds': <String>[]}),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [ThemeConstants.accent, Color(0xFFE09060)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('Start Session', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _R extends StatelessWidget {
  final String l, v;
  const _R(this.l, this.v);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
      Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
    ]),
  );
}
