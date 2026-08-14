import 'package:flutter/material.dart';

/// One timed subtitle line — different lines at different timestamps (§11.12).
class SubtitleSegment {
  SubtitleSegment({
    required this.text,
    required this.start,
    required this.end,
    this.fontFamily,
    this.fontFilePath,
    this.color = 0xFFFFFFFF,
    this.fontSize = 28,
  });

  String text;
  double start; // seconds
  double end; // seconds
  String? fontFamily; // registered family (for preview); null = default
  String? fontFilePath; // .ttf/.otf path (for FFmpeg export); null = default
  int color; // ARGB
  double fontSize;

  Color get uiColor => Color(color);

  SubtitleSegment copy() => SubtitleSegment(
        text: text, start: start, end: end,
        fontFamily: fontFamily, fontFilePath: fontFilePath, color: color, fontSize: fontSize,
      );
}

/// The editable project: fixed base clip + overlay layers.
class EditorProject {
  EditorProject({
    required this.baseClipPath,
    required this.defaultFontPath,
    List<SubtitleSegment>? subtitles,
    this.logoPath,
  }) : subtitles = subtitles ?? [];

  String baseClipPath;
  String defaultFontPath;
  List<SubtitleSegment> subtitles;
  String? logoPath;

  /// Active subtitles at time [t] (seconds).
  List<SubtitleSegment> activeAt(double t) =>
      subtitles.where((s) => t >= s.start && t <= s.end).toList();
}
