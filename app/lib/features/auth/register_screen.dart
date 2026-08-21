import 'package:flutter/material.dart';

import 'login_screen.dart';

/// §02 Auth in sign-up mode (the `/register` route reuses the one auth screen).
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) => const LoginScreen(initialSignup: true);
}
