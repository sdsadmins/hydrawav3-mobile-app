import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../../devices/presentation/widgets/session_plan_widgets.dart';
import '../../data/store_region.dart';
import '../../data/web_plan_link.dart';

/// Shown when a locked protocol (not in the org's plan) is tapped.
///
/// US storefront: "Upgrade your plan" with a button to the website's plan
/// page — the US link-out the Epic v. Apple / Epic v. Google orders allow.
/// Everywhere else: information only — no upgrade wording, price or purchase
/// link (Apple 3.1.1 / Google Play billing); the button opens the in-app,
/// read-only Plan & usage screen.
Future<void> showPlanLockedSheet(BuildContext context, {String? protocolName}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final us = container.read(isUsStorefrontProvider);
  final name = (protocolName == null || protocolName.trim().isEmpty)
      ? 'This protocol'
      : protocolName.trim();
  return showPlanSheet<void>(
    context,
    title: us ? 'Upgrade your plan' : 'Not in your plan',
    subtitle: us
        ? "$name isn't included in your current plan."
        : "$name isn't included in your organization's current plan.",
    builder: (_) => _PlanLockedBody(us: us),
  );
}

class _PlanLockedBody extends ConsumerWidget {
  final bool us;
  const _PlanLockedBody({required this.us});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = PlanTones.dark(context);
    final router = GoRouter.maybeOf(context);

    void showPlan() {
      Navigator.of(context).pop();
      router?.push(RoutePaths.subscription);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PlanTones.copper.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PlanTones.copper.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: dark ? const Color(0xFFE2C0A2) : PlanTones.copperDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  us
                      ? 'Upgrade to unlock this protocol and the rest of the '
                          'library. You finish on the Hydrawav3 website, then '
                          'come back here.'
                      : 'Choose another protocol, or see what your plan '
                          'includes.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: dark
                        ? const Color(0xFFF1E4D6)
                        : const Color(0xFF3A2E24),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (us)
          PlanPrimaryButton(
            label: 'Upgrade plan',
            onTap: () async {
              await openWebPlan(context, ref);
              if (context.mounted) Navigator.of(context).pop();
            },
          )
        else
          PlanPrimaryButton(label: 'View plan & usage', onTap: showPlan),
        const SizedBox(height: 10),
        // `btn soft`: the quiet second action.
        PlanPress(
          onTap: us ? showPlan : () => Navigator.of(context).maybePop(),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1F2A32) : const Color(0xFFF2E9E2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              us ? 'View plan & usage' : 'Choose another protocol',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color:
                    dark ? const Color(0xFFDDCABF) : const Color(0xFF8A5F42),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
