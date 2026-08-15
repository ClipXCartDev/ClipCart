import 'package:flutter/material.dart';

enum TextAlignH { left, center, right }

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

  double get effectiveSize => fontSize * scale;
  Color get uiColor => Color(color);

  SubtitleSegment copy() => SubtitleSegment(
        text: text, start: start, end: end, fontFamily: fontFamily,
        fontFilePath: fontFilePath, color: color, fontSize: fontSize, dx: dx, dy: dy,
        scale: scale, rotation: rotation, strokeWidth: strokeWidth, strokeColor: strokeColor,
        bgEnabled: bgEnabled, bgColor: bgColor, align: align,
      );

  Map<String, dynamic> toJson() => {
        't': text, 's': start, 'e': end, 'ff': fontFamily, 'fp': fontFilePath,
        'c': color, 'fs': fontSize, 'dx': dx, 'dy': dy, 'sc': scale, 'rot': rotation,
        'sw': strokeWidth, 'scol': strokeColor, 'bg': bgEnabled, 'bgc': bgColor, 'al': align.index,
      };

  factory SubtitleSegment.fromJson(Map<String, dynamic> j) => SubtitleSegment(
        text: j['t'] as String, start: (j['s'] as num).toDouble(), end: (j['e'] as num).toDouble(),
        fontFamily: j['ff'] as String?, fontFilePath: j['fp'] as String?, color: j['c'] as int,
        fontSize: (j['fs'] as num).toDouble(), dx: (j['dx'] as num).toDouble(), dy: (j['dy'] as num).toDouble(),
        scale: (j['sc'] as num?)?.toDouble() ?? 1.0, rotation: (j['rot'] as num?)?.toDouble() ?? 0.0,
        strokeWidth: (j['sw'] as num?)?.toDouble() ?? 0,
        strokeColor: (j['scol'] as int?) ?? 0xFF000000, bgEnabled: (j['bg'] as bool?) ?? true,
        bgColor: (j['bgc'] as int?) ?? 0x80000000, align: TextAlignH.values[(j['al'] as int?) ?? 1],
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
    this.logoPath,
    this.logoDx = 0.85,
    this.logoDy = 0.10,
    this.logoScale = 1.0,
    this.logoRotation = 0.0,
    this.trimStart = 0.0,
    this.trimEnd,
    this.duration = 0.0,
    this.aspect = AspectOption.original,
  }) : subtitles = subtitles ?? [];

  String baseClipPath;
  String defaultFontPath;
  List<SubtitleSegment> subtitles;
  String? logoPath;
  double logoDx; // 0..1 center X
  double logoDy; // 0..1 center Y
  double logoScale; // multiplier on base logo width (base = 18% of canvas)
  double logoRotation; // radians
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
        'logoPath': logoPath, 'logoDx': logoDx, 'logoDy': logoDy,
        'logoScale': logoScale, 'logoRotation': logoRotation,
        'trimStart': trimStart, 'trimEnd': trimEnd, 'aspect': _aspectIndex(aspect),
      };

  void restore(Map<String, dynamic> s) {
    subtitles = (s['subs'] as List).map((e) => SubtitleSegment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    logoPath = s['logoPath'] as String?;
    logoDx = (s['logoDx'] as num).toDouble();
    logoDy = (s['logoDy'] as num).toDouble();
    logoScale = (s['logoScale'] as num).toDouble();
    logoRotation = (s['logoRotation'] as num).toDouble();
    trimStart = (s['trimStart'] as num).toDouble();
    trimEnd = (s['trimEnd'] as num?)?.toDouble();
    aspect = AspectOption.all[s['aspect'] as int];
  }

  static int _aspectIndex(AspectOption a) => AspectOption.all.indexOf(a).clamp(0, AspectOption.all.length - 1);
}
