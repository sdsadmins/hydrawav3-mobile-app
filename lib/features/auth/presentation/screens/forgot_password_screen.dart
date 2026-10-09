import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/widgets/premium.dart';
import '../../data/auth_repository.dart';
import '../widgets/auth_ui.dart';

/// "Forgot password?" from the login screen — the web's forgot-password
/// page: `POST auth/forgot-password { email }` emails a reset link, and the
/// link opens the web's reset-password page to choose the new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() => _sent = true);
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not send the reset link. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _backToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: authAppBar(context, onBack: _backToLogin),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedEntrance(
                child: _sent ? _sentView(p) : _formView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formView() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeading(
            'Forgot password',
            subtitle: 'Enter the email on your account and we\'ll send you a '
                'link to reset it.',
          ),
          const SizedBox(height: 22),
          AuthCard(
            child: AuthField(
              controller: _emailCtrl,
              label: 'Email',
              hint: 'you@clinic.com',
              keyboardType: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
              action: TextInputAction.send,
              onSubmitted: (_) => _send(),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Required';
                if (!_emailRe.hasMatch(t)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            AuthError(_error!),
          ],
          const SizedBox(height: 16),
          AuthPrimaryButton(
            label: 'Send reset link',
            busy: _sending,
            onTap: _send,
          ),
          const SizedBox(height: 4),
          Center(
            child: AuthTextLink(label: 'Back to sign in', onTap: _backToLogin),
          ),
        ],
      ),
    );
  }

  Widget _sentView(RefPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: p.tanSoft, shape: BoxShape.circle),
            child: Icon(Icons.mark_email_read_outlined,
                size: 34, color: p.copperInk),
          ),
        ),
        const SizedBox(height: 18),
        AuthHeading(
          'Check your email',
          subtitle: 'If an account uses ${_emailCtrl.text.trim()}, we\'ve '
              'sent it a link to reset the password. Open it to choose a new '
              'one, then sign in here.',
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: 'Back to sign in', onTap: _backToLogin),
        const SizedBox(height: 4),
        Center(
          child: AuthTextLink(
            label: 'Use a different email',
            onTap: () => setState(() => _sent = false),
          ),
        ),
      ],
    );
  }
}
