

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/network/dio_client.dart';
import '../providers/auth_provider.dart';

final organizationProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(organizationProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E3040),
              ThemeConstants.background,
              ThemeConstants.background
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: orgAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Center(
              child: Text(
                'Failed to load organizations\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            data: (orgs) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height, // ✅ FULL HEIGHT
                  child: Center( // ✅ TRUE CENTER
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center, // ✅ CENTER VERTICALLY
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔥 TITLE
                            const Text(
                              "Select Your Organization",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 8),

                            const Text(
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
                                  gradient: isSelected
                                      ? const LinearGradient(
                                          colors: [
                                            ThemeConstants.accent,
                                            Color(0xFFE09060)
                                          ],
                                        )
                                      : null,
                                  color: isSelected
                                      ? null
                                      : ThemeConstants.surface,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.transparent
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
                                  onTap: () {
  setState(() {
    selectedOrgId = orgId;
  });

  ref.read(authStateProvider.notifier).setOrganization(
    orgId,
    org['name'] ?? 'Organization', // ✅ PASS NAME
  );

  context.go(RoutePaths.protocols);
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
                                        child: const Icon(
                                          Icons.business,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          org['name'] ?? 'Organization',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        child: isSelected
                                            ? const Icon(
                                                Icons.check_circle,
                                                color: Colors.white,
                                              )
                                            : const Icon(
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