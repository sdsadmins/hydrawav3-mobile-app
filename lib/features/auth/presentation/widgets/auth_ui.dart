import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/hw_tokens.dart';

/// The v6 sign-in family (`.authwrap`): warm page, a centred 420px column,
/// an uppercase spaced heading, white form cards with labelled filled
/// fields, and the copper gradient action. Shared by Login, Forgot password,
/// Onboarding and Select organization so they read as one flow.

/// Page frame: warm background, safe area, centred and scrollable.
class AuthPage extends StatelessWidget {
  final Widget child;
  final Widget? bottom;
  final PreferredSizeWidget? appBar;
  final bool center;
  const AuthPage({
    super.key,
    required this.child,
    this.bottom,
    this.appBar,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: child,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: p.bg,
      appBar: appBar,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: center
                  ? LayoutBuilder(
                      builder: (context, c) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 24, 20, 28),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 420),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : body,
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

/// A plain back button for auth app bars (`.backbtn`).
AppBar authAppBar(BuildContext context, {VoidCallback? onBack, Widget? title}) {
  final p = RefPalette.of(context);
  return AppBar(
    backgroundColor: p.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    title: title,
    leading: Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Center(
        child: Semantics(
          button: true,
          label: 'Back',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.card,
                border: Border.all(color: p.cardline),
              ),
              child: Icon(Icons.chevron_left_rounded, color: p.ink2, size: 24),
            ),
          ),
        ),
      ),
    ),
    leadingWidth: 60,
  );
}

/// "CREATE ACCOUNT"-style heading: uppercase, widely spaced, with an
/// optional line under it.
class AuthHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  const AuthHeading(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Column(
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: p.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink3),
          ),
        ],
      ],
    );
  }
}

/// The white form card.
class AuthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.cardline),
        boxShadow: p.shadow,
      ),
      child: child,
    );
  }
}

/// Field label above an input — "Email", with an optional red `*`.
class AuthLabel extends StatelessWidget {
  final String text;
  final bool required;
  const AuthLabel(this.text, {super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: text),
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: p.low, fontWeight: FontWeight.w800),
            ),
        ]),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: p.ink2,
        ),
      ),
    );
  }
}

/// The filled input (`.field input`): warm fill, hairline, copper on focus.
InputDecoration authInputDecoration(
  BuildContext context, {
  String? hint,
  String? error,
  Widget? suffix,
  Widget? prefix,
}) {
  final p = RefPalette.of(context);
  OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.ink3, fontSize: 15),
    errorText: error,
    errorMaxLines: 3,
    isDense: true,
    filled: true,
    fillColor: p.bg2,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    suffixIcon: suffix,
    prefixIcon: prefix,
    border: border(p.cardline),
    enabledBorder: border(p.cardline),
    focusedBorder: border(p.copper, 1.6),
    errorBorder: border(p.low),
    focusedErrorBorder: border(p.low, 1.6),
  );
}

/// Label + filled text field, as a form field.
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final String? hint;
  final String? error;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? action;
  final List<String>? autofill;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.hint,
    this.error,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.action,
    this.autofill,
    this.inputFormatters,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthLabel(label, required: required),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: action,
            autofillHints: autofill,
            inputFormatters: inputFormatters,
            validator: validator,
            onFieldSubmitted: onSubmitted,
            style: TextStyle(color: p.ink, fontSize: 15),
            decoration: authInputDecoration(
              context,
              hint: hint,
              error: error,
              suffix: suffix,
            ),
          ),
        ],
      ),
    );
  }
}

/// The copper gradient action (`.btn.primary`) with near-black ink.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? icon;
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: onTap == null ? .55 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : null,
            child: Ink(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFDEB393),
                    Color(0xFFC69E83),
                    Color(0xFFB27D5C),
                  ],
                  stops: [0, .45, 1],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(168, 123, 92, .7),
                    blurRadius: 20,
                    spreadRadius: -10,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF2B1D12)),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon,
                                size: 18, color: const Color(0xFF2B1D12)),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2B1D12),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The white outline action (`.btn` secondary).
class AuthOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const AuthOutlineButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.cardline),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet text link under a form ("Back to sign in").
class AuthTextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const AuthTextLink({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: p.ink3,
        ),
      ),
    );
  }
}

/// An inline error line.
class AuthError extends StatelessWidget {
  final String text;
  const AuthError(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: RefPalette.of(context).low,
          ),
        ),
      );
}
