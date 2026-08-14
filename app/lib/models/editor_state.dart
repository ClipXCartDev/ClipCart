import 'package:flutter/material.dart';

/// One timed, positioned subtitle layer (§11.12). dx/dy are 0..1 fractions of the
/// canvas (center of the text), so overlays can be dragged anywhere.
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
  });

  String text;
  double start; // seconds
  double end; // seconds
  String? fontFamily;
  String? fontFilePath;
  int color; // ARGB
  double fontSize;
  double dx; // 0..1 center X on canvas
  double dy; // 0..1 center Y on canvas

  Color get uiColor => Color(color);

  SubtitleSegment copy() => SubtitleSegment(
        text: text, start: start, end: end, fontFamily: fontFamily,
        fontFilePath: fontFilePath, color: color, fontSize: fontSize, dx: dx, dy: dy,
      );
}

/// The editable project: fixed base clip + positioned overlay layers.
class EditorProject {
  EditorProject({
    required this.baseClipPath,
    required this.defaultFontPath,
    List<SubtitleSegment>? subtitles,
    this.logoPath,
    this.logoDx = 0.85,
    this.logoDy = 0.10,
  }) : subtitles = subtitles ?? [];

  String baseClipPath;
  String defaultFontPath;
  List<SubtitleSegment> subtitles;
  String? logoPath;
  double logoDx; // 0..1 center X
  double logoDy; // 0..1 center Y

  List<SubtitleSegment> activeAt(double t) =>
      subtitles.where((s) => t >= s.start && t <= s.end).toList();
}
