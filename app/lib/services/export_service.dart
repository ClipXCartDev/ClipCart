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
    final stickers = p.stickers.where((s) => !s.hidden && File(s.path).existsSync()).toList();

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
    final stickerIdx = <int>[];
    for (final st in stickers) {
      parts.addAll(['-i', '"${st.path}"']);
      stickerIdx.add(idx++);
    }
    // optional music input (seek into the track with -ss before -i)
    final hasMusic = p.musicPath != null && File(p.musicPath!).existsSync();
    int? musicIdx;
    if (hasMusic) {
      if (p.musicStart > 0.01) parts.addAll(['-ss', _f(p.musicStart, 3)]);
      parts.addAll(['-i', '"${p.musicPath}"']);
      musicIdx = idx++;
    }

    // Overlay list sorted by z (ascending → highest z composited last = on top).
    final ovs = <Map<String, dynamic>>[
      if (hasLogo) {'z': p.logoZ, 'kind': 'logo', 'ii': logoIdx},
      for (var i = 0; i < texts.length; i++) {'z': texts[i].z, 'kind': 'text', 'ii': textIdx[i], 'seg': texts[i]},
      for (var i = 0; i < stickers.length; i++) {'z': stickers[i].z, 'kind': 'sticker', 'ii': stickerIdx[i], 'stk': stickers[i]},
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
      final kind = o['kind'] as String;
      if (kind == 'logo') {
        fc.write("[$ii:v][$cur]scale2ref=w='main_w*${_f(0.18 * p.logoScale)}':h=-1[lg$k][bgl$k];");
        fc.write('[lg$k]rotate=${_f(p.logoRotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[lgr$k];');
        fc.write("[bgl$k][lgr$k]overlay=x='main_w*${_f(p.logoDx)}-overlay_w/2':y='main_h*${_f(p.logoDy)}-overlay_h/2'[o$k];");
      } else if (kind == 'sticker') {
        final s = o['stk'] as StickerOverlay;
        final st = (s.start - off) < 0 ? 0.0 : (s.start - off);
        final en = ((s.end >= 9998 ? p.outEnd : s.end) - off).clamp(st, double.infinity).toDouble();
        // scale to fraction of frame width (against a reference of the current bg)
        fc.write("[$ii:v][$cur]scale2ref=w='main_w*${_f(s.baseWidthFrac * s.scale)}':h=-1[sg$k][bgs$k];");
        String lbl = 'sg$k';
        final fade = _fadeChain(_animFadeIn(s.anim, s.fadeIn), s.fadeOut, st, en, 'sg$k', 'sf$k');
        if (fade != null) { fc.write(fade); lbl = 'sf$k'; }
        fc.write('[$lbl]rotate=${_f(s.rotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[sr$k];');
        final sxy = _animXY(s.anim, st, en, "main_w*${_f(s.dx)}-overlay_w/2", "main_h*${_f(s.dy)}-overlay_h/2");
        fc.write("[bgs$k][sr$k]overlay=x='${sxy['x']}':y='${sxy['y']}':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})[o$k];");
      } else {
        final s = o['seg'] as SubtitleSegment;
        final st = (s.start - off) < 0 ? 0.0 : (s.start - off);
        final en = (s.end - off) < st ? st : (s.end - off);
        String src = '$ii:v';
        final fade = _fadeChain(_animFadeIn(s.anim, s.fadeIn), s.fadeOut, st, en, src, 'tf$k');
        if (fade != null) { fc.write(fade); src = 'tf$k'; }
        fc.write('[$src]rotate=${_f(s.rotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[t$k];');
        final xy = _animXY(s.anim, st, en, "main_w*${_f(s.dx)}-overlay_w/2", "main_h*${_f(s.dy)}-overlay_h/2");
        fc.write("[$cur][t$k]overlay=x='${xy['x']}':y='${xy['y']}':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})[o$k];");
      }
      cur = 'o$k';
    }
    fc.write('[$cur]null[vout]');

    // ---- audio: original (0:a) optionally ducked under an added music track ----
    final dur = p.outDuration;
    String audioMap = '"0:a?"'; // default: passthrough original
    if (hasMusic) {
      // original at originalVolume, music at musicVolume, both trimmed to clip length,
      // mixed (normalize=0 so per-stream volumes are honored), music fades out at end.
      fc.write(";[0:a]volume=${_f(p.originalVolume, 2)},aresample=44100[oa];");
      fc.write("[$musicIdx:a]atrim=0:${_f(dur, 3)},asetpts=PTS-STARTPTS,volume=${_f(p.musicVolume, 2)},aresample=44100");
      final fadeSt = (dur - 0.8).clamp(0.0, dur);
      fc.write(",afade=t=out:st=${_f(fadeSt, 3)}:d=0.8[ma];");
      fc.write("[oa][ma]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]");
      audioMap = '"[aout]"';
    }

    parts.addAll(['-filter_complex', fc.toString(), '-map', '"[vout]"', '-map', audioMap]);
    if (trimmed) parts.addAll(['-t', _f(p.outDuration, 3)]);
    parts.addAll([
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
      '-c:a', 'aac', '-movflags', '+faststart', '-shortest', '"$output"',
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

  /// Builds a filter chain that fades an overlay's ALPHA in/out over its visible
  /// window [st,en] (seconds on the main timeline). Returns null if no fade.
  /// The still image is looped into a timed stream so fade PTS align with the clip.
  String? _fadeChain(double fadeIn, double fadeOut, double st, double en, String src, String out) {
    if (fadeIn <= 0.01 && fadeOut <= 0.01) return null;
    final dur = (en - st).clamp(0.1, double.infinity);
    final fin = fadeIn.clamp(0.0, dur);
    final fout = fadeOut.clamp(0.0, dur);
    final b = StringBuffer('[$src]format=rgba,loop=loop=-1:size=1:start=0,'
        'setpts=N/FRAME_RATE/TB');
    if (fin > 0.01) b.write(',fade=t=in:st=0:d=${_f(fin, 3)}:alpha=1');
    if (fout > 0.01) b.write(',fade=t=out:st=${_f(dur - fout, 3)}:d=${_f(fout, 3)}:alpha=1');
    // trim to the window length, then shift PTS so the faded stream's t=0 lands at
    // main-time `st` (overlay syncs by PTS; enable gates placement to [st,en]).
    b.write(',trim=0:${_f(dur, 3)},setpts=PTS-STARTPTS+${_f(st, 3)}/TB[$out];');
    return b.toString();
  }

  /// Effective fade-in for an overlay: an explicit fadeIn, OR an implicit ~0.3s
  /// opacity ramp when an animation preset is set (so every preset "appears" in).
  double _animFadeIn(OverlayAnim a, double explicitFadeIn) {
    if (explicitFadeIn > 0.01) return explicitFadeIn;
    if (a == OverlayAnim.none) return 0;
    return 0.3;
  }

  /// Overlay x/y expressions for the animation preset over window [st,en].
  /// [bx]/[by] are the base center expressions (without overlay_w/h subtraction).
  /// Returns {x, y} FFmpeg expressions (main timeline `t`). Scale-based presets
  /// (pop/zoom/bounce/pulse) fall back to position-neutral (the fade-in carries
  /// the motion) since single-pass overlay can't time-vary scale.
  Map<String, String> _animXY(OverlayAnim a, double st, double en, String cx, String cy) {
    // cx/cy already include the -overlay_w/2 / -overlay_h/2 centering.
    String x = cx, y = cy;
    final dIn = 0.35;
    // progress p = clip(( t - st ) / dIn, 0, 1); 1 after entry
    final p = "clip((t-${_f(st, 3)})/$dIn\\,0\\,1)";
    switch (a) {
      case OverlayAnim.slideUp:
        y = "$cy+(1-$p)*main_h*0.12";
        break;
      case OverlayAnim.slideDown:
        y = "$cy-(1-$p)*main_h*0.12";
        break;
      case OverlayAnim.typewriter:
        x = "$cx-(1-$p)*main_w*0.08";
        break;
      case OverlayAnim.shake:
        // damped horizontal jitter during entry
        x = "$cx+(1-$p)*main_w*0.012*sin((t-${_f(st, 3)})*40)";
        break;
      default:
        break; // fade/pop/zoom/bounce/pulse → position neutral; fade-in carries it
    }
    return {'x': x, 'y': y};
  }

  String _f(num v, [int d = 4]) => v.toStringAsFixed(d);
}
