import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/logger.dart';
import '../../data/onboarding_remote_source.dart';
import '../../domain/onboarding_models.dart';

/// State for the multi-step "Create account" onboarding flow.
class OnboardingState {
  final int currentStep; // 0..3
  final PractitionerForm form;
  final List<OnboardingCertification> certifications;
  final List<OnboardingBusiness> businesses;
  final String? businessLogoPath;
  final String? businessLogoName;
  final bool euaAccepted;
  final bool isSubmitting;
  final bool submitted;
  final String? error;

  /// Set once step 1 has created the practitioner. The token authorizes the
  /// sports fetch and the remaining submit calls; both are kept so stepping
  /// back and forward never creates a second account.
  final String? practitionerId;
  final String? authToken;
  final bool isCreatingAccount;

  /// Sports offered by the platform, loaded right after the account is created
  /// (the endpoint needs a token). Empty until then, or if the fetch fails.
  final List<SportOption> sports;

  /// Per-field errors for step 1 (keyed by field name).
  final Map<String, String> step1Errors;

  const OnboardingState({
    this.currentStep = 0,
    this.form = const PractitionerForm(),
    this.certifications = const [],
    this.businesses = const [],
    this.businessLogoPath,
    this.businessLogoName,
    this.euaAccepted = false,
    this.isSubmitting = false,
    this.submitted = false,
    this.error,
    this.step1Errors = const {},
    this.practitionerId,
    this.authToken,
    this.isCreatingAccount = false,
    this.sports = const [],
  });

  /// True once step 1 has provisioned the account and handed back a token.
  bool get hasAccount =>
      (practitionerId?.isNotEmpty ?? false) && (authToken?.isNotEmpty ?? false);

  bool get hasBusinessLogo =>
      businessLogoPath != null && businessLogoPath!.isNotEmpty;

  OnboardingState copyWith({
    int? currentStep,
    PractitionerForm? form,
    List<OnboardingCertification>? certifications,
    List<OnboardingBusiness>? businesses,
    String? businessLogoPath,
    String? businessLogoName,
    bool clearLogo = false,
    bool? euaAccepted,
    bool? isSubmitting,
    bool? submitted,
    String? error,
    Map<String, String>? step1Errors,
    String? practitionerId,
    String? authToken,
    bool? isCreatingAccount,
    List<SportOption>? sports,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      form: form ?? this.form,
      certifications: certifications ?? this.certifications,
      businesses: businesses ?? this.businesses,
      businessLogoPath:
          clearLogo ? null : (businessLogoPath ?? this.businessLogoPath),
      businessLogoName:
          clearLogo ? null : (businessLogoName ?? this.businessLogoName),
      euaAccepted: euaAccepted ?? this.euaAccepted,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitted: submitted ?? this.submitted,
      error: error,
      step1Errors: step1Errors ?? this.step1Errors,
      practitionerId: practitionerId ?? this.practitionerId,
      authToken: authToken ?? this.authToken,
      isCreatingAccount: isCreatingAccount ?? this.isCreatingAccount,
      sports: sports ?? this.sports,
    );
  }
}

/// Options for the step-1 Account Type select (`GET {node}user/account-types`).
/// Public endpoint — fetched before the practitioner account exists.
final accountTypesProvider =
    FutureProvider.autoDispose<List<AccountTypeOption>>((ref) {
  return ref.read(onboardingRemoteSourceProvider).getAccountTypes();
});

final onboardingControllerProvider =
    StateNotifierProvider.autoDispose<OnboardingController, OnboardingState>(
        (ref) {
  return OnboardingController(ref);
});

class OnboardingController extends StateNotifier<OnboardingState> {
  final Ref _ref;
  OnboardingController(this._ref) : super(const OnboardingState());

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  // ── Step 1 ────────────────────────────────────────────────────────────────
  void setForm(PractitionerForm form) => state = state.copyWith(form: form);

  /// Validate step 1 (parity with web). Returns true if valid; stores per-field
  /// errors otherwise.
  bool validateStep1(PractitionerForm f) {
    final errors = <String, String>{};
    void req(String key, String val) {
      if (val.trim().isEmpty) errors[key] = 'Required';
    }

    req('firstName', f.firstName);
    req('lastName', f.lastName);
    req('username', f.username);
    req('email', f.email);
    req('phone', f.phone);
    req('title', f.title);
    req('accountType', f.accountType);
    req('address', f.address);
    req('city', f.city);
    req('state', f.state);
    req('zip', f.zip);
    req('country', f.country);
    req('dateOfBirth', f.dateOfBirth);

    if (f.password.isEmpty) {
      errors['password'] = 'Required';
    } else if (f.password.length < 8) {
      errors['password'] = 'Must be at least 8 characters';
    }
    if (f.email.isNotEmpty && !_emailRe.hasMatch(f.email)) {
      errors['email'] = 'Enter a valid email address';
    }

    state = state.copyWith(form: f, step1Errors: errors);
    return errors.isEmpty;
  }

  bool isValidEmail(String email) => _emailRe.hasMatch(email);

  /// Provision the practitioner account (submit call 1) when leaving step 1, so
  /// the token it returns can authorize the sports fetch the Business step
  /// needs. Creates ONCE — stepping back to step 1 and forward again reuses the
  /// existing account instead of creating a duplicate (web parity).
  ///
  /// Returns true when the account exists afterwards.
  Future<bool> createAccount() async {
    if (state.hasAccount) return true;
    if (state.isCreatingAccount) return false;

    state = state.copyWith(isCreatingAccount: true, error: null);
    try {
      final createPayload = buildCreatePractitionerJson(state.form);
      appLogger.i(
        'Onboarding create payload: account_type_id=${createPayload['account_type_id']} '
        'present=${state.form.accountType.trim().isNotEmpty}',
      );
      final created = await _ref
          .read(onboardingRemoteSourceProvider)
          .createPractitioner(createPayload);
      state = state.copyWith(
        isCreatingAccount: false,
        practitionerId: created.userId,
        authToken: created.token,
      );
      // Best-effort: onboarding continues (without sport selection) if this
      // fails — the org is simply created with no sportIds.
      unawaited(_loadSports(created.token));
      return true;
    } on ServerException catch (e) {
      state = state.copyWith(isCreatingAccount: false, error: e.message);
      return false;
    } catch (e) {
      appLogger.e('Onboarding: account create error: $e');
      state = state.copyWith(
        isCreatingAccount: false,
        error: 'Something went wrong. Please try again.',
      );
      return false;
    }
  }

  /// Re-run the sports fetch with the token from step 1 — the picker offers
  /// this when the list came back empty (a failed fetch looks identical to a
  /// genuinely empty catalogue otherwise).
  Future<void> reloadSports() async {
    final token = state.authToken;
    if (token == null || token.isEmpty) return;
    await _loadSports(token);
  }

  Future<void> _loadSports(String token) async {
    try {
      final sports =
          await _ref.read(onboardingRemoteSourceProvider).getSports(token);
      if (!mounted) return;
      state = state.copyWith(sports: sports, error: state.error);
    } catch (e) {
      appLogger.w('Onboarding: sports fetch failed (ignored): $e');
    }
  }

  // ── Step 2: certifications ──────────────────────────────────────────────────
  void addCertification(OnboardingCertification cert) {
    state = state.copyWith(
      certifications: [...state.certifications, cert],
    );
  }

  void removeCertification(int index) {
    final list = [...state.certifications]..removeAt(index);
    state = state.copyWith(certifications: list);
  }

  // ── Step 3: businesses + logo ───────────────────────────────────────────────
  void addBusiness(OnboardingBusiness business) {
    state = state.copyWith(businesses: [...state.businesses, business]);
  }

  void removeBusiness(int index) {
    final list = [...state.businesses]..removeAt(index);
    state = state.copyWith(businesses: list);
  }

  void setBusinessLogo(String path, String name) {
    state = state.copyWith(businessLogoPath: path, businessLogoName: name);
  }

  void clearBusinessLogo() => state = state.copyWith(clearLogo: true);

  // ── File picking (document picker only — no photo/storage permissions) ───────
  /// Pick a certification document (pdf/png/jpg). Returns the picked file or null.
  Future<PlatformFile?> pickCertificationDocument() async {
    return _pick(const ['pdf', 'png', 'jpg', 'jpeg']);
  }

  /// Pick a business logo image. Sets it on state directly.
  Future<void> pickBusinessLogo() async {
    final file = await _pick(const ['png', 'jpg', 'jpeg', 'svg']);
    if (file?.path != null) {
      setBusinessLogo(file!.path!, file.name);
    }
  }

  Future<PlatformFile?> _pick(List<String> extensions) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: false,
      );
      final file = result?.files.firstOrNull;
      if (file == null || file.path == null) return null;
      return file;
    } catch (e) {
      appLogger.w('Onboarding: file pick failed (ignored): $e');
      return null;
    }
  }

  // ── EUA + navigation ────────────────────────────────────────────────────────
  void setEua(bool value) => state = state.copyWith(euaAccepted: value);

  void goTo(int step) =>
      state = state.copyWith(currentStep: step.clamp(0, 3), error: null);

  void next() => goTo(state.currentStep + 1);
  void back() => goTo(state.currentStep - 1);

  // ── Submit ──────────────────────────────────────────────────────────────────
  Future<void> submit() async {
    if (state.isSubmitting) return;
    if (state.businesses.isEmpty) {
      state = state.copyWith(error: 'Add at least one business first.');
      return;
    }
    if (!state.euaAccepted) {
      state = state.copyWith(error: 'Please accept the End User Agreement.');
      return;
    }

    // 1) The account is normally already created (step 1 does it, so sports can
    // load). Falls back to creating here if that hasn't happened.
    if (!state.hasAccount && !await createAccount()) return;
    final userId = state.practitionerId!;
    final token = state.authToken!;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final remote = _ref.read(onboardingRemoteSourceProvider);
      final form = state.form;

      // 2) Create the business / organization from the first business.
      final orgId = await remote.createOrganization(
        buildOrganizationJson(state.businesses.first),
        token,
      );

      // 3) Upload certificate documents (optional, best-effort — web parity).
      for (final cert in state.certifications) {
        await remote.uploadCertificate(
          userId: userId,
          cert: cert,
          token: token,
        );
      }

      // 4) Link the organization to the practitioner account. The web sends
      // `addOrganisations: [Number(orgId)]`, so pass a numeric id when possible.
      final Object orgIdValue = int.tryParse(orgId) ?? orgId;
      final accountUpdatePayload = buildAccountUpdateJson(form, orgIdValue);
      appLogger.i(
        'Onboarding submit payload: account_type_id=${accountUpdatePayload['account_type_id']} '
        'present=${form.accountType.trim().isNotEmpty}',
      );
      await remote.updateUserAccount(
        userId,
        accountUpdatePayload,
        token,
      );

      state = state.copyWith(isSubmitting: false, submitted: true);
    } on ServerException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
    } catch (e) {
      appLogger.e('Onboarding: submit error: $e');
      state = state.copyWith(
        isSubmitting: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }
}
