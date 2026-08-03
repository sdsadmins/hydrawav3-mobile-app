import 'package:flutter/material.dart';

import '../../../../core/constants/legal_content.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';

/// Renders one `LegalContent` document (privacy, terms, acknowledgements) in a
/// scrollable sheet. Shared by the Legal screen and anywhere else that needs
/// to surface a policy without navigating away.
Future<void> showLegalInfoSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<InfoSheetSection> sections,
}) {
  return showHwSheet<void>(
    context: context,
    builder: (sheetContext) => _LegalInfoBody(
      title: title,
      subtitle: subtitle,
      sections: sections,
    ),
  );
}

class _LegalInfoBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<InfoSheetSection> sections;

  const _LegalInfoBody({
    required this.title,
    this.subtitle,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: HwType.lg,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
                fontSize: HwType.cap, height: 1.45, color: p.ink2),
          ),
        ],
        const SizedBox(height: HwSpace.s3),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final section in sections) ...[
                  Text(
                    section.heading,
                    style: TextStyle(
                      fontSize: HwType.md,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final paragraph in section.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        paragraph,
                        style: TextStyle(
                            fontSize: HwType.sm,
                            height: 1.55,
                            color: p.ink2),
                      ),
                    ),
                  for (final bullet in section.bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: p.copper,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              bullet,
                              style: TextStyle(
                                  fontSize: HwType.sm,
                                  height: 1.55,
                                  color: p.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: HwSpace.s3),
        HwButton(
          label: 'Close',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
