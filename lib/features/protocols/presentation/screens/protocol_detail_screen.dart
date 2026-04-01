import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/utils/extensions.dart';
import '../providers/protocol_provider.dart';

class ProtocolDetailScreen extends ConsumerWidget {
  final String protocolId;

  const ProtocolDetailScreen({super.key, required this.protocolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocolAsync = ref.watch(protocolDetailProvider(protocolId));

    return Scaffold(
      appBar: AppBar(title: const Text('Protocol Details')),
      body: protocolAsync.when(
        loading: () => const HwLoading(),
        error: (error, _) => HwErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(protocolDetailProvider(protocolId)),
        ),
        data: (protocol) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(ThemeConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  protocol.templateName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: ThemeConstants.spacingSm),
                if (protocol.description.isNotEmpty) ...[
                  Text(
                    protocol.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: ThemeConstants.spacingMd),
                ],
                // Info chips
                Wrap(
                  spacing: ThemeConstants.spacingSm,
                  runSpacing: ThemeConstants.spacingSm,
                  children: [
                    _InfoChip(
                      icon: Icons.timer,
                      label: 'Duration: ${protocol.totalDuration.formatted}',
                    ),
                    _InfoChip(
                      icon: Icons.repeat,
                      label: '${protocol.cycles.length} Cycles',
                    ),
                    _InfoChip(
                      icon: Icons.play_circle,
                      label: '${protocol.sessions} Sessions',
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingLg),
                Text(
                  'Cycles',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: ThemeConstants.spacingSm),
                ...protocol.cycles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cycle = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(
                        bottom: ThemeConstants.spacingSm),
                    child: Padding(
                      padding:
                          const EdgeInsets.all(ThemeConstants.spacingMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cycle ${index + 1}',
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: ThemeConstants.spacingSm),
                          _DetailRow('Duration',
                              '${cycle.durationSeconds.toInt()}s'),
                          _DetailRow(
                              'Repetitions', '${cycle.repetitions}'),
                          _DetailRow(
                              'Hot PWM', cycle.hotPwm.toStringAsFixed(0)),
                          _DetailRow('Cold PWM',
                              cycle.coldPwm.toStringAsFixed(0)),
                          if (cycle.leftFunction.isNotEmpty)
                            _DetailRow('Left', cycle.leftFunction),
                          if (cycle.rightFunction.isNotEmpty)
                            _DetailRow('Right', cycle.rightFunction),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: ThemeConstants.spacingLg),
                HwButton(
                  label: 'Start Session',
                  icon: Icons.play_arrow,
                  onPressed: () {
                    context.push(
                      RoutePaths.session,
                      extra: {
                        'protocolId': protocol.id,
                        'deviceIds': <String>[],
                      },
                    );
                  },
                ),
                const SizedBox(height: ThemeConstants.spacingMd),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
