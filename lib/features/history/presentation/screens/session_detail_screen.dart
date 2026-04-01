import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Fetch session details from DB
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Social sharing
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Summary',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: ThemeConstants.spacingMd),
            _SummaryCard(
              children: [
                _SummaryRow('Date', 'Loading...'),
                _SummaryRow('Duration', 'Loading...'),
                _SummaryRow('Protocol', 'Loading...'),
                _SummaryRow('Device', 'Loading...'),
              ],
            ),
            const SizedBox(height: ThemeConstants.spacingMd),
            Text(
              'Discomfort Tracking',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: ThemeConstants.spacingSm),
            _SummaryCard(
              children: [
                _SummaryRow('Before', 'N/A'),
                _SummaryRow('After', 'N/A'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<Widget> children;

  const _SummaryCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingMd),
        child: Column(children: children),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
