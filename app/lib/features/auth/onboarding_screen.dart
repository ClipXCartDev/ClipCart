import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../../widgets/primary_button.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF2D6B), Color(0xFFB81D54)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('BROWSE · CUSTOMIZE · EXPORT', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 11)),
                const SizedBox(height: 10),
                const Text('Funny clips,\nmade your brand', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1.05)),
                const SizedBox(height: 10),
                const Text('Browse trending meme & movie clips, drop in your text, logo & subtitles, and export in seconds.',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 22),
                PrimaryButton(label: 'Get started', onPressed: () => context.go('/register')),
                const SizedBox(height: 10),
                GoogleButton(onPressed: () async {
                  final err = await auth.googleSignIn();
                  if (err != null && err != 'Cancelled' && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                }),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('I already have an account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
