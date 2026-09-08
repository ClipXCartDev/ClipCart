import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ClipCart design system — CLIPCART_DESIGN_SPEC.md (mobile v3), DARK theme.
/// Vivid violet brand · deep near-black violet canvas · Instrument Sans (UI) +
/// IBM Plex Mono (data). Token NAMES are kept from the old light palette so every
/// screen re-themes automatically; only the VALUES changed to dark equivalents.
/// DO NOT introduce a colour that is not in §1.
class AppColors {
  // ── §1.1 brand ──────────────────────────────────────────────────────────
  static const brand = Color(0xFF7B5CF0);        // primary — vivid violet that pops on dark
  static const brandPressed = Color(0xFF6A4BDE); // pressed / hover
  static const brandTint = Color(0xFF241E3A);    // info panels, active layer row, icon chips (dark violet tint)
  static const brandTintDeep = Color(0xFF2E2648);// pressed state of tinted surfaces
  static const brandInk = Color(0xFFCBBEF7);     // light violet text on brandTint
  static const brandBorder = Color(0xFF3A3168);  // border of unread / brand-tinted cards
  static const brandLight = Color(0xFF9B87E8);   // lighter violet accent

  // ── §1.2 neutrals (dark, warm-neutral with a hint of violet) ────────────
  static const bg = Color(0xFF0D0B16);           // screen background (deep near-black violet)
  static const bgAlt = Color(0xFF1B1826);        // segmented track, chips, thumb placeholders
  static const surface = Color(0xFF17141F);      // cards, fields, list containers
  static const surfaceHover = Color(0xFF1E1A28); // row hover, icon buttons
  static const surfaceHover2 = Color(0xFF221E2E);// search field, circular icon buttons
  static const line = Color(0xFF2C2838);         // all 1px borders and dividers
  static const lineStrong = Color(0xFF3C3750);   // dashed borders, sheet grabber
  static const ink = Color(0xFFF2F0F7);          // primary text (near-white on dark)
  static const inkMuted = Color(0xFFAAA4B8);     // secondary text, labels
  static const inkFaint = Color(0xFF847E92);     // tertiary text, placeholders
  static const inkGhost = Color(0xFF615C70);     // timestamps, disabled
  static const chevron = Color(0xFF565164);      // row chevrons

  // ── §1.3 status (dark fills, luminous text — same hues) ─────────────────
  static const okBg = Color(0xFF13301F), okText = Color(0xFF74E29C), okIcon = Color(0xFF52CE87);
  static const warnBg = Color(0xFF33260F), warnText = Color(0xFFF0BA64), warnIcon = Color(0xFFE0A040);
  static const goldBg = Color(0xFF2E2611), goldText = Color(0xFFE8C87A);
  static const errBg = Color(0xFF331719), errText = Color(0xFFF17B82), errTextDark = Color(0xFFF5A2A7);
  static const goldAccent = Color(0xFFEBAA2D);   // paywall star tile
  static const greenDot = Color(0xFF5FBE7E);     // autosave / online indicator

  // ── media / chrome (§1.4) ───────────────────────────────────────────────
  static const mediaPlaceholder = Color(0xFF241F45);
  static const scrimModal = Color(0x99000000);   // modal scrim (darker for dark theme)

  // ── back-compat aliases (existing widgets keep compiling) ───────────────
  static const brandHover = brandPressed;
  static const brandSurface = brandTint;
  static const mut = inkMuted;
  static const ok = okIcon, warn = warnIcon, err = errText;
  static const gold = goldAccent, goldIcon = goldText;
  static const paper = bg;
  static const accent = brand, accent2 = brandLight, accentInk = brandPressed;
  // Raised dark panels (kept dark in both worlds) + light copy for the violet cards.
  static const dark = Color(0xFF120F1C), dark2 = Color(0xFF1E1A2A), dark3 = Color(0xFF2C2838);
  static const bgDark = dark, surfaceDark = dark2;
  static const inkDark = Color(0xFFF4F1EB), mutDark = Color(0xFFB9B2C6), lineDark = dark3;
}

/// §3.1 corner radius.
class R {
  static const phone = 44.0;
  static const sheet = 24.0;      // bottom sheet top corners
  static const editor = 22.0;     // editor panel top corners
  static const large = 18.0;      // large card / list container
  static const media = 16.0;      // media card, list item, surface
  static const thumb = 14.0;      // media thumbnail (rail)
  static const button = 14.0;     // button, field
  static const inner = 12.0;      // small button, inner card
  static const tile = 10.0;       // icon tile
  static const pill = 999.0;
  // legacy aliases
  static const sm = button, card = thumb;
  static double get surface => media;
}

/// §3.3 fixed heights.
class H {
  static const statusBar = 52.0;
  static const nav = 54.0;
  static const header = 52.0;
  static const editorBar = 48.0;
  static const primaryBtn = 54.0;
  static const ghostBtn = 48.0;
  static const compactBtn = 44.0;
  static const editorPill = 36.0;
  static const field = 52.0;
  static const smallField = 44.0;
  static const searchField = 44.0;
  static const iconBtn = 40.0;
  static const mediaIconBtn = 36.0;
  static const tabBar = 58.0;
}

const kSans = 'InstrumentSans';
const kMono = 'IBMPlexMono';

/// §2.1 type scale. One place, so every screen stays on the ramp.
class T {
  static const _s = kSans;
  static const _m = kMono;
  // display / titles
  static const display = TextStyle(fontFamily: _s, fontSize: 46, height: 1.02, fontWeight: FontWeight.w600, letterSpacing: -2.0, color: AppColors.ink);
  static const screenTitle = TextStyle(fontFamily: _s, fontSize: 24, height: 1.05, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: AppColors.ink);
  static const pageTitle = TextStyle(fontFamily: _s, fontSize: 19, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: AppColors.ink);
  static const section = TextStyle(fontFamily: _s, fontSize: 16, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: AppColors.ink);
  // cards / rows
  static const cardTitle = TextStyle(fontFamily: _s, fontSize: 15, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.ink);
  static const rowLabel = TextStyle(fontFamily: _s, fontSize: 14, height: 1.0, fontWeight: FontWeight.w500, color: AppColors.ink);
  static const body = TextStyle(fontFamily: _s, fontSize: 14.5, height: 1.55, fontWeight: FontWeight.w400, color: AppColors.inkMuted);
  static const bodySmall = TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w400, color: AppColors.inkMuted);
  static const fieldLabel = TextStyle(fontFamily: _s, fontSize: 12.5, height: 1.0, fontWeight: FontWeight.w500, color: AppColors.inkMuted);
  static const caption = TextStyle(fontFamily: _s, fontSize: 11.5, height: 1.0, fontWeight: FontWeight.w400, color: AppColors.inkFaint);
  static const badge = TextStyle(fontFamily: _s, fontSize: 10.5, height: 1.0, fontWeight: FontWeight.w600);
  static const tab = TextStyle(fontFamily: _s, fontSize: 9.5, height: 1.0, fontWeight: FontWeight.w500);
  // mono — numbers, ids, prices, timestamps, eyebrows
  static const eyebrow = TextStyle(fontFamily: _m, fontSize: 11.5, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: 1.9, color: AppColors.brand);
  static const data = TextStyle(fontFamily: _m, fontSize: 12, height: 1.0, fontWeight: FontWeight.w500, color: AppColors.ink);
  static const dataMuted = TextStyle(fontFamily: _m, fontSize: 11, height: 1.0, fontWeight: FontWeight.w400, color: AppColors.inkFaint);
  static const price = TextStyle(fontFamily: _m, fontSize: 19, height: 1.0, fontWeight: FontWeight.w600, color: AppColors.ink);
}

/// §1.4 mono eyebrow helper (colour override).
TextStyle eyebrow([Color color = AppColors.brand]) => T.eyebrow.copyWith(color: color);

/// Compat gradients — the design has NO gradients; these are flat brand fills.
const brandGradient = LinearGradient(colors: [AppColors.brand, AppColors.brand]);
const coralGradient = brandGradient;

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.dark,
    primary: AppColors.brand,
    onPrimary: Colors.white,
    secondary: AppColors.brandLight,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.errText,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: kSans,
    cardColor: AppColors.surface,
    dividerColor: AppColors.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _textTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: T.pageTitle,
      // Dark app → light (white) status-bar icons.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lineStrong,
        minimumSize: const Size.fromHeight(H.primaryBtn),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
        textStyle: const TextStyle(fontFamily: kSans, fontWeight: FontWeight.w600, fontSize: 16),
      ).copyWith(
        overlayColor: WidgetStateProperty.all(AppColors.brandPressed.withValues(alpha: .28)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(H.field),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
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
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 15, fontWeight: FontWeight.w400),
      labelStyle: T.fieldLabel,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.button), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.button), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.button),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.button),
          borderSide: const BorderSide(color: AppColors.errText)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.button),
          borderSide: const BorderSide(color: AppColors.errText, width: 1.5)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    splashColor: AppColors.brandTint,
    highlightColor: Colors.transparent,
  );
}

TextTheme _textTheme() => const TextTheme(
      displayLarge: T.display,
      headlineMedium: T.screenTitle,
      titleLarge: T.pageTitle,
      titleMedium: T.section,
      bodyLarge: T.body,
      bodyMedium: T.bodySmall,
      labelLarge: T.rowLabel,
      labelSmall: T.eyebrow,
    );

/// Big screen title block (Home/Explore/My Clips headers). 24/600/-0.8.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: T.screenTitle),
            if (subtitle != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(subtitle!, style: T.caption)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Standard content card — §4.5 list container: surface, 1px line, radius 18.
class DesignCard extends StatelessWidget {
  const DesignCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = R.large});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
    return onTap == null
        ? card
        : Material(
            color: Colors.transparent,
            child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card),
          );
  }
}

/// §1.3 status pill — colour is never the only signal, the label rides with it.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.bg, this.fg, {super.key});
  final String label;
  final Color bg, fg;

  factory StatusPill.ok(String l) => StatusPill(l, AppColors.okBg, AppColors.okText);
  factory StatusPill.warn(String l) => StatusPill(l, AppColors.warnBg, AppColors.warnText);
  factory StatusPill.err(String l) => StatusPill(l, AppColors.errBg, AppColors.errTextDark);
  factory StatusPill.gold(String l) => StatusPill(l, AppColors.goldBg, AppColors.goldText);
  factory StatusPill.neutral(String l) => StatusPill(l, AppColors.bgAlt, AppColors.inkMuted);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.pill)),
        child: Text(label, style: T.badge.copyWith(color: fg)),
      );
}
