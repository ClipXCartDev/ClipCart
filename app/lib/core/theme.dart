import 'package:flutter/material.dart';

/// ClipCart design system (v2 — from the .dc.html design files).
/// Violet brand · warm-paper canvas · Instrument Sans + IBM Plex Mono.
/// oklch tokens converted to sRGB. One violet accent carries every commit action.
class AppColors {
  // brand — clean modern blue (replaces the old violet), one accent everywhere
  static const brand = Color(0xFF2563EB);      // primary blue
  static const brandHover = Color(0xFF1D4ED8); // pressed / ink-blue
  static const brandLight = Color(0xFF60A5FA);  // brighter blue (on dark chrome)
  static const brandSurface = Color(0xFFE7EEFD);// subtle blue tint (active pills)

  // neutrals (cool, clean)
  static const bg = Color(0xFFF6F7F9);   // app background
  static const paper = Color(0xFFF6F7F9); // header/frame background (same clean grey-white)
  static const surface = Color(0xFFFFFFFF); // cards / sheets
  static const ink = Color(0xFF191C20);  // primary text (cool near-black)
  static const mut = Color(0xFF6B7280);  // secondary text (cool grey)
  static const line = Color(0xFFE5E7EB); // borders / dividers

  // media / dark chrome (editor, player) — cool neutral near-black
  static const dark = Color(0xFF121316);  // media surfaces
  static const dark2 = Color(0xFF23262C); // editor panel
  static const dark3 = Color(0xFF33373F); // editor border/track

  // premium + status
  static const gold = Color(0xFFE0A73B); // premium/featured
  static const ok = Color(0xFF16A34A);   // success/active
  static const warn = Color(0xFFD97706); // pending/warning
  static const err = Color(0xFFDC2626);  // error/failed

  // status badge fills (bg + text)
  static const okBg = Color(0xFFDCFCE7), okText = Color(0xFF166534);
  static const warnBg = Color(0xFFFEF3C7), warnText = Color(0xFF92590A);
  static const errBg = Color(0xFFFEE2E2);
  static const goldBg = Color(0xFFFBEFD3), goldText = Color(0xFF7A560F);

  // Back-compat aliases (older widgets referenced these names).
  static const accent = brand;
  static const accent2 = brandLight;
  static const accentInk = brandHover;

  // Flat blue for commit actions; a soft gradient for a few hero moments.
  static const gradient = [Color(0xFF3B82F6), Color(0xFF2563EB)];

  // dark-mode neutrals
  static const bgDark = Color(0xFF101114);
  static const surfaceDark = Color(0xFF191B1F);
  static const inkDark = Color(0xFFF3F4F6);
  static const mutDark = Color(0xFF9AA0AA);
  static const lineDark = Color(0xFF2A2D33);
}

/// Fonts.
const kSans = 'InstrumentSans'; // UI
const kMono = 'IBMPlexMono';    // labels / timecodes / data

const brandGradient = LinearGradient(
  colors: AppColors.gradient,
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
// legacy name kept so existing imports don't break
const coralGradient = brandGradient;

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    primary: AppColors.brand,
    secondary: AppColors.brandLight,
    surface: isDark ? AppColors.surfaceDark : AppColors.surface,
  );

  final ink = isDark ? AppColors.inkDark : AppColors.ink;
  final line = isDark ? AppColors.lineDark : AppColors.line;
  final surface = isDark ? AppColors.surfaceDark : AppColors.surface;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Design frame background is --bg (warm paper #FBFAF7), not the deeper canvas.
    scaffoldBackgroundColor: isDark ? AppColors.bgDark : AppColors.paper,
    fontFamily: kSans,
    cardColor: surface,
    dividerColor: line,
    textTheme: _textTheme(ink),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: kSans, color: ink, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.brand, textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.dark2 : Colors.white,
      hintStyle: TextStyle(color: (isDark ? AppColors.mutDark : AppColors.mut).withOpacity(0.9)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
    ),
  );
}

TextTheme _textTheme(Color ink) {
  TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0}) =>
      TextStyle(fontFamily: kSans, color: ink, fontSize: size, fontWeight: w, height: h, letterSpacing: ls);
  return TextTheme(
    displayLarge: s(40, FontWeight.w700, h: 1.02, ls: -1.0),
    headlineMedium: s(26, FontWeight.w700, h: 1.1, ls: -0.5),
    titleLarge: s(20, FontWeight.w700, h: 1.2, ls: -0.3),
    titleMedium: s(16, FontWeight.w600),
    bodyLarge: s(15.5, FontWeight.w400, h: 1.5),
    bodyMedium: s(14, FontWeight.w400, h: 1.45),
    labelLarge: s(14, FontWeight.w600),
    labelSmall: TextStyle(fontFamily: kMono, color: ink, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1.0),
  );
}

/// A mono uppercase "eyebrow" label — the design's signature section marker.
TextStyle eyebrow(Color color) => TextStyle(
      fontFamily: kMono, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1.4, color: color);

/// The canonical big screen title (Search / Templates / Editor / Exports),
/// matching the design: 28px / 600 / -0.025em, ink, with optional trailing action.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).brightness == Brightness.dark ? AppColors.inkDark : AppColors.ink;
    final mut = Theme.of(context).brightness == Brightness.dark ? AppColors.mutDark : AppColors.mut;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.7, color: ink, height: 1.05)),
            if (subtitle != null) Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: TextStyle(fontSize: 13, color: mut)),
            ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Standard content card — 1px hairline, radius 14, surface bg (design spec).
class DesignCard extends StatelessWidget {
  const DesignCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? AppColors.lineDark : AppColors.line),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}
