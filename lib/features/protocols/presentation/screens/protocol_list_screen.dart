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
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        title: const Text('Protocols'),
        actions: [
          IconButton(icon: const Icon(Icons.bookmark_outline_rounded, color: ThemeConstants.accent), onPressed: () => context.push(RoutePaths.presets), tooltip: 'Presets'),
          IconButton(icon: const Icon(Icons.smart_toy_outlined, color: ThemeConstants.accent), onPressed: () => context.push(RoutePaths.chat), tooltip: 'AI Assistant'),
        ],
      ),
      body: protocolsAsync.when(
        loading: () => const HwLoading(message: 'Loading protocols...'),
        error: (e, _) => HwErrorWidget(message: e.toString(), onRetry: () => ref.invalidate(protocolListProvider)),
        data: (protocols) {
          if (protocols.isEmpty) {
            return const HwEmptyState(icon: Icons.science_outlined, title: 'No Protocols Yet', subtitle: 'Protocols will appear here once configured.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(protocolListProvider),
            color: ThemeConstants.accent,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: protocols.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _ProtocolTile(protocol: protocols[index]),
            ),
          );
        },
      ),
    );
  }
}

class _ProtocolTile extends StatelessWidget {
  final Protocol protocol;
  const _ProtocolTile({required this.protocol});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeConstants.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/protocols/${protocol.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeConstants.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.science_rounded, color: ThemeConstants.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(protocol.templateName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${protocol.totalDuration.formatted}  ·  ${protocol.cycles.length} cycles  ·  ${protocol.sessions} sessions',
                        style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: ThemeConstants.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
