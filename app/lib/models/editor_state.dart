import 'package:flutter/material.dart';

enum TextAlignH { left, center, right }

/// One-tap "caption look" motion presets applied to a text/sticker overlay.
/// Drives the in/out animation in both the live preview and the FFmpeg export.
enum OverlayAnim {
  none,
  fade, // simple opacity fade in/out
  popIn, // scale from 0 → 1 with a slight overshoot (bouncy)
  slideUp, // rise up + fade in
  slideDown,
  zoomIn, // scale from big → normal
  bounce, // pop with a spring settle
  typewriter, // reveal left→right (approximated by a wipe)
  shake, // quick jitter on entry (attention grab)
  pulse, // gentle continuous scale breathing
}

extension OverlayAnimMeta on OverlayAnim {
  String get label => switch (this) {
        OverlayAnim.none => 'None',
        OverlayAnim.fade => 'Fade',
        OverlayAnim.popIn => 'Pop',
        OverlayAnim.slideUp => 'Slide up',
        OverlayAnim.slideDown => 'Slide down',
        OverlayAnim.zoomIn => 'Zoom',
        OverlayAnim.bounce => 'Bounce',
        OverlayAnim.typewriter => 'Type',
        OverlayAnim.shake => 'Shake',
        OverlayAnim.pulse => 'Pulse',
      };
  IconData get icon => switch (this) {
        OverlayAnim.none => Icons.block,
        OverlayAnim.fade => Icons.gradient,
        OverlayAnim.popIn => Icons.bubble_chart,
        OverlayAnim.slideUp => Icons.arrow_upward,
        OverlayAnim.slideDown => Icons.arrow_downward,
        OverlayAnim.zoomIn => Icons.zoom_in,
        OverlayAnim.bounce => Icons.sports_basketball,
        OverlayAnim.typewriter => Icons.keyboard,
        OverlayAnim.shake => Icons.vibration,
        OverlayAnim.pulse => Icons.favorite,
      };
}

/// One timed, positioned subtitle layer. dx/dy are 0..1 fractions of the canvas
/// (center of the text). scale multiplies fontSize; stroke + bg are burned on export.
class SubtitleSegment {
  SubtitleSegment({
    required this.text,
    required this.start,
    required this.end,
    this.fontFamily,
    this.fontFilePath,
    this.color = 0xFFFFFFFF,
    this.fontSize = 44,
    this.dx = 0.5,
    this.dy = 0.82,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.bgEnabled = true,
    this.bgColor = 0x80000000,
    this.align = TextAlignH.center,
    this.z = 0,
    this.hidden = false,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.anim = OverlayAnim.none,
  });

  String text;
  double start; // seconds
  double end; // seconds
  String? fontFamily;
  String? fontFilePath;
  int color; // ARGB
  double fontSize; // base size in VIDEO pixels (before scale)
  double dx; // 0..1 center X on canvas
  double dy; // 0..1 center Y on canvas
  double scale; // user pinch scale multiplier
  double rotation; // radians
  double strokeWidth; // outline width in video px (0 = none)
  int strokeColor; // ARGB outline
  bool bgEnabled; // background box behind text
  int bgColor; // ARGB box color (alpha honoured)
  TextAlignH align;
  double z; // stacking order (higher = on top)
  bool hidden; // layer visibility
  double fadeIn; // seconds, 0 = none
  double fadeOut; // seconds, 0 = none
  OverlayAnim anim; // one-tap motion preset

  double get effectiveSize => fontSize * scale;
  Color get uiColor => Color(color);

  /// Preview opacity multiplier at time [t] given this segment's fade in/out.
  double opacityAt(double t) {
    var a = 1.0;
    if (fadeIn > 0 && t < start + fadeIn) a = ((t - start) / fadeIn).clamp(0.0, 1.0);
    if (fadeOut > 0 && t > end - fadeOut) a = math_min(a, ((end - t) / fadeOut).clamp(0.0, 1.0));
    return a.clamp(0.0, 1.0);
  }

  /// Live-preview transform (opacity, scale, dx/dy offset) for the animation preset.
  AnimFrame animAt(double t) => computeAnim(anim, t, start, end);

  SubtitleSegment copy() => SubtitleSegment(
        text: text, start: start, end: end, fontFamily: fontFamily,
        fontFilePath: fontFilePath, color: color, fontSize: fontSize, dx: dx, dy: dy,
        scale: scale, rotation: rotation, strokeWidth: strokeWidth, strokeColor: strokeColor,
        bgEnabled: bgEnabled, bgColor: bgColor, align: align, z: z, hidden: hidden,
        fadeIn: fadeIn, fadeOut: fadeOut, anim: anim,
      );

  Map<String, dynamic> toJson() => {
        't': text, 's': start, 'e': end, 'ff': fontFamily, 'fp': fontFilePath,
        'c': color, 'fs': fontSize, 'dx': dx, 'dy': dy, 'sc': scale, 'rot': rotation,
        'sw': strokeWidth, 'scol': strokeColor, 'bg': bgEnabled, 'bgc': bgColor, 'al': align.index, 'z': z, 'hid': hidden,
        'fi': fadeIn, 'fo': fadeOut, 'an': anim.index,
      };

  factory SubtitleSegment.fromJson(Map<String, dynamic> j) => SubtitleSegment(
        text: j['t'] as String, start: (j['s'] as num).toDouble(), end: (j['e'] as num).toDouble(),
        fontFamily: j['ff'] as String?, fontFilePath: j['fp'] as String?, color: j['c'] as int,
        fontSize: (j['fs'] as num).toDouble(), dx: (j['dx'] as num).toDouble(), dy: (j['dy'] as num).toDouble(),
        scale: (j['sc'] as num?)?.toDouble() ?? 1.0, rotation: (j['rot'] as num?)?.toDouble() ?? 0.0,
        strokeWidth: (j['sw'] as num?)?.toDouble() ?? 0,
        strokeColor: (j['scol'] as int?) ?? 0xFF000000, bgEnabled: (j['bg'] as bool?) ?? true,
        bgColor: (j['bgc'] as int?) ?? 0x80000000, align: TextAlignH.values[(j['al'] as int?) ?? 1],
        z: (j['z'] as num?)?.toDouble() ?? 0, hidden: (j['hid'] as bool?) ?? false,
        fadeIn: (j['fi'] as num?)?.toDouble() ?? 0, fadeOut: (j['fo'] as num?)?.toDouble() ?? 0,
        anim: OverlayAnim.values[(j['an'] as int?) ?? 0],
      );
}

double math_min(double a, double b) => a < b ? a : b;

/// Per-frame animation transform: opacity 0..1, scale multiplier, and dx/dy pixel
/// offset (as a fraction of canvas). Shared by text + sticker preview + export.
class AnimFrame {
  const AnimFrame({this.opacity = 1, this.scale = 1, this.ox = 0, this.oy = 0});
  final double opacity, scale, ox, oy;
}

/// Computes the animation transform for [a] at time [t] within window [start,end].
/// In-animation runs over the first ~0.5s, out over the last ~0.35s.
AnimFrame computeAnim(OverlayAnim a, double t, double start, double end) {
  if (a == OverlayAnim.none) return const AnimFrame();
  final dur = (end - start).clamp(0.1, double.infinity);
  final inD = math_min(0.5, dur * 0.5);
  final outD = math_min(0.35, dur * 0.4);
  final tin = ((t - start) / inD).clamp(0.0, 1.0); // 0→1 during entry
  final tout = ((end - t) / outD).clamp(0.0, 1.0); // 1→0 near exit
  double _ease(double x) => 1 - (1 - x) * (1 - x); // easeOutQuad
  double _overshoot(double x) {
    // easeOutBack — overshoots past 1 then settles
    const c1 = 1.70158, c3 = 2.70158;
    final p = x - 1;
    return 1 + c3 * p * p * p + c1 * p * p;
  }
  switch (a) {
    case OverlayAnim.fade:
      return AnimFrame(opacity: math_min(_ease(tin), tout));
    case OverlayAnim.popIn:
      return AnimFrame(opacity: math_min(tin < 1 ? tin : 1.0, tout), scale: tin < 1 ? _overshoot(tin) : 1.0);
    case OverlayAnim.bounce:
      final double s = tin < 1 ? _overshoot(tin) : 1.0;
      return AnimFrame(opacity: math_min(tin < 1 ? _ease(tin) : 1.0, tout), scale: s);
    case OverlayAnim.zoomIn:
      final double s = tin < 1 ? (1.6 - 0.6 * _ease(tin)) : 1.0;
      return AnimFrame(opacity: math_min(_ease(tin), tout), scale: s);
    case OverlayAnim.slideUp:
      return AnimFrame(opacity: math_min(_ease(tin), tout), oy: (1 - _ease(tin)) * 0.12);
    case OverlayAnim.slideDown:
      return AnimFrame(opacity: math_min(_ease(tin), tout), oy: -(1 - _ease(tin)) * 0.12);
    case OverlayAnim.typewriter:
      // approximate: quick horizontal reveal (slide in from left + fade)
      return AnimFrame(opacity: math_min(tin, tout), ox: -(1 - tin) * 0.08);
    case OverlayAnim.shake:
      if (tin >= 1) return AnimFrame(opacity: tout);
      final ph = (t - start) * 40; // fast jitter
      return AnimFrame(opacity: _ease(tin), ox: 0.012 * (1 - tin) * math_sin(ph));
    case OverlayAnim.pulse:
      // continuous gentle breathing
      final ph = (t - start) * 3.2;
      return AnimFrame(opacity: math_min(_ease(tin), tout), scale: 1 + 0.06 * math_sin(ph));
    case OverlayAnim.none:
      return const AnimFrame();
  }
}

double math_sin(double x) {
  // lightweight sine (avoid importing dart:math in the model)
  const tau = 6.283185307179586;
  x = x % tau;
  if (x < 0) x += tau;
  // Bhaskara approximation
  final neg = x > 3.141592653589793;
  if (neg) x -= 3.141592653589793;
  final s = (16 * x * (3.141592653589793 - x)) / (49.348022 - 4 * x * (3.141592653589793 - x));
  return neg ? -s : s;
}

/// An image/emoji sticker layer — positioned/scaled/rotated/time-gated, composited
/// on export exactly like the logo (transparent PNG overlay). [emoji] is set when
/// created from the emoji picker (rendered to a PNG at export/preview time via [path]).
class StickerOverlay {
  StickerOverlay({
    required this.path,
    this.emoji,
    this.start = 0.0,
    this.end = 9999.0,
    this.dx = 0.5,
    this.dy = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.z = 500,
    this.hidden = false,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.baseWidthFrac = 0.22,
    this.anim = OverlayAnim.none,
  });

  String path; // transparent PNG on disk
  String? emoji; // source emoji, if any
  double start, end; // seconds visible window
  double dx, dy; // 0..1 center
  double scale;
  double rotation; // radians
  double z;
  bool hidden;
  double fadeIn, fadeOut; // seconds
  double baseWidthFrac; // base width as fraction of canvas before scale
  OverlayAnim anim;

  double opacityAt(double t) {
    var a = 1.0;
    if (fadeIn > 0 && t < start + fadeIn) a = ((t - start) / fadeIn).clamp(0.0, 1.0);
    if (fadeOut > 0 && t > end - fadeOut) a = math_min(a, ((end - t) / fadeOut).clamp(0.0, 1.0));
    return a.clamp(0.0, 1.0);
  }

  AnimFrame animAt(double t) => computeAnim(anim, t, start >= 9998 ? 0 : start, end >= 9998 ? start + 3 : end);

  StickerOverlay copy() => StickerOverlay(
        path: path, emoji: emoji, start: start, end: end, dx: dx, dy: dy,
        scale: scale, rotation: rotation, z: z, hidden: hidden, fadeIn: fadeIn, fadeOut: fadeOut, baseWidthFrac: baseWidthFrac, anim: anim,
      );

  Map<String, dynamic> toJson() => {
        'p': path, 'em': emoji, 's': start, 'e': end, 'dx': dx, 'dy': dy,
        'sc': scale, 'rot': rotation, 'z': z, 'hid': hidden, 'fi': fadeIn, 'fo': fadeOut, 'bw': baseWidthFrac, 'an': anim.index,
      };

  factory StickerOverlay.fromJson(Map<String, dynamic> j) => StickerOverlay(
        path: j['p'] as String, emoji: j['em'] as String?,
        start: (j['s'] as num?)?.toDouble() ?? 0, end: (j['e'] as num?)?.toDouble() ?? 9999,
        dx: (j['dx'] as num).toDouble(), dy: (j['dy'] as num).toDouble(),
        scale: (j['sc'] as num?)?.toDouble() ?? 1.0, rotation: (j['rot'] as num?)?.toDouble() ?? 0.0,
        z: (j['z'] as num?)?.toDouble() ?? 500, hidden: (j['hid'] as bool?) ?? false,
        fadeIn: (j['fi'] as num?)?.toDouble() ?? 0, fadeOut: (j['fo'] as num?)?.toDouble() ?? 0,
        baseWidthFrac: (j['bw'] as num?)?.toDouble() ?? 0.22,
        anim: OverlayAnim.values[(j['an'] as int?) ?? 0],
      );
}

/// Aspect-ratio target for export (crop/pad). null width = keep source.
class AspectOption {
  const AspectOption(this.label, this.w, this.h);
  final String label;
  final int? w;
  final int? h;
  bool get isOriginal => w == null;
  double? get ratio => (w == null || h == null) ? null : w! / h!;
  static const original = AspectOption('Original', null, null);
  static const portrait = AspectOption('9:16', 9, 16);
  static const square = AspectOption('1:1', 1, 1);
  static const vertical45 = AspectOption('4:5', 4, 5);
  static const landscape = AspectOption('16:9', 16, 9);
  static const all = [original, portrait, square, vertical45, landscape];
}

/// The editable project: base clip (optionally trimmed) + positioned overlay layers.
class EditorProject {
  EditorProject({
    required this.baseClipPath,
    required this.defaultFontPath,
    List<SubtitleSegment>? subtitles,
    List<StickerOverlay>? stickers,
    this.logoPath,
    this.logoDx = 0.85,
    this.logoDy = 0.10,
    this.logoScale = 1.0,
    this.logoRotation = 0.0,
    this.logoZ = 1000,
    this.logoHidden = false,
    this.trimStart = 0.0,
    this.trimEnd,
    this.duration = 0.0,
    this.aspect = AspectOption.original,
  })  : subtitles = subtitles ?? [],
        stickers = stickers ?? [];

  String baseClipPath;
  String defaultFontPath;
  List<SubtitleSegment> subtitles;
  List<StickerOverlay> stickers;
  String? logoPath;
  double logoDx; // 0..1 center X
  double logoDy; // 0..1 center Y
  double logoScale; // multiplier on base logo width (base = 18% of canvas)
  double logoRotation; // radians
  double logoZ; // stacking order
  bool logoHidden; // layer visibility
  double trimStart; // seconds
  double? trimEnd; // seconds (null = clip end)
  double duration; // full clip duration seconds
  AspectOption aspect;

  double get outStart => trimStart;
  double get outEnd => trimEnd ?? duration;
  double get outDuration => (outEnd - outStart).clamp(0.1, double.infinity);

  List<SubtitleSegment> activeAt(double t) =>
      subtitles.where((s) => t >= s.start && t <= s.end).toList();

  /// Snapshot for undo/redo (deep). Excludes immutable base paths.
  Map<String, dynamic> snapshot() => {
        'subs': subtitles.map((s) => s.toJson()).toList(),
        'stk': stickers.map((s) => s.toJson()).toList(),
        'logoPath': logoPath, 'logoDx': logoDx, 'logoDy': logoDy,
        'logoScale': logoScale, 'logoRotation': logoRotation, 'logoZ': logoZ, 'logoHidden': logoHidden,
        'trimStart': trimStart, 'trimEnd': trimEnd, 'aspect': _aspectIndex(aspect),
      };

  void restore(Map<String, dynamic> s) {
    subtitles = (s['subs'] as List).map((e) => SubtitleSegment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    stickers = ((s['stk'] as List?) ?? []).map((e) => StickerOverlay.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    logoPath = s['logoPath'] as String?;
    logoDx = (s['logoDx'] as num).toDouble();
    logoDy = (s['logoDy'] as num).toDouble();
    logoScale = (s['logoScale'] as num).toDouble();
    logoRotation = (s['logoRotation'] as num).toDouble();
    logoZ = (s['logoZ'] as num?)?.toDouble() ?? 1000;
    logoHidden = (s['logoHidden'] as bool?) ?? false;
    trimStart = (s['trimStart'] as num).toDouble();
    trimEnd = (s['trimEnd'] as num?)?.toDouble();
    aspect = AspectOption.all[s['aspect'] as int];
  }

  static int _aspectIndex(AspectOption a) => AspectOption.all.indexOf(a).clamp(0, AspectOption.all.length - 1);
}
