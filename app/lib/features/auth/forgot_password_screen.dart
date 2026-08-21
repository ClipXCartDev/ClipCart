import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';

/// §03 Forgot password — UI-only reset flow: email → 6-digit code → new password.
/// No backend is wired here; the affordances simply pop or update local state.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = List.generate(6, (_) => TextEditingController());
  final _codeFocus = List.generate(6, (_) => FocusNode());
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    for (final c in _code) {
      c.dispose();
    }
    for (final f in _codeFocus) {
      f.dispose();
    }
    super.dispose();
  }

  void _onCodeChanged(int i, String v) {
    if (v.isNotEmpty && i < 5) {
      _codeFocus[i + 1].requestFocus();
    } else if (v.isEmpty && i > 0) {
      _codeFocus[i - 1].requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          SizedBox(
            height: H.nav,
            child: Row(children: [
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.arrow_back_rounded, size: 22, color: AppColors.ink)),
                ),
              ),
              const SizedBox(width: 2),
              const Text('Reset password', style: T.pageTitle),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              children: [
                Container(
                  width: 46, height: 46, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(R.inner)),
                  child: const Icon(Icons.mail_outline_rounded, size: 24, color: AppColors.brand),
                ),
                const SizedBox(height: 20),
                const Text('Get a reset code',
                    style: TextStyle(fontFamily: kSans, fontSize: 24, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: AppColors.ink)),
                const SizedBox(height: 10),
                const Text("Enter the email on your account. We'll send a 6-digit code that's valid for 10 minutes.",
                    style: T.body),
                const SizedBox(height: 4),

                // email field
                const FieldLabel('Email'),
                SizedBox(
                  height: H.field,
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
                    decoration: const InputDecoration(hintText: 'you@example.com'),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryBtn('Send code', onTap: () {}),

                // code entry
                const FieldLabel('Enter code'),
                Row(children: [
                  for (var i = 0; i < 6; i++) ...[
                    Expanded(child: _otpBox(i)),
                    if (i < 5) const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('Code expires in 09:42', style: T.bodySmall),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {},
                    child: const Text('Resend', style: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
                  ),
                ]),

                const SizedBox(height: 20),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 4),

                // new password
                const FieldLabel('New password'),
                SizedBox(
                  height: H.field,
                  child: TextField(
                    controller: _password,
                    obscureText: _obscure,
                    style: const TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      suffixIcon: TextButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        child: Text(_obscure ? 'Show' : 'Hide', style: const TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                const Text('At least 10 characters with one number.', style: T.bodySmall),
              ],
            ),
          ),
          _footer(children: [
            PrimaryBtn('Save new password', onTap: () => Navigator.of(context).maybePop()),
          ]),
        ]),
      ),
    );
  }

  Widget _otpBox(int i) {
    final filled = _code[i].text.isNotEmpty;
    return SizedBox(
      height: 52,
      child: TextField(
        controller: _code[i],
        focusNode: _codeFocus[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        onChanged: (v) => _onCodeChanged(i, v),
        style: const TextStyle(fontFamily: kMono, fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.ink),
        decoration: InputDecoration(
          counterText: '',
          hintText: filled ? null : '·',
          hintStyle: const TextStyle(fontFamily: kMono, fontSize: 19, color: AppColors.inkGhost),
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: AppColors.surface,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.inner),
            borderSide: BorderSide(color: filled ? AppColors.brand : AppColors.line, width: filled ? 1.5 : 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.inner),
            borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _footer({required List<Widget> children}) => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}
