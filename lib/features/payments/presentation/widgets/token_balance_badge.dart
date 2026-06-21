import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../providers/token_balance_provider.dart';
import 'token_details_sheet.dart';

/// Small `Tokens` pill mirroring the web header. Red when the balance runs low
/// (< 80, same threshold as the web), otherwise the app accent. Hidden until the
/// balance is known. Tapping opens the token details sheet (override with [onTap]).
class TokenBalanceBadge extends ConsumerWidget {
  final VoidCallback? onTap;
  const TokenBalanceBadge({super.key, this.onTap});

  static const double _lowThreshold = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(tokenBalanceProvider);
    if (balance == null) return const SizedBox.shrink();

    final isLow = balance < _lowThreshold;
    final color = isLow ? Colors.red.shade600 : ThemeConstants.accent;

    return InkWell(
      onTap: onTap ?? () => showTokenDetailsSheet(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tokens',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  balance.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
