import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../providers/token_balance_provider.dart';
import 'token_details_sheet.dart';

/// The plan badge in a screen's top bar — the UI spec's `.tokenbadge`
/// (styles.css:372, `tokenBadgeHTML()` at app.js:2240).
///
/// Reads **"Enterprise"** for any package plan, whatever the product is called
/// ("Pro+", "Pro Team", …) — the pill names the category, and the product's own
/// name heads the plan sheet behind it. Never a raw credit count; the balance
/// and usage live one tap away. Tan-soft pill, copper-on-surface text, a
/// diamond glyph and a caret.
class TokenBalanceBadge extends ConsumerWidget {
  final VoidCallback? onTap;
  const TokenBalanceBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final plan = ref.watch(currentPlanProvider).valueOrNull;

    // Nothing to name yet — stay out of the way rather than show a placeholder.
    final label = plan?.badgeLabel.trim();
    if (label == null || label.isEmpty) return const SizedBox.shrink();

    return HwPress(
      scale: 0.9,
      onTap: onTap ?? () => showTokenDetailsSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: p.tanSoft,
          borderRadius: BorderRadius.circular(HwRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '◈ ',
              style: TextStyle(
                fontSize: HwType.cap,
                fontWeight: FontWeight.w800,
                color: p.copperInk,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HwType.cap,
                  fontWeight: FontWeight.w800,
                  color: p.copperInk,
                ),
              ),
            ),
            const SizedBox(width: 4),
            HwIcon(HwIcons.caret, size: 12, color: p.copperInk),
          ],
        ),
      ),
    );
  }
}
