import 'package:flutter/material.dart';

import '../../core/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.brand,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_rounded, color: Colors.white, size: 56),
            SizedBox(height: 12),
            Text('ClipCart', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
            SizedBox(height: 6),
            Text('FUNNY MOVIE CLIPS', style: TextStyle(color: Colors.white70, fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 2)),
            SizedBox(height: 28),
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
