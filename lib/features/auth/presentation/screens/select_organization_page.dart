import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/network/dio_client.dart';
import '../../../payments/data/payment_repository.dart';
import '../../data/organization_repository.dart';
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

  // ── Create-organization (empty state) ──────────────────────────────────────
  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  final _nameCtrl = TextEditingController();
  final _mailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isCreating = false;
  String? _formError;

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.refresh(organizationProvider);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mailCtrl.dispose();
    _addressCtrl.dispose();
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: orgs.isEmpty
                            ? _buildCreateOrg()
                            : _buildOrgList(orgs),
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

  /// The organization picker (2+ orgs, or 1 after creation).
  Widget _buildOrgList(List<Map<String, dynamic>> orgs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
                  ? ThemeConstants.accent.withValues(alpha: 0.14)
                  : ThemeConstants.surface,
              border: Border.all(
                color: isSelected
                    ? ThemeConstants.accent
                    : ThemeConstants.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? ThemeConstants.accent.withValues(alpha: 0.3)
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
                      org['name'] ?? 'Organization', // ✅ PASS NAME
                    );

                // Provision the org's free plan + starter tokens (web parity)
                // so the token balance shows for first-time / newly onboarded
                // accounts. Best-effort — never blocks nav.
                await ref
                    .read(paymentRepositoryProvider)
                    .ensureFreePlan(orgId);

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
                      color: Colors.white.withValues(alpha: 0.1),
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
                    duration: const Duration(milliseconds: 300),
                    child: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: ThemeConstants.textPrimary,
                          )
                        : Icon(
                            Icons.arrow_forward_ios,
                            color: ThemeConstants.textTertiary,
                            size: 16,
                          ),
                  )
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Empty state: no organizations yet → inline "Create Your Organization" form
  /// (web parity with `selectOrganizationPage.tsx`).
  Widget _buildCreateOrg() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Create Your Organization",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: ThemeConstants.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "You don't have any organizations yet.\nCreate one to get started.",
          style: TextStyle(
            fontSize: 13,
            color: ThemeConstants.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ThemeConstants.surface,
            border: Border.all(color: ThemeConstants.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(
                controller: _nameCtrl,
                label: 'Organization Name *',
                hint: 'Acme Wellness',
              ),
              _field(
                controller: _mailCtrl,
                label: 'Email *',
                hint: 'org@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              _field(
                controller: _addressCtrl,
                label: 'Address *',
                hint: '123 Main St',
              ),
              _field(
                controller: _ageCtrl,
                label: 'Age',
                hint: 'Optional',
                keyboardType: TextInputType.number,
              ),
              _field(
                controller: _phoneCtrl,
                label: 'Phone Number *',
                hint: '+1 555 000 0000',
                keyboardType: TextInputType.phone,
              ),
              if (_formError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isCreating ? null : _handleCreate,
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create Organization',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ThemeConstants.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: !_isCreating,
            style: TextStyle(color: ThemeConstants.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: ThemeConstants.textTertiary),
              filled: true,
              fillColor: ThemeConstants.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ThemeConstants.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ThemeConstants.accent),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: ThemeConstants.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCreate() async {
    // Validate (web parity: name/mail/address/phone required, email regex; age optional).
    final name = _nameCtrl.text.trim();
    final mail = _mailCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final age = _ageCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    String? error;
    if (name.isEmpty) {
      error = 'Organization name is required.';
    } else if (mail.isEmpty) {
      error = 'Email is required.';
    } else if (!_emailRe.hasMatch(mail)) {
      error = 'Enter a valid email address.';
    } else if (address.isEmpty) {
      error = 'Address is required.';
    } else if (phone.isEmpty) {
      error = 'Phone number is required.';
    }
    if (error != null) {
      setState(() => _formError = error);
      return;
    }

    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null || userId.isEmpty) {
      setState(() => _formError =
          'Could not identify your account. Please sign in again.');
      return;
    }

    setState(() {
      _formError = null;
      _isCreating = true;
    });

    try {
      final orgId =
          await ref.read(organizationRepositoryProvider).createAndLinkOrganization(
        userId: userId,
        orgBody: {
          'name': name,
          'mail': mail,
          'address': address,
          'age': age,
          'phone': phone,
        },
      );

      // Auto-select the just-created org and enter the app (releases the router
      // gate, which requires a selected org). Same tail as the select onTap.
      await ref.read(authStateProvider.notifier).setOrganization(orgId, name);
      await ref.read(paymentRepositoryProvider).ensureFreePlan(orgId);

      if (!mounted) return;
      context.go(RoutePaths.protocols);
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _formError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _formError = 'Something went wrong. Please try again.';
      });
    }
  }
}
