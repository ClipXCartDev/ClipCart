import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB), Color(0xFFB81D54)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_rounded, color: Colors.white, size: 56),
              SizedBox(height: 12),
              Text('ClipCart', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              SizedBox(height: 6),
              Text('FUNNY MOVIE CLIPS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 3)),
              SizedBox(height: 28),
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
