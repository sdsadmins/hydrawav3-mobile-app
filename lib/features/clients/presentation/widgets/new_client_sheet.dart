import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/utils/extensions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../intake/presentation/widgets/option_picker.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';

/// Bottom sheet to create a new client (`POST /clients`). On success the new
/// client is selected for the session and returned.
Future<Client?> showNewClientSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<Client>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _NewClientForm(ref: ref),
    ),
  );
}

class _NewClientForm extends StatefulWidget {
  final WidgetRef ref;
  const _NewClientForm({required this.ref});

  @override
  State<_NewClientForm> createState() => _NewClientFormState();
}

class _NewClientFormState extends State<_NewClientForm> {
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _phone = TextEditingController();
  String? _gender;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final age = int.tryParse(_age.text.trim());
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());

    if (age == null || age <= 0) {
      context.showSnackBar('Enter a valid age', isError: true);
      return;
    }
    if (height == null || height <= 0) {
      context.showSnackBar('Enter a valid height (cm)', isError: true);
      return;
    }
    if (weight == null || weight <= 0) {
      context.showSnackBar('Enter a valid weight (kg)', isError: true);
      return;
    }

    final auth = widget.ref.read(authStateProvider);
    final orgId = int.tryParse(auth.selectedOrgId ?? '');
    if (orgId == null) {
      context.showSnackBar('Select an organization first', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final created =
          await widget.ref.read(clientRepositoryProvider).create(
                CreateClientRequest(
                  age: age,
                  height: height,
                  weight: weight,
                  organizationId: orgId,
                  organizationName: auth.selectedOrgName ?? '',
                  clientName: _name.text.trim().isEmpty ? null : _name.text.trim(),
                  nickname:
                      _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
                  gender: _gender,
                  phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                ),
              );
      // Select the new client and refresh the list.
      widget.ref.read(selectedClientProvider.notifier).state = created;
      widget.ref.read(sessionClientModeProvider.notifier).state =
          ClientMode.client;
      widget.ref.invalidate(clientListProvider);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        context.showSnackBar('Failed to create client: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Client',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _field('Full name', _name, hint: 'Optional — auto-generated if blank'),
            const SizedBox(height: 12),
            _field('Nickname', _nickname, hint: 'Optional'),
            const SizedBox(height: 12),
            _field('Age', _age,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 12),
            PickerField(
              label: 'Gender',
              value: _gender,
              placeholder: 'Select gender',
              onTap: () async {
                final picked = await showOptionPicker<String>(
                  context,
                  title: 'Gender',
                  options: const ['Male', 'Female', 'Other'],
                  labelOf: (v) => v,
                  selected: _gender,
                );
                if (picked != null) setState(() => _gender = picked);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field('Height (cm)', _height,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field('Weight (kg)', _weight,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field('Phone', _phone,
                hint: 'Optional', keyboardType: TextInputType.phone),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Client'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: ThemeConstants.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ThemeConstants.textTertiary),
            filled: true,
            fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ThemeConstants.accent),
            ),
          ),
        ),
      ],
    );
  }
}
