import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/theme_constants.dart';

class PresetManagementScreen extends ConsumerWidget {
  const PresetManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Demo presets — no DB dependency
    final presetNames = ['Full Body + Pro AI', null, null]; // 1 configured, 2 empty

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Presets')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Quick Start Presets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Save your favorite device + protocol combos for one-tap sessions.', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
          const SizedBox(height: 20),
          ...List.generate(AppConstants.maxPresets, (i) {
            final name = i < presetNames.length ? presetNames[i] : null;
            final empty = name == null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: ThemeConstants.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
                    child: Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: empty ? ThemeConstants.surfaceVariant : ThemeConstants.accent, borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text('${i + 1}', style: TextStyle(color: empty ? ThemeConstants.textTertiary : Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(empty ? 'Empty Slot' : name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: empty ? ThemeConstants.textTertiary : Colors.white)),
                              const SizedBox(height: 2),
                              Text(empty ? 'Tap to configure' : 'Tap to start session', style: const TextStyle(fontSize: 12, color: ThemeConstants.textTertiary)),
                            ],
                          ),
                        ),
                        Icon(empty ? Icons.add_circle_outline_rounded : Icons.play_circle_rounded, color: empty ? ThemeConstants.textTertiary : ThemeConstants.accent, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
