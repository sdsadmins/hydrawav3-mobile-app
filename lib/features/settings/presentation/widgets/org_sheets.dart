import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_icon.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/data/organization_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import '../../../payments/data/payment_repository.dart';

/// Add organization — the UI spec's `editOrgSheet(null)` (`app.js:2026`).
///
/// The More screen used to send this to `/select-organization?create=1`, a full
/// page built for the *login gate*. The spec puts it in a sheet, in place, so
/// adding a second organization never looks like being signed out.
///
/// Returns true when an organization was created.
Future<bool?> showAddOrganizationSheet(BuildContext context) {
  return showHwSheet<bool>(
    context: context,
    builder: (_) => const _AddOrganizationSheet(),
  );
}

class _AddOrganizationSheet extends ConsumerStatefulWidget {
  const _AddOrganizationSheet();

  @override
  ConsumerState<_AddOrganizationSheet> createState() =>
      _AddOrganizationSheetState();
}

class _AddOrganizationSheetState extends ConsumerState<_AddOrganizationSheet> {
  // Field order follows the spec sheet exactly.
  final _name = TextEditingController();
  final _type = TextEditingController();
  final _years = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  final _nameFocus = FocusNode();

  bool _saving = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    // The spec focuses the name field 80ms after the sheet opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _nameFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _years.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _title.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Add organization',
          style: TextStyle(
            fontSize: HwType.lg,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'One login, many organizations. You can switch between them any time.',
          style: TextStyle(fontSize: HwType.cap, height: 1.45, color: p.ink2),
        ),
        if (_error != null) ...[
          const SizedBox(height: HwSpace.s2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: p.lowSoft,
              borderRadius: BorderRadius.circular(HwRadius.sm),
            ),
            child: Text(
              _error!,
              style: TextStyle(fontSize: HwType.cap, height: 1.4, color: p.low),
            ),
          ),
        ],
        const SizedBox(height: HwSpace.s3),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                HwField(
                  label: 'Organization / business name',
                  controller: _name,
                  hint: 'e.g. Miami Dolphins',
                ),
                HwField(
                  label: 'Type of organization',
                  controller: _type,
                  hint: 'e.g. NFL team · private practice · university',
                ),
                // The spec's `.grid2` — two short fields sharing a row.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: HwField(
                        label: 'Years operating',
                        controller: _years,
                        hint: 'e.g. 12',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: HwSpace.s3),
                    Expanded(
                      child: HwField(
                        label: 'Contact number',
                        controller: _phone,
                        hint: '(555) 123-4567',
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                // NOT in the spec sheet, but the create endpoint requires
                // `mail` — the spec is a click-through prototype with no
                // backend. Placed next to the phone number so the two contact
                // details read together.
                HwField(
                  label: 'Business email',
                  controller: _email,
                  hint: 'e.g. front-desk@yourclinic.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                HwField(
                  label: 'Business address',
                  controller: _address,
                  hint: 'Street, City, State ZIP',
                ),
                HwField(
                  label: 'Your role / title here',
                  controller: _title,
                  hint: 'e.g. Director of Rehabilitation',
                ),
                HwField(
                  label: 'Other details',
                  controller: _notes,
                  hint: 'Anything else relevant',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: HwSpace.s2),
        HwButton(
          label: 'Create organization',
          busy: _saving,
          onTap: _saving ? null : _save,
        ),
        HwSkipLink(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final address = _address.text.trim();
    final phone = _phone.text.trim();

    // Same rules the org-selection page enforces, so a business created here
    // and one created at the login gate are validated identically.
    String? error;
    if (name.isEmpty) {
      error = 'Organization name is required.';
    } else if (email.isEmpty) {
      error = 'Business email is required.';
    } else if (!_emailRe.hasMatch(email)) {
      error = 'Enter a valid email address.';
    } else if (address.isEmpty) {
      error = 'Business address is required.';
    } else if (phone.isEmpty) {
      error = 'Contact number is required.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null || userId.isEmpty) {
      setState(() =>
          _error = 'Could not identify your account. Please sign in again.');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      final orgId =
          await ref.read(organizationRepositoryProvider).createAndLinkOrganization(
        userId: userId,
        orgBody: {
          'name': name,
          'mail': email,
          'address': address,
          // `age` is the API's name for how long the business has been running.
          'age': _years.text.trim(),
          'phone': phone,
        },
      );

      // Every new org starts on the free plan, exactly as the login-gate path
      // does — otherwise the first session hits an org with no plan at all.
      await ref.read(paymentRepositoryProvider).ensureFreePlan(orgId);
      ref.invalidate(organizationProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name created')),
      );
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }
}

/// The spec's copper ghost "Add organization" button (`app.js:1908`).
class AddOrganizationButton extends StatelessWidget {
  final VoidCallback onTap;
  const AddOrganizationButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return HwPress(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(HwRadius.sm),
          border: Border.all(color: p.copper, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HwIcon(HwIcons.building, size: 15, color: p.copperInk),
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
    );
  }
}
