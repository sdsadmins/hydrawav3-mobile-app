import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../domain/onboarding_models.dart';
import '../providers/onboarding_provider.dart';

/// Native multi-step "Create account" onboarding (parity with the web's
/// 4-step practitioner onboarding). Theme-aware (light + dark): cards, labeled
/// fields with required asterisks, modern spacing.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = [
    (icon: Icons.person_rounded, label: 'Practitioner'),
    (icon: Icons.workspace_premium_rounded, label: 'Credentials'),
    (icon: Icons.business_rounded, label: 'Business'),
    (icon: Icons.fact_check_rounded, label: 'Review'),
  ];

  // Step 1.
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();
  final _country = TextEditingController();
  bool _obscurePassword = true;

  // Step 2 — certification draft.
  final _certName = TextEditingController();
  final _certOrg = TextEditingController();
  String? _certIssueDate;
  String? _certExpDate;
  PlatformFile? _certDoc;

  // Step 3 — business draft.
  final _bizName = TextEditingController();
  final _bizEmail = TextEditingController();
  final _bizContact = TextEditingController();
  final _bizAddress = TextEditingController();
  String? _bizAge;

  @override
  void dispose() {
    for (final c in [
      _firstName, _lastName, _username, _password, _email, _phone, _title,
      _address, _city, _state, _zip, _country, _certName, _certOrg,
      _bizName, _bizEmail, _bizContact, _bizAddress,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  PractitionerForm _buildForm() => PractitionerForm(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        title: _title.text.trim(),
        address: _address.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        zip: _zip.text.trim(),
        country: _country.text.trim(),
      );

  void _onPrimary() {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final step = ref.read(onboardingControllerProvider).currentStep;
    switch (step) {
      case 0:
        if (controller.validateStep1(_buildForm())) {
          controller.next();
        } else {
          _snack('Please complete the required fields.', error: true);
        }
        break;
      case 1:
        controller.next();
        break;
      case 2:
        if (ref.read(onboardingControllerProvider).businesses.isEmpty) {
          _snack('Add at least one business to continue.', error: true);
        } else {
          controller.next();
        }
        break;
      case 3:
        controller.submit();
        break;
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? ThemeConstants.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);

    ref.listen(onboardingControllerProvider.select((s) => s.error), (_, err) {
      if (err != null && err.isNotEmpty) _snack(err, error: true);
    });

    if (state.submitted) return _SuccessView();

    final isLast = state.currentStep == 3;
    final canSubmit = !isLast || state.euaAccepted;

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.background,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 74,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (state.currentStep > 0) {
              ref.read(onboardingControllerProvider.notifier).back();
            } else {
              context.pop();
            }
          },
        ),
        // Logo centered in the app bar, sized to roughly match the
        // "Welcome to Hydrawav3" heading (SVG has built-in vertical padding).
        title: const _OnboardingLogo(height: 56),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Everything below the app bar scrolls together (hero + stepper +
            // form); only the bottom action bar stays fixed.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                      child: _heroHeader(),
                    ),
                    _stepper(state.currentStep),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position:
                              Tween(begin: const Offset(0.05, 0), end: Offset.zero)
                                  .animate(anim),
                          child: child,
                        ),
                      ),
                      child: Padding(
                        key: ValueKey(state.currentStep),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: _stepBody(state),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _bottomBar(state, isLast, canSubmit),
          ],
        ),
      ),
    );
  }

  // ── Hero header (step 1) ────────────────────────────────────────────────────
  Widget _heroHeader() {
    return Column(
      children: [
        // Sparkles badge pill.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: ThemeConstants.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: ThemeConstants.accent.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 14, color: ThemeConstants.accent),
              const SizedBox(width: 7),
              Text('PRACTITIONER ONBOARDING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: ThemeConstants.accent,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // "Welcome to Hydrawav3" on one line (Hydrawav3 in the accent gradient).
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome to ',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: ThemeConstants.textPrimary,
                  )),
              ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  colors: [ThemeConstants.accent, const Color(0xFFA55A3B)],
                ).createShader(rect),
                child: const Text('Hydrawav3',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Share your details so we can tailor the workspace to your practice.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: ThemeConstants.textSecondary,
          ),
        ),
      ],
    );
  }

  // ── Stepper ─────────────────────────────────────────────────────────────────
  Widget _stepper(int current) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(child: _stepItem(i, current)),
            if (i < _steps.length - 1)
              Container(
                width: 18,
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i < current
                    ? ThemeConstants.accent
                    : ThemeConstants.border,
              ),
          ],
        ],
      ),
    );
  }

  Widget _stepItem(int index, int current) {
    final done = index < current;
    final active = index == current;
    final on = done || active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: on ? ThemeConstants.accent : ThemeConstants.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? ThemeConstants.accent : ThemeConstants.border,
              width: 2,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ThemeConstants.accent.withValues(alpha: 0.30),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            done ? Icons.check_rounded : _steps[index].icon,
            size: 18,
            color: on ? ThemeConstants.onAccent : ThemeConstants.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _steps[index].label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active
                ? ThemeConstants.textPrimary
                : ThemeConstants.textTertiary,
          ),
        ),
      ],
    );
  }

  // ── Step bodies ─────────────────────────────────────────────────────────────
  Widget _stepBody(OnboardingState s) {
    switch (s.currentStep) {
      case 0:
        return _step1(s);
      case 1:
        return _step2(s);
      case 2:
        return _step3(s);
      default:
        return _step4(s);
    }
  }

  Widget _step1(OnboardingState s) {
    return _StepShell(
      icon: Icons.person_rounded,
      title: 'Practitioner Information',
      subtitle: 'All fields are required.',
      children: [
        _field(_firstName, 'First Name',
            req: true, hint: 'Jane', err: s.step1Errors['firstName']),
        _field(_lastName, 'Last Name',
            req: true, hint: 'Doe', err: s.step1Errors['lastName']),
        _field(_username, 'Username',
            req: true, hint: 'janedoe', err: s.step1Errors['username']),
        _field(_password, 'Password (Must Be 8 Characters)',
            req: true,
            hint: '••••••••',
            obscure: _obscurePassword,
            err: s.step1Errors['password'],
            suffix: IconButton(
              icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: ThemeConstants.textTertiary),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            )),
        _field(_email, 'Email',
            req: true,
            hint: 'you@example.com',
            keyboard: TextInputType.emailAddress,
            err: s.step1Errors['email']),
        _field(_phone, 'Phone',
            req: true,
            hint: '(555) 123-4567',
            keyboard: TextInputType.phone,
            err: s.step1Errors['phone']),
        _field(_title, 'Title',
            req: true,
            hint: 'e.g. Physiotherapist',
            err: s.step1Errors['title']),
        _field(_address, 'Address',
            req: true, hint: '123 Main St', err: s.step1Errors['address']),
        Row(children: [
          Expanded(
              child: _field(_city, 'City',
                  req: true, hint: 'Los Angeles', err: s.step1Errors['city'])),
          const SizedBox(width: 12),
          Expanded(
              child: _field(_state, 'State',
                  req: true, hint: 'California', err: s.step1Errors['state'])),
        ]),
        Row(children: [
          Expanded(
              child: _field(_zip, 'ZIP',
                  req: true,
                  hint: '90001',
                  keyboard: TextInputType.number,
                  err: s.step1Errors['zip'])),
          const SizedBox(width: 12),
          Expanded(
              child: _field(_country, 'Country',
                  req: true, hint: 'USA', err: s.step1Errors['country'])),
        ]),
      ],
    );
  }

  Widget _step2(OnboardingState s) {
    return _StepShell(
      icon: Icons.workspace_premium_rounded,
      title: 'Credentials / Licenses',
      subtitle: 'This step is optional — you can add these later.',
      children: [
        _field(_certName, 'Certification Name', hint: 'State License'),
        _field(_certOrg, 'Issuing Organization', hint: 'State Medical Board'),
        Row(children: [
          Expanded(
              child: _dateField('Issue Date', _certIssueDate,
                  (v) => setState(() => _certIssueDate = v))),
          const SizedBox(width: 12),
          Expanded(
              child: _dateField('Expiration Date', _certExpDate,
                  (v) => setState(() => _certExpDate = v))),
        ]),
        const SizedBox(height: 4),
        _filePickTile(
          label: _certDoc?.name ?? 'Upload Certification Document',
          hasFile: _certDoc != null,
          onTap: () async {
            final file = await ref
                .read(onboardingControllerProvider.notifier)
                .pickCertificationDocument();
            if (file != null) setState(() => _certDoc = file);
          },
          onClear:
              _certDoc == null ? null : () => setState(() => _certDoc = null),
        ),
        const SizedBox(height: 14),
        HwButton(
          label: 'Add Certification',
          isOutlined: true,
          icon: Icons.add_rounded,
          width: double.infinity,
          height: 46,
          onPressed: () {
            if (_certName.text.trim().isEmpty) {
              _snack('Enter a certification name first.', error: true);
              return;
            }
            ref.read(onboardingControllerProvider.notifier).addCertification(
                  OnboardingCertification(
                    name: _certName.text.trim(),
                    issuingOrganization: _certOrg.text.trim(),
                    issueDate: _certIssueDate ?? '',
                    expirationDate: _certExpDate ?? '',
                    documentPath: _certDoc?.path,
                    documentName: _certDoc?.name,
                  ),
                );
            _certName.clear();
            _certOrg.clear();
            setState(() {
              _certIssueDate = null;
              _certExpDate = null;
              _certDoc = null;
            });
          },
        ),
        if (s.certifications.isNotEmpty) ...[
          const SizedBox(height: 18),
          _addedHeader('Uploaded Certifications', s.certifications.length),
          ...s.certifications.asMap().entries.map((e) => _addedTile(
                icon: Icons.workspace_premium_outlined,
                title: e.value.name,
                subtitle: [
                  if (e.value.issuingOrganization.isNotEmpty)
                    e.value.issuingOrganization,
                  if (e.value.documentName != null)
                    '📎 ${e.value.documentName}',
                ].join('  ·  '),
                onRemove: () => ref
                    .read(onboardingControllerProvider.notifier)
                    .removeCertification(e.key),
              )),
        ],
      ],
    );
  }

  Widget _step3(OnboardingState s) {
    return _StepShell(
      icon: Icons.business_rounded,
      title: 'Business Information',
      subtitle: 'Add at least one business to continue.',
      children: [
        _field(_bizName, 'Name', hint: 'Hydrawa Clinic'),
        _dropdownField('Business Age', _bizAge, businessAgeOptions,
            (v) => setState(() => _bizAge = v)),
        _field(_bizEmail, 'Email Address',
            hint: 'clinic@example.com', keyboard: TextInputType.emailAddress),
        _field(_bizContact, 'Contact Number',
            hint: '(555) 765-4321', keyboard: TextInputType.phone),
        _field(_bizAddress, 'Address (street, city, state, zip)',
            hint: '456 Clinic Ave, Los Angeles, CA, 90001'),
        const SizedBox(height: 4),
        _filePickTile(
          label: s.businessLogoName ?? 'Business Logo (Optional)',
          hasFile: s.hasBusinessLogo,
          onTap: () => ref
              .read(onboardingControllerProvider.notifier)
              .pickBusinessLogo(),
          onClear: s.hasBusinessLogo
              ? () => ref
                  .read(onboardingControllerProvider.notifier)
                  .clearBusinessLogo()
              : null,
        ),
        const SizedBox(height: 14),
        HwButton(
          label: 'Save Business',
          isOutlined: true,
          icon: Icons.add_rounded,
          width: double.infinity,
          height: 46,
          onPressed: _addBusiness,
        ),
        if (s.businesses.isNotEmpty) ...[
          const SizedBox(height: 18),
          _addedHeader('Businesses Linked', s.businesses.length),
          ...s.businesses.asMap().entries.map((e) => _addedTile(
                icon: Icons.storefront_rounded,
                title: e.value.name,
                subtitle: [
                  if (e.value.businessAge.isNotEmpty) e.value.businessAge,
                  if (e.value.email.isNotEmpty) e.value.email,
                ].join('  ·  '),
                onRemove: () => ref
                    .read(onboardingControllerProvider.notifier)
                    .removeBusiness(e.key),
              )),
        ],
      ],
    );
  }

  void _addBusiness() {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final name = _bizName.text.trim();
    final email = _bizEmail.text.trim();
    final contact = _bizContact.text.trim();
    final address = _bizAddress.text.trim();
    if (name.isEmpty ||
        _bizAge == null ||
        email.isEmpty ||
        contact.isEmpty ||
        address.isEmpty) {
      _snack('Please fill in all business fields.', error: true);
      return;
    }
    if (!controller.isValidEmail(email)) {
      _snack('Enter a valid business email.', error: true);
      return;
    }
    controller.addBusiness(OnboardingBusiness(
      name: name,
      businessAge: _bizAge!,
      email: email,
      contactNumber: contact,
      address: address,
    ));
    _bizName.clear();
    _bizEmail.clear();
    _bizContact.clear();
    _bizAddress.clear();
    setState(() => _bizAge = null);
  }

  Widget _step4(OnboardingState s) {
    return _StepShell(
      icon: Icons.fact_check_rounded,
      title: 'Review & Submit',
      subtitle: 'Confirm your details and accept the agreement.',
      children: [
        _reviewRow(Icons.person_rounded, 'Practitioner',
            s.form.fullName.isEmpty ? '—' : s.form.fullName, s.form.email),
        _divider(),
        _reviewRow(Icons.workspace_premium_outlined, 'Licenses',
            '${s.certifications.length} added', null),
        _divider(),
        _reviewRow(Icons.storefront_rounded, 'Businesses',
            '${s.businesses.length} linked', null),
        const SizedBox(height: 18),
        InkWell(
          onTap: () => _launch('https://www.hydrawav3.com/privacy'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.description_outlined,
                  size: 18, color: ThemeConstants.accent),
              const SizedBox(width: 8),
              Text('Read the End User Agreement',
                  style: TextStyle(
                      color: ThemeConstants.accent,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => ref
              .read(onboardingControllerProvider.notifier)
              .setEua(!s.euaAccepted),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: s.euaAccepted,
                activeColor: ThemeConstants.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => ref
                    .read(onboardingControllerProvider.notifier)
                    .setEua(v ?? false),
              ),
              Expanded(
                child: Text(
                  'I have read and agree to the Hydrawav3 End User Agreement.',
                  style: TextStyle(
                      fontSize: 13, color: ThemeConstants.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: ThemeConstants.borderLight),
      );

  Widget _reviewRow(IconData icon, String label, String value, String? sub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: ThemeConstants.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: ThemeConstants.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: ThemeConstants.textTertiary)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ThemeConstants.textPrimary)),
              if (sub != null && sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: ThemeConstants.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Reusable field with external label + required asterisk (modern) ─────────
  Widget _field(
    TextEditingController c,
    String label, {
    bool req = false,
    String? hint,
    String? err,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, req),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: keyboard,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
            decoration: _inputDecoration(hint: hint, error: err, suffix: suffix),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, bool req) {
    return RichText(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ThemeConstants.textSecondary,
        ),
        children: [
          if (req)
            TextSpan(
              text: ' *',
              style: TextStyle(
                  color: ThemeConstants.error, fontWeight: FontWeight.w800),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, String? error, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1.4]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: ThemeConstants.textTertiary, fontSize: 14),
      errorText: error,
      isDense: true,
      filled: true,
      fillColor: ThemeConstants.surfaceVariant.withValues(alpha: 0.45),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffix,
      enabledBorder: border(ThemeConstants.border),
      focusedBorder: border(ThemeConstants.accent, 1.6),
      errorBorder: border(ThemeConstants.error),
      focusedErrorBorder: border(ThemeConstants.error, 1.6),
    );
  }

  Widget _dropdownField(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged, {
    bool req = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, req),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: value,
            isDense: true,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: ThemeConstants.textTertiary),
            dropdownColor: ThemeConstants.surface,
            style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
            decoration: _inputDecoration(hint: '-- Select --'),
            items: options
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, String? value, ValueChanged<String> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, false),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(now.year - 60),
              lastDate: DateTime(now.year + 60),
            );
            if (picked != null) {
              String two(int n) => n.toString().padLeft(2, '0');
              onPicked('${picked.year}-${two(picked.month)}-${two(picked.day)}');
            }
          },
          child: InputDecorator(
            decoration: _inputDecoration(),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 15, color: ThemeConstants.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(value ?? 'Select',
                      style: TextStyle(
                          fontSize: 14,
                          color: value == null
                              ? ThemeConstants.textTertiary
                              : ThemeConstants.textPrimary)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _filePickTile({
    required String label,
    required bool hasFile,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: ThemeConstants.surfaceVariant.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile ? ThemeConstants.accent : ThemeConstants.border,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Icon(hasFile ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                size: 18,
                color: hasFile
                    ? ThemeConstants.accent
                    : ThemeConstants.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeConstants.textPrimary)),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded,
                    size: 18, color: ThemeConstants.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addedHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.textPrimary)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: ThemeConstants.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.accent)),
        ),
      ]),
    );
  }

  Widget _addedTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: ThemeConstants.surfaceVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeConstants.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ThemeConstants.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ThemeConstants.textPrimary)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: ThemeConstants.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: ThemeConstants.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(OnboardingState s, bool isLast, bool canSubmit) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        border: Border(top: BorderSide(color: ThemeConstants.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (s.currentStep > 0) ...[
              Expanded(
                child: HwButton(
                  label: 'Back',
                  isOutlined: true,
                  onPressed: s.isSubmitting
                      ? null
                      : () => ref
                          .read(onboardingControllerProvider.notifier)
                          .back(),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: HwButton(
                // Licenses (step 2) is optional → "Skip / Next" like the web.
                label: isLast
                    ? 'Submit application'
                    : (s.currentStep == 1 ? 'Skip / Next' : 'Continue'),
                isLoading: s.isSubmitting,
                onPressed: (isLast && !canSubmit) ? null : _onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// A step "card": a header (icon + title + subtitle) and a card body holding
/// the labeled fields.
class _StepShell extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  const _StepShell({
    this.icon,
    this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showHeader = title != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ThemeConstants.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: ThemeConstants.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title!,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ThemeConstants.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle ?? '',
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: ThemeConstants.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          decoration: BoxDecoration(
            color: isDark ? ThemeConstants.surface : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ThemeConstants.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Theme-aware logo (same single-SVG treatment as home; identical size in both
/// themes — white variant in dark, black in light).
class _OnboardingLogo extends StatelessWidget {
  final double height;
  const _OnboardingLogo({this.height = 30});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      isDark
          ? 'assets/images/Hydrawav3_White_Logo.svg'
          : 'assets/images/Hydrawav3_Black_Logo.svg',
      height: height,
      fit: BoxFit.contain,
    );
  }
}

/// Shown after a successful submit — no auto-login (the endpoint returns no
/// user session), so we route back to sign in.
class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _OnboardingLogo(height: 44),
              const SizedBox(height: 36),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: ThemeConstants.success.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded,
                    size: 40, color: ThemeConstants.success),
              ),
              const SizedBox(height: 22),
              Text('Application submitted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ThemeConstants.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Thanks! We\'ll review your details and set up your account. '
                'You\'ll be able to sign in once it\'s approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: ThemeConstants.textSecondary),
              ),
              const SizedBox(height: 28),
              HwButton(
                label: 'Back to sign in',
                width: double.infinity,
                onPressed: () => context.go(RoutePaths.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
