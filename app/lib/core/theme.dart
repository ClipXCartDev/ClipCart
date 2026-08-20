import 'package:flutter/material.dart';

/// ClipCart design system — tokens taken directly from the .dc.html design files.
/// Violet brand · warm-paper canvas · Instrument Sans + IBM Plex Mono.
/// Every value below is the oklch token from CLIPCART-SPEC.md §1 converted to sRGB.
/// DO NOT introduce a colour that is not in this file.
class AppColors {
  // brand — violet. oklch(0.52 0.18 288). One accent carries every commit action.
  static const brand = Color(0xFF684FC8);        // --br
  static const brandHover = Color(0xFF553CB0);   // pressed / deep violet
  static const brandLight = Color(0xFF9B87E8);   // on dark chrome (editor)
  static const brandSurface = Color(0xFFEFEEFF); // --brs, subtle violet fill

  // neutrals — warm paper, not grey
  static const bg = Color(0xFFFCFAF6);      // --bg  warm paper canvas
  static const paper = Color(0xFFFCFAF6);   // alias
  static const surface = Color(0xFFFFFFFF); // --sf  cards / sheets
  static const ink = Color(0xFF221F19);     // --ink primary text
  static const mut = Color(0xFF6F6B64);     // --mut secondary text
  static const line = Color(0xFFE4E1DB);    // --ln  borders / dividers

  // media / dark chrome — warm ink-dark, not neutral black
  static const dark = Color(0xFF15120F);   // --dk
  static const dark2 = Color(0xFF27241F);  // --dk2 raised
  static const dark3 = Color(0xFF38342D);  // dark border / track

  // premium + status
  static const gold = Color(0xFFEBAA2D);   // --gd premium / featured
  static const ok = Color(0xFF258343);     // --ok success / active / approved
  static const warn = Color(0xFFD88018);   // --wn pending / changes requested
  static const err = Color(0xFFC2272D);    // --er error / rejected / failed

  // status fills — tints of the status hues, used behind status labels
  static const okBg = Color(0xFFE6F4EA), okText = Color(0xFF1B6334);
  static const warnBg = Color(0xFFFDF0E0), warnText = Color(0xFF8F5410);
  static const errBg = Color(0xFFFBE9E9), errText = Color(0xFF8E1D22);
  static const goldBg = Color(0xFFFCF2DD), goldText = Color(0xFF7A560F);

  // Back-compat aliases so existing widgets keep compiling.
  static const accent = brand;
  static const accent2 = brandLight;
  static const accentInk = brandHover;

  // dark mode
  static const bgDark = Color(0xFF15120F);
  static const surfaceDark = Color(0xFF27241F);
  static const inkDark = Color(0xFFF4F1EB);
  static const mutDark = Color(0xFF9E9890);
  static const lineDark = Color(0xFF38342D);
}

/// Radii from the design: 12 small · 14 cards+inputs · 16 surfaces · 999 pills.
class R {
  static const sm = 12.0, card = 14.0, surface = 16.0, pill = 999.0;
}

const kSans = 'InstrumentSans';
const kMono = 'IBMPlexMono';

/// The design has NO gradients. These exist only so old imports compile —
/// they are flat brand fills. Do not add colour stops.
const brandGradient = LinearGradient(colors: [AppColors.brand, AppColors.brand]);
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
    scaffoldBackgroundColor: isDark ? AppColors.bgDark : AppColors.bg,
    fontFamily: kSans,
    cardColor: surface,
    dividerColor: line,
    textTheme: _textTheme(ink),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: kSans, color: ink, fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: -0.3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
        textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
        textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brand,
        textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.dark2 : AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: isDark ? AppColors.mutDark : AppColors.mut),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: const BorderSide(color: AppColors.brand, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: const BorderSide(color: AppColors.err)),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
  );
}

TextTheme _textTheme(Color ink) {
  TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0}) =>
      TextStyle(fontFamily: kSans, color: ink, fontSize: size, fontWeight: w, height: h, letterSpacing: ls);
  return TextTheme(
    displayLarge: s(40, FontWeight.w600, h: 1.02, ls: -1.2),
    headlineMedium: s(26, FontWeight.w600, h: 1.1, ls: -0.65),
    titleLarge: s(20, FontWeight.w600, h: 1.2, ls: -0.4),
    titleMedium: s(16, FontWeight.w600),
    bodyLarge: s(15, FontWeight.w400, h: 1.55),
    bodyMedium: s(13.5, FontWeight.w400, h: 1.5),
    labelLarge: s(14, FontWeight.w600),
    labelSmall: TextStyle(
        fontFamily: kMono, color: ink, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.1),
  );
}

/// Mono uppercase eyebrow — the design's signature section marker.
TextStyle eyebrow(Color color) => TextStyle(
    fontFamily: kMono, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.3, color: color);

/// Big screen title: 26px / 600 / -0.025em.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.inkDark : AppColors.ink;
    final mut = dark ? AppColors.mutDark : AppColors.mut;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.65, color: ink, height: 1.05)),
                if (subtitle != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!, style: TextStyle(fontSize: 13, color: mut, height: 1.4))),
              ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Standard content card — 1px hairline, radius 14, surface bg.
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
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: dark ? AppColors.lineDark : AppColors.line),
      ),
      child: child,
    );
    return onTap == null ? card : GestureDetector(onTap: onTap, child: card);
  }
}

/// Status pill — colour is NEVER the only signal, the label always rides with it.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.bg, this.fg, {super.key});
  final String label;
  final Color bg, fg;

  factory StatusPill.ok(String l) => StatusPill(l, AppColors.okBg, AppColors.okText);
  factory StatusPill.warn(String l) => StatusPill(l, AppColors.warnBg, AppColors.warnText);
  factory StatusPill.err(String l) => StatusPill(l, AppColors.errBg, AppColors.errText);
  factory StatusPill.gold(String l) => StatusPill(l, AppColors.goldBg, AppColors.goldText);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.pill)),
        child: Text(label,
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
      );
}
