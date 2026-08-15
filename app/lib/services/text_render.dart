import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';

/// Renders a styled subtitle to a transparent PNG at video-pixel size, so the
/// export can overlay it rotated/scaled like any image (drawtext can't rotate).
/// This is what makes text fully transformable + perfectly WYSIWYG.
class TextRenderService {
  static TextAlign _ta(TextAlignH a) => switch (a) {
        TextAlignH.left => TextAlign.left,
        TextAlignH.right => TextAlign.right,
        TextAlignH.center => TextAlign.center,
      };

  static Future<String> renderToPng(SubtitleSegment s, int index) async {
    final size = s.effectiveSize.clamp(8.0, 400.0);
    final text = s.text.isEmpty ? 'Text' : s.text;
    final style = TextStyle(
      fontFamily: s.fontFamily,
      color: Color(s.color),
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.18,
    );
    final fill = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: _ta(s.align),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size * 24);

    final padX = s.bgEnabled ? size * 0.36 : size * 0.14;
    final padY = s.bgEnabled ? size * 0.18 : size * 0.10;
    final margin = s.strokeWidth * 1.5 + 8;
    final w = (fill.width + padX * 2 + margin * 2).ceil();
    final h = (fill.height + padY * 2 + margin * 2).ceil();

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    if (s.bgEnabled) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(margin, margin, w - margin * 2, h - margin * 2),
        Radius.circular(size * 0.18),
      );
      canvas.drawRRect(r, Paint()..color = Color(s.bgColor));
    }
    final off = Offset(margin + padX, margin + padY);
    if (s.strokeWidth > 0) {
      final strokePainter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s.strokeWidth * 2
              ..strokeJoin = StrokeJoin.round
              ..color = Color(s.strokeColor),
          ),
        ),
        textAlign: _ta(s.align),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size * 24);
      strokePainter.paint(canvas, off);
    } else {
      // subtle shadow for legibility when no stroke and no bg
      if (!s.bgEnabled) {
        final shadow = TextPainter(
          text: TextSpan(text: text, style: style.copyWith(color: Colors.black54)),
          textAlign: _ta(s.align),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size * 24);
        shadow.paint(canvas, off + Offset(size * 0.03, size * 0.03));
      }
    }
    fill.paint(canvas, off);

    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/txt_$index.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }
}
