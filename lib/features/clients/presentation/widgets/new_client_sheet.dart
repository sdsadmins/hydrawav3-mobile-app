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
  final _nickname = TextEditingController();
  final _age = TextEditingController();
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _pounds = TextEditingController();
  String? _gender;
  bool _saving = false;

  @override
  void dispose() {
    _nickname.dispose();
    _age.dispose();
    _feet.dispose();
    _inches.dispose();
    _pounds.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final age = int.tryParse(_age.text.trim());
    final feet = int.tryParse(_feet.text.trim()) ?? 0;
    final inches = int.tryParse(_inches.text.trim()) ?? 0;
    final pounds = double.tryParse(_pounds.text.trim());

    // Web parity (newpatientIntake.tsx): height entered in feet/inches and
    // weight in pounds, converted to cm/kg before the backend (which is metric).
    final height = (feet * 12 + inches) * 2.54;
    final weight = (pounds ?? 0) * 0.453592;

    if (age == null || age <= 0) {
      context.showSnackBar('Enter a valid age', isError: true);
      return;
    }
    if (height <= 0) {
      context.showSnackBar('Enter a valid height', isError: true);
      return;
    }
    if (pounds == null || pounds <= 0) {
      context.showSnackBar('Enter a valid weight (lbs)', isError: true);
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
                  // Web parity: no full-name field — the backend auto-generates
                  // the client name.
                  clientName: null,
                  nickname:
                      _nickname.text.trim().isEmpty ? null : _nickname.text.trim(),
                  gender: _gender,
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
              'New Client Intake Form',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _field('Nickname (Optional)', _nickname, hint: 'Enter nickname'),
            const SizedBox(height: 12),
            _field('Age', _age,
                hint: 'Enter age',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
            const SizedBox(height: 12),
            PickerField(
              label: 'Gender',
              value: _gender,
              placeholder: 'Select Gender',
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
            // Height in feet + inches (web parity), converted to cm on submit.
            Text(
              'Height',
              style: TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _field(null, _feet,
                      hint: '0',
                      suffixText: 'ft',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(null, _inches,
                      hint: '0',
                      suffixText: 'in',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Weight in pounds (web parity), converted to kg on submit.
            _field('Weight', _pounds,
                hint: 'Enter weight',
                suffixText: 'lbs',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
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
    String? label,
    TextEditingController controller, {
    String? hint,
    String? suffixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: TextStyle(
              color: ThemeConstants.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: ThemeConstants.textTertiary),
            // Use suffixIcon (not suffixText) so the unit stays visible even
            // when the field is empty/unfocused.
            suffixIcon: suffixText == null
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      suffixText,
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
            suffixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
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
