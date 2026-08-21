import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

/// §02 Auth — one screen, Sign up / Log in via a segmented toggle.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialSignup = false});
  final bool initialSignup;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _signup = widget.initialSignup;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pwFocus = FocusNode();
  bool _loading = false, _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pwFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    final err = _signup
        ? await auth.register(_name.text.trim(), _email.text.trim(), _password.text)
        : await auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  void _forgot() => context.push('/forgot');

  /// Inline error card — never a snackbar. Shows the real reason: device-limit
  /// and bad-credentials get friendly copy; anything else (Google, network,
  /// server config) surfaces its actual message instead of a misleading
  /// "check your password" line.
  Widget _errorCard(String raw) {
    final lower = raw.toLowerCase();
    final isDeviceLimit = lower.contains('device') && lower.contains('limit');
    // Only rewrite to the friendly "those details didn't match" on the LOG IN
    // path. On sign up, let the real backend reason through (e.g. "email already
    // registered", "password must contain a number") — masking it there is worse.
    final isBadCreds = !_signup &&
        (lower.contains('credential') ||
            lower.contains('password') ||
            lower.contains('incorrect') ||
            lower.contains("didn't match"));
    final String title, body;
    if (isDeviceLimit) {
      title = 'Device limit reached';
      body = 'This account is signed in on the maximum number of devices. Remove one from Account → Devices, then try again.';
    } else if (isBadCreds) {
      title = "Those details didn't match";
      body = 'Check your email and password and try again.';
    } else {
      title = "Couldn't sign you in";
      body = raw;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.errBg, borderRadius: BorderRadius.circular(R.thumb), border: Border.all(color: const Color(0xFFF3C7C7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.errText),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.errText))),
        ]),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(fontFamily: kSans, fontSize: 13, height: 1.45, color: AppColors.errText)),
      ]),
    );
  }

  Widget _field(String label, TextEditingController c,
      {String? hint, bool obscure = false, TextInputType? keyboard, FocusNode? focusNode, Widget? trailingLabel, Widget? suffix}) {
    final focused = focusNode?.hasFocus ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: T.fieldLabel.copyWith(color: focused ? AppColors.brand : AppColors.inkMuted)),
        if (trailingLabel != null) trailingLabel,
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: H.field,
        child: TextField(
          controller: c,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboard,
          style: const TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink, letterSpacing: 0),
          decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
          children: [
            // logo tile + Skip
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                width: 38, height: 38, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.inner)),
                child: const Text('C', style: TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              TextButton(
                onPressed: () => context.go('/home'),
                style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted, textStyle: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w500)),
                child: const Text('Skip'),
              ),
            ]),
            const SizedBox(height: 22),
            Segmented<bool>(
              value: _signup,
              items: const [(true, 'Sign up'), (false, 'Log in')],
              onChanged: (v) => setState(() {
                _signup = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 24),
            Text(_signup ? 'Create your account' : 'Welcome back', style: const TextStyle(fontFamily: kSans, fontSize: 27, height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -1, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(_signup ? 'One account, two devices.' : 'Log in to pick up where you left off.', style: T.body),
            const SizedBox(height: 22),
            GoogleButton(onPressed: () async {
              final err = await auth.googleSignIn();
              if (err != null && err != 'Cancelled' && mounted) setState(() => _error = err);
            }),
            const SizedBox(height: 20),
            Row(children: const [
              Expanded(child: Divider(color: AppColors.line, height: 1)),
              Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('or email', style: TextStyle(fontFamily: kMono, fontSize: 11.5, color: AppColors.inkFaint, letterSpacing: 1))),
              Expanded(child: Divider(color: AppColors.line, height: 1)),
            ]),
            const SizedBox(height: 20),
            if (_signup) ...[
              _field('Full name', _name, hint: 'Aarav Mehta'),
              const SizedBox(height: 14),
            ],
            _field('Email', _email, hint: 'you@example.com', keyboard: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _field('Password', _password, obscure: _obscure, hint: '••••••••', focusNode: _pwFocus,
                trailingLabel: _signup
                    ? null
                    : GestureDetector(onTap: _forgot, child: const Text('Forgot password?', style: TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand))),
                suffix: TextButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Text(_obscure ? 'Show' : 'Hide', style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
                )),
            const SizedBox(height: 9),
            Text(_signup ? 'At least 10 characters with one number.' : 'Your drafts stay saved on this account.', style: T.bodySmall.copyWith(color: AppColors.inkFaint)),
            const SizedBox(height: 20),
            if (_error != null) _errorCard(_error!),
            PrimaryBtn(_signup ? 'Create account' : 'Log in', loading: _loading, onTap: _submit),
            if (_signup) ...[
              const SizedBox(height: 16),
              Center(child: GestureDetector(onTap: _forgot, child: const Text('Forgot password?', style: TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.inkMuted)))),
            ],
            const SizedBox(height: 18),
            const Center(
              child: Text('By continuing you agree to the Terms and Privacy Policy.',
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: kSans, fontSize: 12, height: 1.5, color: AppColors.inkFaint)),
            ),
          ],
        ),
      ),
    );
  }
}
