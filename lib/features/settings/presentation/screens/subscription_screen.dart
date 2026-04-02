import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current plan
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_rounded, size: 40, color: ThemeConstants.textTertiary),
                const SizedBox(height: 12),
                const Text('Free Plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Upgrade to unlock advanced features', style: TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pro plan
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.accent, width: 1.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.star_rounded, color: ThemeConstants.accent, size: 22),
                  const SizedBox(width: 8),
                  const Text('Practitioner Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
                const SizedBox(height: 16),
                ...[
                  'Advanced temperature & vibration controls',
                  '3 custom presets',
                  'Session goals & recommendations',
                  'AI chatbot assistant',
                  'Default memory system',
                ].map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: ThemeConstants.success),
                    const SizedBox(width: 10),
                    Text(f, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ]),
                )),
                const SizedBox(height: 12),
                SizedBox(height: 48, width: double.infinity, child: ElevatedButton(onPressed: () {}, child: const Text('Upgrade Now'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
