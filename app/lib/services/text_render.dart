import 'dart:io';
import 'dart:math' as math;
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
    // Parametric drop shadow (client §5). Offset by distance/angle, softened by
    // blur, at the user's colour+opacity. Painted as its own pass below so it
    // works with or without a stroke — matches the live preview exactly.
    List<Shadow>? shadows;
    double shadowExtent = 0; // how far the shadow reaches past the text (px)
    if (s.shadow) {
      final ang = s.shadowAngle * math.pi / 180.0;
      final dist = (s.shadowDistance / 100.0) * size;
      final blurR = (s.shadowBlur.clamp(0.0, 1.0)) * size * 0.4;
      shadows = [
        Shadow(
          color: Color(s.shadowColor).withOpacity(s.shadowOpacity.clamp(0.0, 1.0)),
          blurRadius: blurR,
          offset: Offset(math.cos(ang) * dist, math.sin(ang) * dist),
        ),
      ];
      // Reserve canvas room for the offset + blur spread (~3σ) so the shadow is
      // never hard-clipped by the PNG bounds (client §5 big-shadow presets).
      shadowExtent = dist.abs() + blurR * 3;
    }
    final style = TextStyle(
      fontFamily: s.fontFamily,
      color: Color(s.color),
      fontSize: size,
      fontWeight: s.bold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: s.letterSpacing,
      height: s.lineHeight,
      // A stroke pass draws the outline; keep the parametric shadow on the fill
      // text so a shadow+stroke combo renders both.
      shadows: shadows,
    );
    final fill = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: _ta(s.align),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size * 24);

    final padX = s.bgEnabled ? size * 0.36 : size * 0.14;
    final padY = s.bgEnabled ? size * 0.18 : size * 0.10;
    final margin = s.strokeWidth * 1.5 + 8 + shadowExtent;
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
            // Clear shadows on the stroke pass so the shadow isn't composited
            // twice (the fill pass below already carries it).
            shadows: const [],
          ),
        ),
        textAlign: _ta(s.align),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size * 24);
      strokePainter.paint(canvas, off);
    } else {
      // Subtle auto legibility shadow ONLY when the user hasn't set an explicit
      // shadow and there's no stroke/bg — otherwise the parametric shadow above
      // (baked into `style.shadows`) is the single source of truth.
      if (!s.bgEnabled && !s.shadow) {
        final shadow = TextPainter(
          text: TextSpan(text: text, style: style.copyWith(color: Colors.black54)),
          textAlign: _ta(s.align),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size * 24);
        shadow.paint(canvas, off + Offset(size * 0.03, size * 0.03));
      }
    }
    fill.paint(canvas, off);

    ui.Image img;
    if (s.opacity < 0.995) {
      // Re-composite the whole layer at reduced opacity so export matches preview.
      final rec2 = ui.PictureRecorder();
      final c2 = Canvas(rec2);
      final layerImg = await rec.endRecording().toImage(w, h);
      c2.saveLayer(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Color.fromRGBO(0, 0, 0, s.opacity.clamp(0.0, 1.0)));
      c2.drawImage(layerImg, Offset.zero, Paint());
      c2.restore();
      img = await rec2.endRecording().toImage(w, h);
    } else {
      img = await rec.endRecording().toImage(w, h);
    }
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/txt_$index.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }

  /// Renders an emoji glyph to a high-res transparent PNG for use as a sticker.
  /// Persisted with a stable name so the same emoji reuses one file.
  static Future<String> renderEmojiToPng(String emoji) async {
    const px = 256.0;
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: px)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width.ceil().clamp(1, 4096);
    final h = tp.height.ceil().clamp(1, 4096);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    tp.paint(canvas, Offset.zero);
    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getApplicationDocumentsDirectory();
    final stk = Directory('${dir.path}/stickers')..createSync(recursive: true);
    final code = emoji.runes.map((r) => r.toRadixString(16)).join('_');
    final path = '${stk.path}/emoji_$code.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return path;
  }
}
