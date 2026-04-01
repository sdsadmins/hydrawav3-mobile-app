import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/storage/local_db.dart';
import '../../../../core/theme/widgets/glass_container.dart';
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ThemeConstants.darkTeal, Color(0xFF0F1E25)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text('📌 Quick Presets',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '⚡ Save your favorite device + protocol combos for one-tap sessions',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
              const SizedBox(height: 24),

              // Preset slots
              Expanded(
                child: presetsAsync.when(
                  loading: () => const HwLoading(),
                  error: (e, _) => HwErrorWidget(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(presetsProvider)),
                  data: (presets) => ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: AppConstants.maxPresets,
                    itemBuilder: (context, index) {
                      final preset =
                          index < presets.length ? presets[index] : null;
                      final isEmpty = preset == null;
                      final slotEmojis = ['🥇', '🥈', '🥉'];

                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration:
                            Duration(milliseconds: 500 + index * 150),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 30 * (1 - value)),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: GlassContainer(
                            opacity: isEmpty ? 0.04 : 0.08,
                            onTap: () {
                              // TODO: Load preset or show create dialog
                            },
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: isEmpty
                                        ? null
                                        : const LinearGradient(
                                            colors: [
                                              ThemeConstants.copper,
                                              ThemeConstants.tanLight,
                                            ],
                                          ),
                                    color: isEmpty
                                        ? Colors.white
                                            .withValues(alpha: 0.06)
                                        : null,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: Center(
                                    child: Text(
                                      slotEmojis[index],
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isEmpty
                                            ? '➕ Empty Slot'
                                            : preset.name,
                                        style: TextStyle(
                                          color: isEmpty
                                              ? Colors.white
                                                  .withValues(alpha: 0.4)
                                              : Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isEmpty
                                            ? 'Tap to configure'
                                            : '▶️ Tap to start session',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.4),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isEmpty
                                      ? Icons.add_circle_outline_rounded
                                      : Icons.play_circle_rounded,
                                  color: isEmpty
                                      ? Colors.white
                                          .withValues(alpha: 0.2)
                                      : ThemeConstants.copper,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
