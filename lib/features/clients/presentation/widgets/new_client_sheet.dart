import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/extensions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../devices/presentation/widgets/plan_sheet.dart';
import '../../../devices/presentation/widgets/session_plan_widgets.dart';
import '../../../intake/presentation/widgets/option_picker.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';

/// Sheet to create a new client (`POST /clients`), in the v6 intake look
/// (`55-intake`). On success the new client is selected for the session and
/// returned. The fields are the ones the backend takes for a clinic client:
/// its name is generated server-side, and age, height and weight are required.
Future<Client?> showNewClientSheet(BuildContext context, WidgetRef ref) {
  return showPlanSheet<Client>(
    context,
    title: 'New client intake',
    subtitle: 'Age, height and weight are required',
    builder: (_) => _NewClientForm(ref: ref),
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
    final dark = PlanTones.dark(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PlanFieldLabel('Nickname', tag: 'optional'),
          PlanTextField(controller: _nickname, hint: 'What you call them'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PlanFieldLabel('Age'),
                    PlanTextField(
                      controller: _age,
                      hint: 'Enter age',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PlanFieldLabel('Gender'),
                    PlanPress(
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
                      scale: .98,
                      child: PlanSelectBox(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _gender ?? 'Select',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _gender == null
                                      ? PlanTones.sub(context)
                                      : (dark
                                          ? const Color(0xFFF1E4D6)
                                          : const Color(0xFF1A1A1A)),
                                ),
                              ),
                            ),
                            Icon(Icons.expand_more_rounded,
                                size: 20, color: PlanTones.sub(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Height in feet + inches (web parity), converted to cm on submit.
          const PlanFieldLabel('Height'),
          Row(
            children: [
              Expanded(
                child: PlanTextField(
                  controller: _feet,
                  hint: '0',
                  unit: 'ft',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PlanTextField(
                  controller: _inches,
                  hint: '0',
                  unit: 'in',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Weight in pounds (web parity), converted to kg on submit.
          const PlanFieldLabel('Weight'),
          PlanTextField(
            controller: _pounds,
            hint: 'Enter weight',
            unit: 'lbs',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 20),
          PlanPrimaryButton(
            label: 'Create client',
            busy: _saving,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}
