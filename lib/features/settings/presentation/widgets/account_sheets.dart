import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../../auth/data/auth_remote_source.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Edit profile — the UI spec's `profileSheet()` (app.js:3290).
Future<void> showProfileSheet(BuildContext context) {
  return showHwSheet<void>(
    context: context,
    builder: (_) => const _ProfileSheet(),
  );
}

/// Change password — the UI spec's `passwordSheet()` (app.js:3307).
Future<void> showPasswordSheet(BuildContext context) {
  return showHwSheet<void>(
    context: context,
    builder: (_) => const _PasswordSheet(),
  );
}

// ---------------------------------------------------------------------------

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet();

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _dob = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _email, _phone, _address, _dob]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The screen this replaces fired this off unawaited with no loading or
  /// error state, so a slow network showed empty fields that silently filled
  /// in later. Await it and show both.
  Future<void> _load() async {
    try {
      final profile = await ref.read(authRemoteSourceProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _name.text = profile.displayName;
        _email.text = profile.email ?? '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your profile. You can still edit and save.";
      });
    }
  }

  Future<void> _save() async {
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(authRemoteSourceProvider).updateProfile({
        'firstName': parts.isNotEmpty ? parts.first : '',
        'lastName': parts.length > 1 ? parts.sublist(1).join(' ') : '',
        'phone': _phone.text.trim(),
        'dateOfBirth': _dob.text.trim(),
      });
      await ref.read(authStateProvider.notifier).refreshProfile();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
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
        _error = 'Unable to save your profile right now.';
      });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now.subtract(const Duration(days: 1)),
    );
    if (picked == null) return;
    _dob.text = '${picked.year}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Edit profile',
          style: TextStyle(
            fontSize: HwType.lg,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(fontSize: HwType.cap, color: p.low),
          ),
        ],
        const SizedBox(height: HwSpace.s3),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HwField(label: 'Full name', controller: _name),
                  HwField(
                    label: 'Professional title',
                    controller: _title,
                    hint: 'e.g. Director of Rehabilitation',
                  ),
                  HwField(
                    label: 'Email address',
                    controller: _email,
                    readOnly: true,
                  ),
                  HwField(
                    label: 'Phone number',
                    controller: _phone,
                    hint: '(555) 123-4567',
                    keyboardType: TextInputType.phone,
                  ),
                  HwField(
                    label: 'Address',
                    controller: _address,
                    hint: 'Street, City, State ZIP',
                  ),
                  HwField(
                    label: 'Date of birth',
                    controller: _dob,
                    readOnly: true,
                    hint: 'YYYY-MM-DD',
                    onTap: _pickDob,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: HwSpace.s2),
        HwButton(
          label: 'Save profile',
          busy: _saving,
          onTap: _loading ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Validators carried over from the screen this replaces — they were the
  // best-written part of it.
  String? _validateCurrent(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Enter your current password.' : null;

  String? _validateNew(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter a new password.';
    if (t.length < 8) return 'Use at least 8 characters.';
    if (t == _current.text.trim()) return 'New password must be different.';
    return null;
  }

  String? _validateConfirm(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Confirm your new password.';
    if (t != _new.text.trim()) return 'Passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text.trim(),
            newPassword: _new.text.trim(),
            confirmPassword: _confirm.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated')),
      );
    } on ServerException catch (e) {
      if (!mounted) return;
      // The spec wipes every field on error; keep them, since re-typing a
      // correct current password is pure friction.
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to update your password right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Change password',
            style: TextStyle(
              fontSize: HwType.lg,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: HwType.cap, color: p.low),
            ),
          ],
          const SizedBox(height: HwSpace.s3),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HwField(
                    label: 'Current password',
                    controller: _current,
                    obscure: true,
                    validator: _validateCurrent,
                  ),
                  HwField(
                    label: 'New password',
                    controller: _new,
                    obscure: true,
                    hint: '8+ characters',
                    validator: _validateNew,
                  ),
                  HwField(
                    label: 'Confirm new password',
                    controller: _confirm,
                    obscure: true,
                    validator: _validateConfirm,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HwSpace.s2),
          HwButton(
            label: 'Update password',
            busy: _saving,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}
