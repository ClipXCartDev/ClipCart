import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

/// Log in — carbon copy of Mobile §3.1 (lines 262–277).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pwFocus = FocusNode();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _pwFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final err = await context.read<AuthController>().login(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(children: [
          // back-nav row (padding 16 24)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Row(children: [
              GestureDetector(
                onTap: () => context.go('/onboarding'),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.ink),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
              children: [
                const Text('Log in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.64, color: AppColors.ink)),
                const SizedBox(height: 14),
                const Text('Use the same account as the website — your plan and favourites follow you.',
                    style: TextStyle(fontSize: 15, color: AppColors.mut, height: 1.5)),
                const SizedBox(height: 14),
                GoogleButton(onPressed: () async {
                  final err = await auth.googleSignIn();
                  if (err != null && err != 'Cancelled' && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }),
                const SizedBox(height: 14),
                _appleButton(),
                const SizedBox(height: 18),
                // "or" divider
                Row(children: const [
                  Expanded(child: Divider(color: AppColors.line, height: 1)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: AppColors.mut, fontSize: 13))),
                  Expanded(child: Divider(color: AppColors.line, height: 1)),
                ]),
                const SizedBox(height: 18),
                _field('Email', _email, focused: false, hint: 'you@example.com', keyboard: TextInputType.emailAddress),
                const SizedBox(height: 14),
                _field('Password', _password, focused: _pwFocus.hasFocus, hint: '••••••••', obscure: true, focusNode: _pwFocus),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent if the email exists.'))),
                    child: const Text('Forgot password?', style: TextStyle(fontSize: 14, color: AppColors.brand, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(height: 54, child: PrimaryButton(label: 'Log in', loading: _loading, onPressed: _submit)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('No account? ', style: TextStyle(fontSize: 14, color: AppColors.mut)),
              GestureDetector(
                onTap: () => context.go('/register'),
                child: const Text('Sign up', style: TextStyle(fontSize: 14, color: AppColors.brand, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _appleButton() => SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in with Apple is available on iPhone.'))),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.ink,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          icon: const Icon(Icons.apple, size: 20, color: Colors.white),
          label: const Text('Continue with Apple', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
        ),
      );

  Widget _field(String label, TextEditingController c, {required bool focused, String? hint, bool obscure = false, TextInputType? keyboard, FocusNode? focusNode}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 14, color: focused ? AppColors.brand : AppColors.mut, fontWeight: focused ? FontWeight.w500 : FontWeight.w400)),
      const SizedBox(height: 7),
      TextField(
        controller: c,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 16, color: AppColors.ink),
        decoration: InputDecoration(hintText: hint, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16)),
      ),
    ]);
  }
}
