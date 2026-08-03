import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/legal_content.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../widgets/legal_info_sheet.dart';

/// Legal & licenses — ported from the UI spec's `renderLegal()` (app.js:3330).
///
/// Replaces the bottom sheet this content used to live in: the spec gives it a
/// screen, since the wellness statement and the Z-Anatomy attribution are
/// obligations rather than a menu.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HwBackBar(
                title: 'Legal & licenses',
                onBack: () => _back(context),
              ),
              const SizedBox(height: HwSpace.s2),

              HwCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HwEyebrow('Wellness statement'),
                    Text(
                      'Hydrawav3 is a general wellness & performance '
                      'platform, not a medical device. Sessions support '
                      'readiness, recovery, and mobility; they do not treat, '
                      'cure, or diagnose any condition.',
                      style: TextStyle(
                          fontSize: HwType.sm, height: 1.45, color: p.ink2),
                    ),
                  ],
                ),
              ),

              HwRowGroup(children: [
                _LinkRow(
                  icon: HwIcons.scale,
                  title: 'Privacy policy',
                  subtitle: 'hydrawav3.com/privacy',
                  onTap: () =>
                      _open(context, 'https://www.hydrawav3.com/privacy'),
                ),
                _LinkRow(
                  icon: HwIcons.phone,
                  title: 'Help center',
                  subtitle: 'hydrawav3.com/help-center',
                  onTap: () =>
                      _open(context, 'https://www.hydrawav3.com/help-center'),
                ),
                _LinkRow(
                  icon: HwIcons.doc,
                  title: 'Terms of service',
                  subtitle: 'Rules and responsibilities',
                  onTap: () => showLegalInfoSheet(
                    context,
                    title: 'Terms & Conditions',
                    subtitle: 'Rules and responsibilities for using the app.',
                    sections: LegalContent.termsAndConditionsSections,
                  ),
                ),
                _LinkRow(
                  icon: HwIcons.gear,
                  title: 'Privacy & security',
                  subtitle: 'Permissions and account protection',
                  onTap: () => showLegalInfoSheet(
                    context,
                    title: 'Privacy & Security',
                    subtitle: 'How Hydrawav3 handles permissions and '
                        'account protection.',
                    sections: LegalContent.privacyAndSecuritySections,
                  ),
                ),
              ]),

              HwCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HwEyebrow('Credits'),
                    Text(
                      // The Z-Anatomy licence requires this attribution.
                      '3D muscle model: Z-Anatomy (CC BY-SA 4.0), adapted '
                      'from BodyParts3D.',
                      style: TextStyle(
                          fontSize: HwType.sm, height: 1.45, color: p.ink2),
                    ),
                    const SizedBox(height: HwSpace.s2),
                    HwPress(
                      onTap: () => showLegalInfoSheet(
                        context,
                        title: 'Acknowledgements',
                        subtitle:
                            'Open-source and third-party content used here.',
                        sections: LegalContent.acknowledgementsSections,
                      ),
                      child: Text(
                        'All acknowledgements',
                        style: TextStyle(
                          fontSize: HwType.sm,
                          fontWeight: FontWeight.w700,
                          color: p.copperInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${AppConstants.appVersion} · BUILD '
                  '${AppConstants.buildNumber}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: p.ink3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.settings);
    }
  }

  static Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the link right now.')),
      );
    }
  }
}

class _LinkRow extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwRow(
      leading: HwIcon(icon, size: 19, color: p.copperInk),
      title: title,
      subtitle: subtitle,
      trailing: HwIcon(HwIcons.chev, size: 18, color: p.ink3),
      onTap: onTap,
    );
  }
}
