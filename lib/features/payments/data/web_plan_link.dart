import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/storage/secure_storage.dart';
import '../../auth/presentation/providers/auth_provider.dart';

/// US storefront only. The website's login handoff, which signs the browser
/// in with this app's login and lands on the plan page:
/// `<site>/auth/handoff?token=Bearer …&refreshToken=Bearer …&orgId=…&redirect=/practitioner/subscription`
/// (web `Hydrawav3-ai` `auth/handoff/route.ts`). Without a login it is just
/// the plan page.
Future<Uri> webPlanLink(WidgetRef ref) async {
  final plan = Uri.parse(ApiEndpoints.practitionerSubscriptionUrl);
  final storage = ref.read(secureStorageProvider);
  final access = await storage.getAccessToken();
  final refresh = await storage.getRefreshToken();
  final org = ref.read(authStateProvider).selectedOrgId ??
      await storage.getSelectedOrgId();
  if (access == null || access.isEmpty) return plan;
  String bearer(String t) => t.startsWith('Bearer ') ? t : 'Bearer $t';
  return plan.replace(path: '/auth/handoff', queryParameters: {
    'token': bearer(access),
    if (refresh != null && refresh.isNotEmpty) 'refreshToken': bearer(refresh),
    if (org != null && org.isNotEmpty) 'orgId': org,
    'redirect': plan.path.isEmpty ? '/practitioner/subscription' : plan.path,
  });
}

/// Opens [webPlanLink] in a Safari sheet / Chrome Custom Tab over the app
/// (the browser's own page, not an app web view). US storefront only.
Future<void> openWebPlan(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final link = await webPlanLink(ref);
  final ok = await launchUrl(link, mode: LaunchMode.inAppBrowserView);
  if (!ok) {
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't open the browser.")),
    );
  }
}
