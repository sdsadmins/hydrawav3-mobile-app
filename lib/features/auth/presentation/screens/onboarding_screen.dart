import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/config/app_config_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_button.dart';
import '../../domain/onboarding_models.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/auth_ui.dart';

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
  String? _dob; // yyyy-MM-dd (date of birth)
  String? _accountType; // AccountTypeOption.id
  /// Name of the selected account type, captured at selection time. Kept here
  /// rather than re-read from [accountTypesProvider] later: that provider is
  /// autoDispose, so by the time the Business step asks, nothing is watching it
  /// and it has already been torn down.
  String? _accountTypeName;
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
  final _bizSports = <String>{}; // selected sport NAMES (university only)

  /// True when the account type picked on step 1 is the university one. Matched
  /// on the option's NAME, not its id, since ids are per-environment.
  bool get _isUniversityAccount =>
      (_accountTypeName ?? '').toUpperCase() == 'UNIVERSITY';

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _username,
      _password,
      _email,
      _phone,
      _title,
      _address,
      _city,
      _state,
      _zip,
      _country,
      _certName,
      _certOrg,
      _bizName,
      _bizEmail,
      _bizContact,
      _bizAddress,
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
        accountType: _accountType ?? '',
        address: _address.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        zip: _zip.text.trim(),
        country: _country.text.trim(),
        dateOfBirth: _dob ?? '',
      );

  Future<void> _onPrimary() async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final state = ref.read(onboardingControllerProvider);
    final step = state.currentStep;
    switch (step) {
      case 0:
        if (!controller.validateStep1(_buildForm())) {
          _snack('Please complete the required fields.', error: true);
          return;
        }
        if (!state.euaAccepted) {
          _snack('Please accept the End User Agreement.', error: true);
          return;
        }
        // Creating the account here (not at submit) is what makes the sports
        // list reachable on the Business step — it needs the returned token.
        // Safe to re-enter: the controller creates at most once.
        if (!await controller.createAccount()) {
          _snack(
            ref.read(onboardingControllerProvider).error ??
                'Could not create your account.',
            error: true,
          );
          return;
        }
        controller.next();
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
      backgroundColor: RefPalette.of(context).bg,
      appBar: authAppBar(
        context,
        onBack: () {
          if (state.currentStep > 0) {
            ref.read(onboardingControllerProvider.notifier).back();
          } else {
            context.pop();
          }
        },
        title: const _OnboardingLogo(height: 34),
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
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                      child: _heroHeader(),
                    ),
                    _stepper(state.currentStep),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                                  begin: const Offset(0.05, 0),
                                  end: Offset.zero)
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

  // ── Heading (v6 `.authwrap` eyebrow title) ────────────────────────────────
  Widget _heroHeader() {
    return const AuthHeading(
      'Practitioner onboarding',
      subtitle:
          'Share your details so we can tailor the workspace to your practice.',
    );
  }

  // ── Stepper: dots + "Step N of 4 · Name" ─────────────────────────────────
  Widget _stepper(int current) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Semantics(
        label: 'Step ${current + 1} of ${_steps.length}, '
            '${_steps[current].label}',
        child: ExcludeSemantics(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == current ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= current ? p.copper : p.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Step ${current + 1} of ${_steps.length} · '
                '${_steps[current].label}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
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
        _accountTypeField(s.step1Errors['accountType']),
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
        _dateField('Date of Birth', _dob, (v) => setState(() => _dob = v),
            req: true),
        if (s.step1Errors['dateOfBirth'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(s.step1Errors['dateOfBirth']!,
                style: TextStyle(fontSize: 12, color: ThemeConstants.error)),
          ),
        _euaBlock(s),
      ],
    );
  }

  Widget _step2(OnboardingState s) {
    return _StepShell(
      icon: Icons.workspace_premium_rounded,
      title: 'Credentials / Licenses',
      subtitle: 'This step is optional, you can add these later.',
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
        if (_isUniversityAccount) _sportsPicker(s),
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
                  if (e.value.sports.isNotEmpty) e.value.sports.join(', '),
                ].join('  ·  '),
                onRemove: () => ref
                    .read(onboardingControllerProvider.notifier)
                    .removeBusiness(e.key),
              )),
        ],
      ],
    );
  }

  /// University-only: the sports this business offers, sent as `sport` (the
  /// display names) when the organization is created. The options come from the
  /// performance disciplines catalogue, so the list is empty if that fetch
  /// failed — optional either way, so onboarding is never blocked on it.
  Widget _sportsPicker(OnboardingState s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Sports Offered (Optional)', false),
          const SizedBox(height: 8),
          if (s.sports.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text('No sports available to select.',
                      style: TextStyle(
                          fontSize: 13, color: ThemeConstants.textTertiary)),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(onboardingControllerProvider.notifier)
                      .reloadSports(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Retry',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.accent)),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sport in s.sports)
                  _sportChip(
                    label: sport.name,
                    selected: _bizSports.contains(sport.name),
                    onTap: () => setState(() {
                      if (!_bizSports.remove(sport.name))
                        _bizSports.add(sport.name);
                    }),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sportChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ThemeConstants.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : ThemeConstants.textSecondary,
          ),
        ),
      ),
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
      sports: _isUniversityAccount ? _bizSports.toList() : const [],
    ));
    _bizName.clear();
    _bizEmail.clear();
    _bizContact.clear();
    _bizAddress.clear();
    setState(() {
      _bizAge = null;
      _bizSports.clear();
    });
  }

  Widget _step4(OnboardingState s) {
    return _StepShell(
      icon: Icons.fact_check_rounded,
      title: 'Review & Submit',
      subtitle: 'Confirm your details and accept the agreement.',
      children: [
        _reviewRow(Icons.person_rounded, 'Practitioner',
            s.form.fullName.isEmpty ? '--' : s.form.fullName, s.form.email),
        _divider(),
        _reviewRow(Icons.workspace_premium_outlined, 'Licenses',
            '${s.certifications.length} added', null),
        _divider(),
        _reviewRow(Icons.storefront_rounded, 'Businesses',
            '${s.businesses.length} linked', null),
        _divider(),
        _reviewRow(
          Icons.verified_user_outlined,
          'Agreement',
          s.euaAccepted ? 'Accepted' : 'Not accepted',
          null,
        ),
      ],
    );
  }

  /// End User Agreement — read link + acceptance. Lives on step 1 because the
  /// practitioner account is created when that step is completed, and the
  /// create call reports whether the agreement was accepted.
  Widget _euaBlock(OnboardingState s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _launch(AppConfigStore.current.links.privacy),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.description_outlined,
                  size: 18, color: ThemeConstants.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Read the End User Agreement',
                    style: TextStyle(
                        color: ThemeConstants.accent,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline)),
              ),
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
          TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: keyboard,
            textInputAction: TextInputAction.next,
            style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
            decoration:
                _inputDecoration(hint: hint, error: err, suffix: suffix),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, bool req) => AuthLabel(text, required: req);

  InputDecoration _inputDecoration(
          {String? hint, String? error, Widget? suffix}) =>
      authInputDecoration(context, hint: hint, error: error, suffix: suffix);

  /// Step-1 Account Type select. Options come from the public
  /// `user/account-types` endpoint; the selected value is the option's id,
  /// which is submitted as `account_type_id`.
  Widget _accountTypeField(String? err) {
    final options = ref.watch(accountTypesProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Account Type', true),
          options.when(
            loading: () => DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: null,
              isDense: true,
              items: const [],
              onChanged: null,
              decoration: _inputDecoration(hint: 'Loading…', error: err),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: null,
                  isDense: true,
                  items: const [],
                  onChanged: null,
                  decoration: _inputDecoration(
                      hint: 'Couldn\'t load account types', error: err),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(accountTypesProvider),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Retry',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ThemeConstants.accent)),
                ),
              ],
            ),
            data: (types) {
              // Drop a stale selection if the list ever comes back without it,
              // otherwise the dropdown asserts on an unmatched value.
              final value =
                  types.any((t) => t.id == _accountType) ? _accountType : null;
              return DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: value,
                isDense: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded,
                    color: ThemeConstants.textTertiary),
                dropdownColor: ThemeConstants.surface,
                style:
                    TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
                decoration: _inputDecoration(hint: '-- Select --', error: err),
                items: [
                  for (final t in types)
                    DropdownMenuItem(value: t.id, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() {
                  _accountType = v;
                  _accountTypeName = types
                      .where((t) => t.id == v)
                      .map((t) => t.name)
                      .firstOrNull;
                  // A non-university account can't offer sports — drop any
                  // selection made before the type was changed.
                  if (!_isUniversityAccount) _bizSports.clear();
                }),
              );
            },
          ),
        ],
      ),
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
          DropdownButtonFormField<String>(
            isExpanded: true,
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

  Widget _dateField(String label, String? value, ValueChanged<String> onPicked,
      {bool req = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, req),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final now = DateTime.now();
            // Cascading Year → Month → Day picker (no month `< >` navigation):
            // the user picks the year first, then the month, then the day.
            final picked = await showModalBottomSheet<DateTime>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _YearMonthDayPicker(
                firstYear: now.year - 60,
                lastYear: now.year + 60,
                initialDate: DateTime.tryParse(value ?? '') ?? now,
              ),
            );
            if (picked != null) {
              String two(int n) => n.toString().padLeft(2, '0');
              onPicked(
                  '${picked.year}-${two(picked.month)}-${two(picked.day)}');
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
            Icon(
                hasFile
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
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
                          fontSize: 12, color: ThemeConstants.textSecondary)),
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
    final p = RefPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (s.currentStep > 0) ...[
              Expanded(
                child: AuthOutlineButton(
                  label: 'Back',
                  onTap: (s.isSubmitting || s.isCreatingAccount)
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
              child: AuthPrimaryButton(
                // Licenses (step 2) is optional → "Skip / Next" like the web.
                label: isLast
                    ? 'Submit application'
                    : (s.currentStep == 1 ? 'Skip / Next' : 'Continue'),
                // Step 1 provisions the account, so it has its own spinner.
                busy: s.isSubmitting || s.isCreatingAccount,
                onTap: (isLast && !canSubmit) ? null : _onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    // Open INSIDE the app (SFSafariViewController on iOS / Custom Tab on
    // Android), not the external/default browser — App Store Guideline 4.
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }
}

/// A cascading date picker shown in a bottom sheet that selects the date in
/// sequence — **Year → Month → Day** — instead of the Material calendar's
/// month `< >` navigation. Returns the chosen [DateTime] via `Navigator.pop`,
/// or null if dismissed.
class _YearMonthDayPicker extends StatefulWidget {
  final int firstYear;
  final int lastYear;
  final DateTime initialDate;
  const _YearMonthDayPicker({
    required this.firstYear,
    required this.lastYear,
    required this.initialDate,
  });

  @override
  State<_YearMonthDayPicker> createState() => _YearMonthDayPickerState();
}

class _YearMonthDayPickerState extends State<_YearMonthDayPicker> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  // Row height used to estimate the initial year-grid scroll offset
  // (mainAxisExtent 48 + mainAxisSpacing 8).
  static const double _yearRowHeight = 56;

  int _step = 0; // 0 = year, 1 = month, 2 = day
  late int _year;
  late int _month;
  late int _day;
  late final ScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year.clamp(widget.firstYear, widget.lastYear);
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;
    // Years are listed newest-first, so the selected year's row index is
    // (lastYear - year) ~/ 3. Start the grid scrolled near it.
    final rowIndex = ((widget.lastYear - _year) ~/ 3);
    _yearController =
        ScrollController(initialScrollOffset: rowIndex * _yearRowHeight);
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _commitDay(int day) {
    final maxDay = DateUtils.getDaysInMonth(_year, _month);
    Navigator.of(context).pop(DateTime(_year, _month, day.clamp(1, maxDay)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeConstants.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _header(),
          const SizedBox(height: 8),
          SizedBox(height: 320, child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    const titles = ['Select Year', 'Select Month', 'Select Day'];
    final subtitle = _step == 0
        ? ''
        : (_step == 1 ? '$_year' : '${_months[_month - 1]} $_year');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (_step > 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: ThemeConstants.textSecondary,
              onPressed: () => setState(() => _step--),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Column(
              children: [
                Text(
                  titles[_step],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ThemeConstants.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeConstants.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return _yearGrid();
      case 1:
        return _monthGrid();
      default:
        return _dayGrid();
    }
  }

  Widget _yearGrid() {
    final years = [
      for (var y = widget.lastYear; y >= widget.firstYear; y--) y,
    ];
    return GridView.builder(
      controller: _yearController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 48,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
      ),
      itemCount: years.length,
      itemBuilder: (_, i) {
        final y = years[i];
        return _cell(
          label: '$y',
          selected: y == _year,
          onTap: () => setState(() {
            _year = y;
            _step = 1;
          }),
        );
      },
    );
  }

  Widget _monthGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 56,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (_, i) {
        final m = i + 1;
        return _cell(
          label: _months[i],
          selected: m == _month,
          onTap: () => setState(() {
            _month = m;
            _step = 2;
          }),
        );
      },
    );
  }

  Widget _dayGrid() {
    final days = DateUtils.getDaysInMonth(_year, _month);
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisExtent: 44,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: days,
      itemBuilder: (_, i) {
        final d = i + 1;
        return _cell(
          label: '$d',
          selected: d == _day && _day <= days,
          onTap: () => _commitDay(d),
        );
      },
    );
  }

  Widget _cell({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? ThemeConstants.accent.withValues(alpha: 0.16)
              : ThemeConstants.surfaceVariant.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? ThemeConstants.accent : ThemeConstants.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color:
                selected ? ThemeConstants.accent : ThemeConstants.textPrimary,
          ),
        ),
      ),
    );
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
    final p = RefPalette.of(context);
    return AuthCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.tanSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: p.copperInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: p.ink)),
                      if ((subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5, height: 1.3, color: p.ink3)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: p.divider),
            const SizedBox(height: 16),
          ],
          ...children,
        ],
      ),
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

/// Shown after a successful submit. The web-parity flow creates the account +
/// organization and links them; we don't auto-login here, so the practitioner
/// signs in with the username/password they just set.
class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return AuthPage(
      child: Column(
        children: [
          const _OnboardingLogo(height: 40),
          const SizedBox(height: 32),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: p.goodSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 40, color: p.good),
          ),
          const SizedBox(height: 22),
          const AuthHeading(
            'Account created',
            subtitle: 'Your account and business are set up. '
                'Sign in with your username and password to get started.',
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: AuthPrimaryButton(
              label: 'Sign in',
              onTap: () => context.go(RoutePaths.login),
            ),
          ),
        ],
      ),
    );
  }
}
