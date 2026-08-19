import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final err = await context.read<AuthController>().login(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink))),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/onboarding'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text('Log in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: AppColors.ink)),
              const SizedBox(height: 6),
              const Text('Log in to continue creating', style: TextStyle(color: AppColors.mut, fontSize: 15)),
              const SizedBox(height: 26),
              GoogleButton(onPressed: () async {
                final err = await auth.googleSignIn();
                if (err != null && err != 'Cancelled' && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              }),
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Divider(color: AppColors.line)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.mut, fontSize: 13))),
                const Expanded(child: Divider(color: AppColors.line)),
              ]),
              const SizedBox(height: 18),
              _label('Email'),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'you@example.com')),
              const SizedBox(height: 16),
              _label('Password'),
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(hintText: '••••••••')),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Log in', loading: _loading, onPressed: _submit),
              const SizedBox(height: 18),
              Center(child: TextButton(onPressed: () => context.go('/register'), child: const Text('New here? Create account', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)))),
            ],
          ),
        ),
      ),
    );
  }
}
