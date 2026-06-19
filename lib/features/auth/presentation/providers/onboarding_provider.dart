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
  });

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
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      form: form ?? this.form,
      certifications: certifications ?? this.certifications,
      businesses: businesses ?? this.businesses,
      businessLogoPath: clearLogo ? null : (businessLogoPath ?? this.businessLogoPath),
      businessLogoName: clearLogo ? null : (businessLogoName ?? this.businessLogoName),
      euaAccepted: euaAccepted ?? this.euaAccepted,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitted: submitted ?? this.submitted,
      error: error,
      step1Errors: step1Errors ?? this.step1Errors,
    );
  }
}

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
    req('address', f.address);
    req('city', f.city);
    req('state', f.state);
    req('zip', f.zip);
    req('country', f.country);

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

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final remote = _ref.read(onboardingRemoteSourceProvider);
      final adminToken = await remote.fetchAdminToken();
      final data = buildOnboardingDataJson(
        form: state.form,
        primaryBusiness: state.businesses.first,
        certifications: state.certifications,
      );
      await remote.submitOnboarding(
        data: data,
        adminToken: adminToken,
        businessLogoPath: state.businessLogoPath,
        certifications: state.certifications,
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
