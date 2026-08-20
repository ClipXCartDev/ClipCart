import 'package:flutter/material.dart';

/// ClipCart design system (v2 — from the .dc.html design files).
/// Violet brand · warm-paper canvas · Instrument Sans + IBM Plex Mono.
/// oklch tokens converted to sRGB. One violet accent carries every commit action.
class AppColors {
  // brand
  static const brand = Color(0xFF6D45C9);      // --br  oklch(0.52 0.18 288) violet
  static const brandHover = Color(0xFF5636A3); // brand pressed/ink
  static const brandLight = Color(0xFF846EEA);  // brighter violet (on dark)
  static const brandSurface = Color(0xFFF0ECFA);// --brs subtle violet fill

  // neutrals (warm paper)
  static const bg = Color(0xFFF1EFEB);   // mobile body canvas (slightly deeper paper)
  static const paper = Color(0xFFFBFAF7); // --bg true paper (headers/hero)
  static const surface = Color(0xFFFFFFFF); // --sf cards/sheets
  static const ink = Color(0xFF2E2A25);  // --ink primary text
  static const mut = Color(0xFF77716A);  // --mut secondary text
  static const line = Color(0xFFE7E4DF); // --ln borders

  // media / dark chrome (editor, player)
  static const dark = Color(0xFF232019);  // --dk  media surfaces
  static const dark2 = Color(0xFF37332C); // editor panel
  static const dark3 = Color(0xFF4B463E); // editor border/track

  // premium + status
  static const gold = Color(0xFFD89A3C); // --gd  premium/featured
  static const ok = Color(0xFF2E8A5C);   // --ok  success/active
  static const warn = Color(0xFFC9862F); // --wn  pending/warning
  static const err = Color(0xFFC24338);  // --er  error/failed

  // status badge fills (bg + text)
  static const okBg = Color(0xFFE1F3E7), okText = Color(0xFF1F6743);
  static const warnBg = Color(0xFFFBEBD4), warnText = Color(0xFF875416);
  static const errBg = Color(0xFFFCE9E6);
  static const goldBg = Color(0xFFF7E4C4), goldText = Color(0xFF71501C);

  // Back-compat aliases (older widgets referenced these names). Now violet.
  static const accent = brand;
  static const accent2 = brandLight;
  static const accentInk = brandHover;

  // The design uses a flat violet for commit actions; a soft brand gradient is
  // kept for a few hero moments (banner, FAB, avatar).
  static const gradient = [Color(0xFF7E57DE), Color(0xFF6D45C9)];

  // dark-mode neutrals (paper → ink)
  static const bgDark = Color(0xFF17140F);
  static const surfaceDark = Color(0xFF221E18);
  static const inkDark = Color(0xFFF2EFE9);
  static const mutDark = Color(0xFF9A948B);
  static const lineDark = Color(0xFF332E27);
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
