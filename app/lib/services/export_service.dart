import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';

class ExportResult {
  ExportResult(this.path, this.savedToGallery);
  final String path;
  final bool savedToGallery;
}

/// On-device MP4 export. Burns timed subtitles (drawtext: scale/stroke/box/align),
/// scaled+rotated logo overlay, optional trim + aspect-ratio crop. WYSIWYG with the
/// editor canvas. ffmpeg_kit_flutter_new v4.x `execute(String)` API (no spaces in filters).
class ExportService {
  Future<ExportResult> export(EditorProject p, {void Function(double)? onProgress}) async {
    final tmp = await getTemporaryDirectory();
    final trimmed = p.trimStart > 0.01 || p.outEnd < p.duration - 0.01;
    final off = p.trimStart; // subtitle enable times are in full-clip time

    // ---- drawtext chain (one filter per timed line) ----
    final draws = <String>[];
    for (var i = 0; i < p.subtitles.length; i++) {
      final s = p.subtitles[i];
      final tf = File('${tmp.path}/sub_$i.txt');
      await tf.writeAsString(s.text);
      final font = s.fontFilePath ?? p.defaultFontPath;
      final xExpr = switch (s.align) {
        TextAlignH.left => '(w*${_f(s.dx)})',
        TextAlignH.right => '(w*${_f(s.dx)}-text_w)',
        TextAlignH.center => '(w*${_f(s.dx)}-text_w/2)',
      };
      final b = StringBuffer('drawtext=fontfile=$font')
        ..write(':textfile=${tf.path}')
        ..write(':fontcolor=${_col(s.color)}')
        ..write(':fontsize=${s.effectiveSize.round()}')
        ..write(':x=$xExpr:y=(h*${_f(s.dy)}-text_h/2)');
      if (s.strokeWidth > 0) {
        b.write(':borderw=${s.strokeWidth.round()}:bordercolor=${_col(s.strokeColor)}');
      }
      if (s.bgEnabled) {
        b.write(':box=1:boxcolor=${_col(s.bgColor)}:boxborderw=${(s.effectiveSize * 0.28).round()}');
      }
      final st = math.max(0.0, s.start - off);
      final en = math.max(st, s.end - off);
      b.write(':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})');
      draws.add(b.toString());
    }
    final drawChain = draws.join(',');

    // ---- aspect crop (center) ----
    String cropFilter = '';
    final ar = p.aspect.ratio;
    if (ar != null) {
      cropFilter = "crop='min(iw\\,ih*${_f(ar)})':'min(ih\\,iw/${_f(ar)})',setsar=1";
    }

    final outDir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports')
      ..createSync(recursive: true);
    final output = '${outDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // ---- assemble command ----
    final parts = <String>['-y'];
    if (p.trimStart > 0.01) parts.addAll(['-ss', _f(p.trimStart, 3)]);
    parts.addAll(['-i', '"${p.baseClipPath}"']);
    if (p.logoPath != null) parts.addAll(['-i', '"${p.logoPath}"']);

    final fc = StringBuffer();
    // base (after optional crop)
    fc.write('[0:v]');
    fc.write(cropFilter.isEmpty ? 'null' : cropFilter);
    fc.write('[bg];');
    String last = 'bg';
    if (p.logoPath != null) {
      final ang = p.logoRotation;
      // scale logo to 18%*scale of main width, then rotate keeping alpha
      fc.write("[1:v][bg]scale2ref=w='main_w*${_f(0.18 * p.logoScale)}':h=-1[lg][bg2];");
      fc.write('[lg]rotate=${_f(ang, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[lgr];');
      fc.write("[bg2][lgr]overlay=x='main_w*${_f(p.logoDx)}-overlay_w/2':y='main_h*${_f(p.logoDy)}-overlay_h/2'[ov];");
      last = 'ov';
    }
    if (drawChain.isNotEmpty) {
      fc.write('[$last]$drawChain[vout]');
      last = 'vout';
    } else {
      fc.write('[$last]null[vout]');
      last = 'vout';
    }

    parts.addAll(['-filter_complex', fc.toString(), '-map', '"[vout]"', '-map', '"0:a?"']);
    if (trimmed) parts.addAll(['-t', _f(p.outDuration, 3)]);
    parts.addAll([
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
      '-c:a', 'aac', '-movflags', '+faststart', '"$output"',
    ]);

    final session = await FFmpegKit.execute(parts.join(' '));
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Export failed (rc=$rc)\n${logs ?? ''}');
    }

    bool saved = false;
    try {
      await Gal.putVideo(output, album: 'ClipCart');
      saved = true;
    } catch (_) {}
    return ExportResult(output, saved);
  }

  String _f(num v, [int d = 4]) => v.toStringAsFixed(d);

  /// ARGB int → FFmpeg color "0xRRGGBB@A.AA" (alpha only if <1).
  String _col(int argb) {
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final a = ((argb >> 24) & 0xFF) / 255.0;
    return a >= 0.999 ? '0x$rgb' : '0x$rgb@${a.toStringAsFixed(2)}';
  }
}
