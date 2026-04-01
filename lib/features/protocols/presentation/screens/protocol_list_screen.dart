import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_loading.dart';
import '../../../../core/utils/extensions.dart';
import '../../domain/protocol_model.dart';
import '../providers/protocol_provider.dart';

class ProtocolListScreen extends ConsumerWidget {
  const ProtocolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protocolsAsync = ref.watch(protocolListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocols'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            onPressed: () => context.push(RoutePaths.chat),
            tooltip: 'AI Assistant',
          ),
        ],
      ),
      body: protocolsAsync.when(
        loading: () => const HwLoading(message: 'Loading protocols...'),
        error: (error, _) => HwErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(protocolListProvider),
        ),
        data: (protocols) {
          if (protocols.isEmpty) {
            return const HwEmptyState(
              icon: Icons.science_outlined,
              title: 'No Protocols Available',
              subtitle: 'Protocols will appear here once configured.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(protocolListProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(ThemeConstants.spacingMd),
              itemCount: protocols.length,
              itemBuilder: (context, index) =>
                  _ProtocolCard(protocol: protocols[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.presets),
        icon: const Icon(Icons.bookmark_outlined),
        label: const Text('Presets'),
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final Protocol protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingSm),
      child: InkWell(
        onTap: () => context.push('/protocols/${protocol.id}'),
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      protocol.templateName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeConstants.spacingSm,
                      vertical: ThemeConstants.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryColor.withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(ThemeConstants.radiusSm),
                    ),
                    child: Text(
                      protocol.totalDuration.formatted,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              if (protocol.description.isNotEmpty) ...[
                const SizedBox(height: ThemeConstants.spacingSm),
                Text(
                  protocol.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: ThemeConstants.spacingSm),
              Row(
                children: [
                  Icon(Icons.repeat, size: 16, color: ThemeConstants.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${protocol.cycles.length} cycles',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: ThemeConstants.spacingMd),
                  Icon(Icons.play_circle_outline, size: 16,
                      color: ThemeConstants.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${protocol.sessions} sessions',
                    style: Theme.of(context).textTheme.bodySmall,
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
