import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
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
          padding: const EdgeInsets.all(16),
          children: [
            Text(p.templateName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.description, style: const TextStyle(fontSize: 14, color: ThemeConstants.textSecondary, height: 1.5)),
            ],
            const SizedBox(height: 16),
            // Info row
            Row(children: [
              _InfoChip(Icons.timer_outlined, p.totalDuration.formatted),
              const SizedBox(width: 8),
              _InfoChip(Icons.repeat_rounded, '${p.cycles.length} cycles'),
              const SizedBox(width: 8),
              _InfoChip(Icons.play_circle_outline_rounded, '${p.sessions} sessions'),
            ]),
            const SizedBox(height: 24),
            const Text('CYCLES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ThemeConstants.textTertiary, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            ...p.cycles.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cycle ${i + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 8),
                    _DetailRow('Duration', '${c.durationSeconds.toInt()}s'),
                    _DetailRow('Repetitions', '${c.repetitions}'),
                    _DetailRow('Hot PWM', '${c.hotPwm.toInt()}'),
                    _DetailRow('Cold PWM', '${c.coldPwm.toInt()}'),
                    if (c.leftFunction.isNotEmpty) _DetailRow('Left', c.leftFunction),
                    if (c.rightFunction.isNotEmpty) _DetailRow('Right', c.rightFunction),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => context.push(RoutePaths.session, extra: {'protocolId': p.id, 'deviceIds': <String>[]}),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Start Session'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: ThemeConstants.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: ThemeConstants.accent),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: ThemeConstants.textSecondary)),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: ThemeConstants.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
      ]),
    );
  }
}
