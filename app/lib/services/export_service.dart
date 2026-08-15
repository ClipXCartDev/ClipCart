import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';
import 'text_render.dart';

class ExportResult {
  ExportResult(this.path, this.savedToGallery);
  final String path;
  final bool savedToGallery;
}

/// On-device MP4 export. Every overlay (styled text + logo) is composited as a
/// transparent PNG that is scaled, rotated and time-gated — perfectly WYSIWYG
/// with the editor canvas. Optional trim + aspect-ratio crop.
class ExportService {
  Future<ExportResult> export(EditorProject p) async {
    final trimmed = p.trimStart > 0.01 || p.outEnd < p.duration - 0.01;
    final off = p.trimStart;

    // Render each VISIBLE subtitle to a PNG at video-pixel size.
    final texts = <SubtitleSegment>[];
    final textPaths = <String>[];
    for (var i = 0; i < p.subtitles.length; i++) {
      final s = p.subtitles[i];
      if (s.hidden) continue;
      texts.add(s);
      textPaths.add(await TextRenderService.renderToPng(s, i));
    }
    final hasLogo = p.logoPath != null && !p.logoHidden;

    // Aspect crop (center).
    String cropFilter = 'null';
    final ar = p.aspect.ratio;
    if (ar != null) {
      cropFilter = "crop='min(iw\\,ih*${_f(ar)})':'min(ih\\,iw/${_f(ar)})',setsar=1";
    }

    final outDir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports')
      ..createSync(recursive: true);
    final output = '${outDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Inputs: base [0], logo [1?], text PNGs [next..].
    final parts = <String>['-y'];
    if (p.trimStart > 0.01) parts.addAll(['-ss', _f(p.trimStart, 3)]);
    parts.addAll(['-i', '"${p.baseClipPath}"']);
    int idx = 1;
    int? logoIdx;
    if (hasLogo) {
      parts.addAll(['-i', '"${p.logoPath}"']);
      logoIdx = idx++;
    }
    final textIdx = <int>[];
    for (final tp in textPaths) {
      parts.addAll(['-i', '"$tp"']);
      textIdx.add(idx++);
    }

    // Overlay list sorted by z (ascending → highest z composited last = on top).
    final ovs = <Map<String, dynamic>>[
      if (hasLogo) {'z': p.logoZ, 'logo': true, 'ii': logoIdx},
      for (var i = 0; i < texts.length; i++) {'z': texts[i].z, 'logo': false, 'ii': textIdx[i], 'seg': texts[i]},
    ]..sort((a, b) => (a['z'] as double).compareTo(b['z'] as double));

    // Filtergraph (no spaces; commas inside filter args escaped as \,).
    final fc = StringBuffer()
      ..write('[0:v]')
      ..write(cropFilter)
      ..write('[bg];');
    String cur = 'bg';
    for (var k = 0; k < ovs.length; k++) {
      final o = ovs[k];
      final ii = o['ii'] as int;
      if (o['logo'] == true) {
        fc.write("[$ii:v][$cur]scale2ref=w='main_w*${_f(0.18 * p.logoScale)}':h=-1[lg$k][bgl$k];");
        fc.write('[lg$k]rotate=${_f(p.logoRotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[lgr$k];');
        fc.write("[bgl$k][lgr$k]overlay=x='main_w*${_f(p.logoDx)}-overlay_w/2':y='main_h*${_f(p.logoDy)}-overlay_h/2'[o$k];");
      } else {
        final s = o['seg'] as SubtitleSegment;
        final st = (s.start - off) < 0 ? 0.0 : (s.start - off);
        final en = (s.end - off) < st ? st : (s.end - off);
        fc.write('[$ii:v]rotate=${_f(s.rotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[t$k];');
        fc.write("[$cur][t$k]overlay=x='main_w*${_f(s.dx)}-overlay_w/2':y='main_h*${_f(s.dy)}-overlay_h/2':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})[o$k];");
      }
      cur = 'o$k';
    }
    fc.write('[$cur]null[vout]');

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
}
