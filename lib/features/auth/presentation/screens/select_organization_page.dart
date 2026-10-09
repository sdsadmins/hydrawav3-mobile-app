import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/network/dio_client.dart';
import '../../../payments/data/payment_repository.dart';
import '../../data/organization_repository.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_ui.dart';

/// Every organization the signed-in practitioner belongs to. Shared by this
/// page and the More screen's org switcher — there is exactly one declaration.
///
/// The endpoint has returned both a bare list and a paginated envelope across
/// backend versions, so normalize both shapes rather than assuming one.
final organizationProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.read(djangoDioProvider);
  final response = await dio.get('/admin/organizations');
  final data = response.data;

  List<dynamic>? rows;
  if (data is List) {
    rows = data;
  } else if (data is Map<String, dynamic>) {
    rows = (data['results'] ?? data['data']) as List<dynamic>?;
    // A single org can come back unwrapped.
    rows ??= [data];
  }
  if (rows == null) {
    throw Exception('Unexpected organizations response: ${data.runtimeType}');
  }
  return rows
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
});

class SelectOrganizationPage extends ConsumerStatefulWidget {
  /// Show the create-organization form even when the practitioner already
  /// belongs to one. Set by `/select-organization?create=1`, which is where
  /// the Hub's "Add organization" action lands — without it that action would
  /// dead-end on the picker.
  final bool startInCreateMode;

  const SelectOrganizationPage({super.key, this.startInCreateMode = false});

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
    final p = RefPalette.of(context);

    return orgAsync.when(
      loading: () => Scaffold(
        backgroundColor: p.bg,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(p.copper),
          ),
        ),
      ),
      error: (e, _) => AuthPage(
        child: Column(
          children: [
            const AuthHeading('Select organization'),
            const SizedBox(height: 14),
            Text(
              'Failed to load organizations\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.ink2, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            AuthOutlineButton(
              label: 'Retry',
              onTap: () => ref.invalidate(organizationProvider),
            ),
          ],
        ),
      ),
      data: (orgs) => AuthPage(
        child: orgs.isEmpty || widget.startInCreateMode
            ? _buildCreateOrg()
            : _buildOrgList(orgs),
      ),
    );
  }

  /// The organization picker (2+ orgs, or 1 after creation) — v6
  /// `renderOrgSelect`: spaced heading, one card per organization.
  Widget _buildOrgList(List<Map<String, dynamic>> orgs) {
    final p = RefPalette.of(context);
    final name = (ref.watch(authStateProvider).user?.displayName ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeading(
          'Select organization',
          subtitle: '${name.isEmpty ? 'One login' : '$name — one login'}, all '
              "your organizations. Pick where you're working today.",
        ),
        const SizedBox(height: 26),
        ...orgs.map((org) {
          final orgId = org['id'].toString();
          final isSelected = selectedOrgId == orgId;
          final detail = [
            for (final k in ['description', 'address'])
              if ((org[k]?.toString().trim() ?? '').isNotEmpty)
                org[k].toString().trim(),
          ];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  setState(() {
                    selectedOrgId = orgId;
                  });

                  await ref.read(authStateProvider.notifier).setOrganization(
                        orgId,
                        org['name'] ?? 'Organization', // ✅ PASS NAME
                      );

                  // Provision the org's free plan + starter tokens (web
                  // parity) so the token balance shows for first-time /
                  // newly onboarded accounts. Best-effort — never
                  // blocks nav.
                  await ref
                      .read(paymentRepositoryProvider)
                      .ensureFreePlan(orgId);

                  if (mounted) {
                    context.go(RoutePaths.devices);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? p.copper : p.cardline,
                      width: isSelected ? 1.6 : 1,
                    ),
                    boxShadow: p.shadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: p.sunGrad,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.apartment_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              org['name'] ?? 'Organization',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            if (detail.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                detail.join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: p.ink3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: isSelected
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(p.copper),
                                ),
                              )
                            : Icon(Icons.chevron_right_rounded,
                                color: p.ink3, size: 24),
                      ),
                    ],
                  ),
                ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeading(
          'Create your organization',
          subtitle: "You don't have any organizations yet. "
              'Create one to get started.',
        ),
        const SizedBox(height: 22),
        AuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _nameCtrl,
                label: 'Organization name',
                required: true,
                hint: 'Acme Wellness',
              ),
              _field(
                controller: _mailCtrl,
                label: 'Email',
                required: true,
                hint: 'org@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              _field(
                controller: _addressCtrl,
                label: 'Address',
                required: true,
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
                label: 'Phone number',
                required: true,
                hint: '+1 555 000 0000',
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 8),
          AuthError(_formError!),
        ],
        const SizedBox(height: 16),
        AuthPrimaryButton(
          label: 'Create organization',
          busy: _isCreating,
          onTap: _handleCreate,
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool required = false,
    String? hint,
    TextInputType? keyboardType,
  }) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthLabel(label, required: required),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            enabled: !_isCreating,
            style: TextStyle(color: p.ink, fontSize: 15),
            decoration: authInputDecoration(context, hint: hint),
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
      final orgId = await ref
          .read(organizationRepositoryProvider)
          .createAndLinkOrganization(
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
      context.go(RoutePaths.devices);
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
