import 'package:flutter/material.dart';

/// Sunset Coral design system (locked). Same palette light + dark.
class AppColors {
  static const accent = Color(0xFFFF4D6D);
  static const accent2 = Color(0xFFFF8A3D);
  static const accentInk = Color(0xFFE01A48);
  static const gold = Color(0xFFF5A623);
  static const ok = Color(0xFF12B76A);

  static const gradient = [Color(0xFFFF8A3D), Color(0xFFFF4D6D)];
}

const coralGradient = LinearGradient(
  colors: AppColors.gradient,
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: brightness,
    primary: AppColors.accent,
    secondary: AppColors.accent2,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0E0C0F) : const Color(0xFFF6F5F7),
    fontFamily: 'Roboto',
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF211D24) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: isDark ? const Color(0xFF2C2731) : const Color(0xFFEAE8EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: isDark ? const Color(0xFF2C2731) : const Color(0xFFEAE8EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    ),
  );
}
