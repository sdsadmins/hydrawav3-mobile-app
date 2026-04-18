import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/premium.dart';

class PresetManagementScreen extends ConsumerWidget {
  const PresetManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presetNames = ['Full Body + Pro AI', null, null];

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3040), ThemeConstants.background],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: AnimatedEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: ThemeConstants.surfaceVariant, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Text('Quick Presets', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                        const SizedBox(height: 8),
                        const Text('Save your favorite combos for one-tap sessions', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final name = i < presetNames.length ? presetNames[i] : null;
                final empty = name == null;
                return AnimatedEntrance(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GradientCard(
                      onTap: () {},
                      showGlow: !empty,
                      gradientColors: empty
                          ? [ThemeConstants.surface, ThemeConstants.surface]
                          : [ThemeConstants.accent.withValues(alpha: 0.06), ThemeConstants.surface],
                      padding: const EdgeInsets.all(18),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            gradient: empty ? null : const LinearGradient(colors: [ThemeConstants.accent, Color(0xFFE09060)]),
                            color: empty ? ThemeConstants.surfaceVariant : null,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: empty ? null : [BoxShadow(color: ThemeConstants.accent.withValues(alpha: 0.2), blurRadius: 8)],
                          ),
                          child: Center(child: Text('${i + 1}', style: TextStyle(color: empty ? ThemeConstants.textTertiary : Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(empty ? 'Empty Slot' : name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: empty ? ThemeConstants.textTertiary : Colors.white)),
                            const SizedBox(height: 2),
                            Text(empty ? 'Tap to configure' : 'Tap to start session', style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                          ],
                        )),
                        Icon(empty ? Icons.add_circle_outline_rounded : Icons.play_circle_rounded, color: empty ? ThemeConstants.textTertiary : ThemeConstants.accent, size: 26),
                      ]),
                    ),
                  ),
                );
              }, childCount: AppConstants.maxPresets),
            ),
          ),
        ],
      ),
    );
  }
}
