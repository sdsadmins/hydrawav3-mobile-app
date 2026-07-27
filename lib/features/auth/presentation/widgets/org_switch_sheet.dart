import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../providers/auth_provider.dart';
import '../screens/select_organization_page.dart' show organizationProvider;

/// One login, many organizations — the quick switcher the UI spec opens
/// straight from the Hub header (`orgSwitchSheet()`, app.js:2010), rather than
/// sending the practitioner off to another screen to change org.
Future<void> showOrgSwitchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // The Hub lives inside a ShellRoute, whose Navigator only covers the
    // Scaffold body. Without the root navigator the sheet would render behind
    // the bottom nav, leaving the tabs live under the scrim.
    useRootNavigator: true,
    builder: (_) => const _OrgSwitchSheet(),
  );
}

class _OrgSwitchSheet extends ConsumerWidget {
  const _OrgSwitchSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final auth = ref.watch(authStateProvider);
    final orgs = ref.watch(organizationProvider);
    final coach = (auth.user?.displayName ?? '').trim();

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(HwRadius.xl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 18),
              decoration: BoxDecoration(
                color: p.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Switch organization',
              style: TextStyle(
                fontSize: HwType.lg,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                coach.isEmpty
                    ? 'One login across every organization'
                    : '$coach · one login across every organization',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: HwType.cap, color: p.ink2),
              ),
            ),
            const SizedBox(height: HwSpace.s4),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                child: orgs.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => _Message(
                    text: "Couldn't load your organizations.",
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(organizationProvider),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return _Message(
                        text: 'You are not part of an organization yet.',
                        actionLabel: 'Create one',
                        onAction: () => _openCreateOrg(context),
                      );
                    }
                    return Column(
                      children: [
                        for (final org in list)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: HwSpace.s2),
                            child: _OrgRow(
                              org: org,
                              active: org['id'].toString() ==
                                  auth.selectedOrgId,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, HwSpace.s2, 18, 0),
              child: HwPress(
                onTap: () => _openCreateOrg(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HwRadius.sm),
                    border: Border.all(color: p.copper, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HwIcon(HwIcons.building, size: 16, color: p.copperInk),
                      const SizedBox(width: HwSpace.s2),
                      Text(
                        'Add organization',
                        style: TextStyle(
                          fontSize: HwType.sm,
                          fontWeight: FontWeight.w700,
                          color: p.copperInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            HwPress(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: HwType.cap,
                    fontWeight: FontWeight.w600,
                    color: p.ink3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCreateOrg(BuildContext context) {
    // Resolve the router before popping — this context is gone afterwards.
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push('/select-organization?create=1');
  }
}

class _OrgRow extends ConsumerWidget {
  final Map<String, dynamic> org;
  final bool active;
  const _OrgRow({required this.org, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final name = (org['name'] ?? 'Organization').toString();
    final subtitle = (org['description'] ?? org['type'] ?? '').toString();

    return HwCard(
      accented: active,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // Tapping the org you're already in does nothing — no pointless reload.
      onTap: active
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              await ref
                  .read(authStateProvider.notifier)
                  .setOrganization(org['id'].toString(), name);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Switched to $name')),
              );
            },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active ? p.tanSoft : p.bg2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: HwIcon(
                HwIcons.building,
                size: 19,
                color: active ? p.copperInk : p.ink3,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: HwType.md,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: HwType.eyebrow, color: p.ink3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: HwSpace.s2),
          if (active)
            const HwPill('Active', tone: HwPillTone.copper)
          else
            HwIcon(HwIcons.chev, size: 18, color: p.ink3),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: HwType.sm, color: p.ink2),
          ),
          const SizedBox(height: HwSpace.s3),
          HwPress(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: TextStyle(
                fontSize: HwType.sm,
                fontWeight: FontWeight.w700,
                color: p.copperInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
