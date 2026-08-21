import 'package:flutter/material.dart';

/// ClipCart design system — CLIPCART_DESIGN_SPEC.md (mobile v3).
/// Violet brand · warm-paper canvas · Instrument Sans (UI) + IBM Plex Mono (data).
/// There is NO dark theme. The only dark surfaces are the Account plan card and
/// the Home subscription banner (`ink` #221F19), used as deliberate contrast blocks.
/// DO NOT introduce a colour that is not in §1.
class AppColors {
  // ── §1.1 brand ──────────────────────────────────────────────────────────
  static const brand = Color(0xFF684FC8);        // primary
  static const brandPressed = Color(0xFF553CB0); // pressed / hover
  static const brandTint = Color(0xFFEFEEFF);    // info panels, active layer row, icon chips
  static const brandTintDeep = Color(0xFFE2DFFA);// pressed state of tinted surfaces
  static const brandInk = Color(0xFF4A3E7A);     // text on brandTint
  static const brandBorder = Color(0xFFDAD5F5);  // border of unread / brand-tinted cards
  static const brandLight = Color(0xFF9B87E8);   // brand on the darkest surfaces

  // ── §1.2 neutrals (warm paper, not grey) ────────────────────────────────
  static const bg = Color(0xFFFCFAF6);           // screen background
  static const bgAlt = Color(0xFFEFECE5);        // segmented track, chips, thumb placeholders
  static const surface = Color(0xFFFFFFFF);      // cards, fields, list containers
  static const surfaceHover = Color(0xFFF7F5F1); // row hover, icon buttons
  static const surfaceHover2 = Color(0xFFF1EEE8);// search field, circular icon buttons
  static const line = Color(0xFFE4E1DB);         // all 1px borders and dividers
  static const lineStrong = Color(0xFFD8D4CC);   // dashed borders, sheet grabber
  static const ink = Color(0xFF221F19);          // primary text, dark contrast cards
  static const inkMuted = Color(0xFF6F6B64);     // secondary text, labels
  static const inkFaint = Color(0xFF8B857C);     // tertiary text, placeholders
  static const inkGhost = Color(0xFFA8A29A);     // timestamps, disabled
  static const chevron = Color(0xFFC4BFB6);      // row chevrons

  // ── §1.3 status ─────────────────────────────────────────────────────────
  static const okBg = Color(0xFFE6F4EA), okText = Color(0xFF1B6334), okIcon = Color(0xFF258343);
  static const warnBg = Color(0xFFFDF0E0), warnText = Color(0xFF8F5410), warnIcon = Color(0xFFD88018);
  static const goldBg = Color(0xFFFCF2DD), goldText = Color(0xFF7A560F);
  static const errBg = Color(0xFFFBE9E9), errText = Color(0xFFC2272D), errTextDark = Color(0xFF8E1D22);
  static const goldAccent = Color(0xFFEBAA2D);   // paywall star tile
  static const greenDot = Color(0xFF5FBE7E);     // autosave / online indicator

  // ── media / dark chrome (§1.4) ──────────────────────────────────────────
  static const mediaPlaceholder = Color(0xFF241F45);
  static const scrimModal = Color(0x52221F19);   // rgba(34,31,25,.32) modal scrim

  // ── back-compat aliases (existing widgets keep compiling) ───────────────
  static const brandHover = brandPressed;
  static const brandSurface = brandTint;
  static const mut = inkMuted;
  static const ok = okIcon, warn = warnIcon, err = errText;
  static const gold = goldAccent, goldIcon = goldText;
  static const paper = bg;
  static const accent = brand, accent2 = brandLight, accentInk = brandPressed;
  static const dark = Color(0xFF15120F), dark2 = Color(0xFF27241F), dark3 = Color(0xFF38342D);
  static const bgDark = dark, surfaceDark = dark2;
  static const inkDark = Color(0xFFF4F1EB), mutDark = Color(0xFF9E9890), lineDark = dark3;
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
    brightness: Brightness.light,
    primary: AppColors.brand,
    secondary: AppColors.brandLight,
    surface: AppColors.surface,
    error: AppColors.errText,
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
