import 'package:flutter/material.dart';

import '../../../../core/constants/theme_constants.dart';

/// A tappable field row showing a label + current value + chevron, matching the
/// protocol picker field in `session_setup_screen.dart`. Tapping opens a bottom
/// sheet (no Material dropdown widgets — app convention).
class PickerField extends StatelessWidget {
  final String? label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final IconData icon;
  final Widget? trailing;

  const PickerField({
    super.key,
    this.label,
    required this.value,
    this.placeholder = 'Select',
    this.onTap,
    this.icon = Icons.keyboard_arrow_down_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: ThemeConstants.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ThemeConstants.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasValue
                          ? ThemeConstants.textPrimary
                          : ThemeConstants.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(icon, color: ThemeConstants.textTertiary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Show a themed single-select bottom sheet and return the chosen option.
Future<T?> showOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final opt = options[i];
                  final isSelected = selected == opt;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(ctx).pop(opt),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? ThemeConstants.accent.withValues(alpha: 0.14)
                            : ThemeConstants.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? ThemeConstants.accent
                              : ThemeConstants.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: isSelected
                                ? ThemeConstants.accent
                                : ThemeConstants.textTertiary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              labelOf(opt),
                              style: TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Show a themed multi-select bottom sheet (chips). Returns the chosen list, or
/// null if dismissed. Used for worsening/improving factors.
Future<List<String>?> showMultiSelectPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  bool allowCustom = true,
}) {
  final chosen = {...selected};
  final custom = <String>[
    ...selected.where((s) => !options.contains(s)),
  ];
  final controller = TextEditingController();
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final all = [...options, ...custom];
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: all.map((o) {
                    final sel = chosen.contains(o);
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setSheet(() {
                        if (sel) {
                          chosen.remove(o);
                        } else {
                          chosen.add(o);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: sel
                              ? ThemeConstants.accent.withValues(alpha: 0.16)
                              : ThemeConstants.surfaceVariant
                                  .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: sel
                                ? ThemeConstants.accent
                                : ThemeConstants.border,
                          ),
                        ),
                        child: Text(
                          o,
                          style: TextStyle(
                            color: sel
                                ? ThemeConstants.accent
                                : ThemeConstants.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (allowCustom) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add custom…',
                            hintStyle:
                                TextStyle(color: ThemeConstants.textTertiary),
                            filled: true,
                            fillColor: ThemeConstants.surfaceVariant
                                .withValues(alpha: 0.7),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: ThemeConstants.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: ThemeConstants.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          final v = controller.text.trim();
                          if (v.isEmpty) return;
                          setSheet(() {
                            if (!custom.contains(v) && !options.contains(v)) {
                              custom.add(v);
                            }
                            chosen.add(v);
                            controller.clear();
                          });
                        },
                        icon: Icon(Icons.add_circle_rounded,
                            color: ThemeConstants.accent),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(chosen.toList()),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
