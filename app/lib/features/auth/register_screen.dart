import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password must be at least 8 characters')));
      return;
    }
    setState(() => _loading = true);
    final err = await context.read<AuthController>().register(_name.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Align(alignment: Alignment.centerLeft, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/onboarding'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text('Create account', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: AppColors.ink)),
              const SizedBox(height: 6),
              const Text('Free clips to start — upgrade anytime', style: TextStyle(color: AppColors.mut, fontSize: 15)),
              const SizedBox(height: 26),
              _label('Name'),
              TextField(controller: _name, decoration: const InputDecoration(hintText: 'Your name')),
              const SizedBox(height: 16),
              _label('Email'),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'you@example.com')),
              const SizedBox(height: 16),
              _label('Password'),
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(hintText: 'At least 8 characters')),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Create account', loading: _loading, onPressed: _submit),
              const SizedBox(height: 18),
              Center(child: TextButton(onPressed: () => context.go('/login'), child: const Text('Have an account? Log in', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600)))),
            ],
          ),
        ),
      ),
    );
  }
}
