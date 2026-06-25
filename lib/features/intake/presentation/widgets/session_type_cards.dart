import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../providers/guided_assessment_provider.dart';

/// Guided Assessment vs Quick Start chooser (web parity). Drives
/// [sessionTypeProvider].
class SessionTypeCards extends ConsumerWidget {
  const SessionTypeCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(sessionTypeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: _card(
              active: type == SessionType.guided,
              icon: Icons.auto_awesome_rounded,
              title: 'Guided Assessment',
              subtitle: 'AI intake & report',
              onTap: () => ref.read(sessionTypeProvider.notifier).state =
                  SessionType.guided,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _card(
              active: type == SessionType.quick,
              icon: Icons.bolt_rounded,
              title: 'Quick Start',
              subtitle: 'Skip the intake',
              onTap: () => ref.read(sessionTypeProvider.notifier).state =
                  SessionType.quick,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required bool active,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active
              ? ThemeConstants.accent.withValues(alpha: 0.14)
              : ThemeConstants.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? ThemeConstants.accent : ThemeConstants.border,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: active
                    ? ThemeConstants.accent
                    : ThemeConstants.textSecondary),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
