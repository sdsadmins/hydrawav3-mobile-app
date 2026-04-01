import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/theme/widgets/hw_button.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current plan
            Card(
              child: Padding(
                padding: const EdgeInsets.all(ThemeConstants.spacingLg),
                child: Column(
                  children: [
                    const Icon(Icons.workspace_premium,
                        size: 48, color: ThemeConstants.textTertiary),
                    const SizedBox(height: ThemeConstants.spacingSm),
                    Text('Free Plan',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: ThemeConstants.spacingSm),
                    Text(
                      'Upgrade to unlock advanced features',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ThemeConstants.spacingLg),

            // Practitioner plan
            Card(
              color: ThemeConstants.primaryColor.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(ThemeConstants.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: ThemeConstants.primaryColor),
                        const SizedBox(width: ThemeConstants.spacingSm),
                        Text('Practitioner Plan',
                            style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: ThemeConstants.spacingMd),
                    _FeatureItem('Advanced temperature & vibration controls'),
                    _FeatureItem('3 custom presets'),
                    _FeatureItem('Session goals & recommendations'),
                    _FeatureItem('AI chatbot assistant'),
                    _FeatureItem('Default memory system'),
                    const SizedBox(height: ThemeConstants.spacingMd),
                    HwButton(
                      label: 'Upgrade Now',
                      onPressed: () {
                        // TODO: Stripe checkout
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String text;

  const _FeatureItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              size: 20, color: ThemeConstants.success),
          const SizedBox(width: ThemeConstants.spacingSm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
