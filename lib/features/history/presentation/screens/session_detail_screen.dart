import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';

class SessionDetailScreen extends ConsumerWidget {
  final String sessionId;
  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(title: const Text('Session Details'), actions: [
        IconButton(icon: const Icon(Icons.share_rounded, color: ThemeConstants.accent), onPressed: () {}),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Session Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 12),
          _Card(children: [_Row('Date', 'Loading...'), _Row('Duration', 'Loading...'), _Row('Protocol', 'Loading...'), _Row('Device', 'Loading...')]),
          const SizedBox(height: 16),
          const Text('Discomfort Tracking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 12),
          _Card(children: [_Row('Before', 'N/A'), _Row('After', 'N/A')]),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: ThemeConstants.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.border)),
      child: Column(children: children.asMap().entries.map((e) => Column(children: [
        e.value,
        if (e.key < children.length - 1) const Divider(height: 1, indent: 16, endIndent: 16, color: ThemeConstants.border),
      ])).toList()),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 14, color: ThemeConstants.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
      ]),
    );
  }
}
