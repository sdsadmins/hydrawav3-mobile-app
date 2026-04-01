import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/hw_loading.dart';

final presetsProvider = StreamProvider<List<Preset>>((ref) {
  return ref.read(databaseProvider).watchPresets();
});

class PresetManagementScreen extends ConsumerWidget {
  const PresetManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetsAsync = ref.watch(presetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Presets')),
      body: presetsAsync.when(
        loading: () => const HwLoading(),
        error: (error, _) => HwErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(presetsProvider),
        ),
        data: (presets) {
          return ListView(
            padding: const EdgeInsets.all(ThemeConstants.spacingMd),
            children: [
              Text(
                'Quick Start Presets',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: ThemeConstants.spacingSm),
              Text(
                'Save your favorite device, protocol, and settings combinations for one-tap session start.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: ThemeConstants.spacingLg),
              ...List.generate(AppConstants.maxPresets, (index) {
                final preset = index < presets.length ? presets[index] : null;
                return _PresetSlot(
                  index: index + 1,
                  preset: preset,
                  onTap: () {
                    if (preset != null) {
                      // TODO: Load preset and navigate to session
                    } else {
                      // TODO: Show preset creation dialog
                    }
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _PresetSlot extends StatelessWidget {
  final int index;
  final Preset? preset;
  final VoidCallback onTap;

  const _PresetSlot({
    required this.index,
    this.preset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = preset == null;

    return Card(
      margin: const EdgeInsets.only(bottom: ThemeConstants.spacingMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingLg),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isEmpty
                    ? ThemeConstants.divider
                    : ThemeConstants.primaryColor,
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: isEmpty ? ThemeConstants.textTertiary : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: ThemeConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEmpty ? 'Empty Preset' : preset!.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isEmpty ? ThemeConstants.textTertiary : null,
                          ),
                    ),
                    if (!isEmpty)
                      Text(
                        'Tap to start session',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (isEmpty)
                      Text(
                        'Tap to configure',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Icon(
                isEmpty ? Icons.add_circle_outline : Icons.play_circle,
                color: isEmpty
                    ? ThemeConstants.textTertiary
                    : ThemeConstants.primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
