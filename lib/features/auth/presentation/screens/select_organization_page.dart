import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/network/dio_client.dart';
import '../providers/auth_provider.dart';

final organizationProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(djangoDioProvider);
  final response = await dio.get('/admin/organizations');
  return List<Map<String, dynamic>>.from(response.data);
});

class SelectOrganizationPage extends ConsumerStatefulWidget {
  const SelectOrganizationPage({super.key});

  @override
  ConsumerState<SelectOrganizationPage> createState() =>
      _SelectOrganizationPageState();
}

class _SelectOrganizationPageState
    extends ConsumerState<SelectOrganizationPage> {
  String? selectedOrgId;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.refresh(organizationProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(organizationProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: Container(
        decoration: BoxDecoration(color: ThemeConstants.background),
        child: SafeArea(
          child: orgAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Center(
              child: Text(
                'Failed to load organizations\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: ThemeConstants.textPrimary),
              ),
            ),
            data: (orgs) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height, // ✅ FULL HEIGHT
                  child: Center(
                    // ✅ TRUE CENTER
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center, // ✅ CENTER VERTICALLY
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔥 TITLE
                            Text(
                              "Select Your Organization",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: ThemeConstants.textPrimary,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              "Choose the organization you want to work with.\nEasily collaborate, manage files, and stay in sync.",
                              style: TextStyle(
                                fontSize: 13,
                                color: ThemeConstants.textSecondary,
                              ),
                            ),

                            const SizedBox(height: 30),

                            /// 🔥 LIST
                            ...orgs.map((org) {
                              final orgId = org['id'].toString();
                              final isSelected = selectedOrgId == orgId;

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: isSelected
                                      ? ThemeConstants.accent
                                          .withValues(alpha: 0.14)
                                      : ThemeConstants.surface,
                                  border: Border.all(
                                    color: isSelected
                                        ? ThemeConstants.accent
                                        : ThemeConstants.border,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? ThemeConstants.accent
                                              .withValues(alpha: 0.3)
                                          : Colors.black12,
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    setState(() {
                                      selectedOrgId = orgId;
                                    });

                                    await ref
                                        .read(authStateProvider.notifier)
                                        .setOrganization(
                                          orgId,
                                          org['name'] ??
                                              'Organization', // ✅ PASS NAME
                                        );

                                    if (mounted) {
                                      context.go(RoutePaths.protocols);
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white
                                              .withValues(alpha: 0.1),
                                        ),
                                        child: Icon(
                                          Icons.business,
                                          color: ThemeConstants.textPrimary,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          org['name'] ?? 'Organization',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: ThemeConstants.textPrimary,
                                          ),
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        child: isSelected
                                            ? Icon(
                                                Icons.check_circle,
                                                color:
                                                    ThemeConstants.textPrimary,
                                              )
                                            : Icon(
                                                Icons.arrow_forward_ios,
                                                color:
                                                    ThemeConstants.textTertiary,
                                                size: 16,
                                              ),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
