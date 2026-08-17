import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';
import 'text_render.dart';

/// Probed facts about the base clip we need before building the filtergraph.
class _ClipProbe {
  _ClipProbe(this.hasAudio, this.width, this.height);
  final bool hasAudio;
  final int? width, height;
}

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
    final off = p.trimStart;

    // Probe the base clip ONCE: does it have an audio stream (so we never wire a
    // non-existent [0:a] pad into the mix), and its native w/h (to remap overlay
    // positions when an aspect crop shrinks the frame).
    final probe = await _probe(p.baseClipPath);

    bool inWindow(double start, double end) {
      // Overlay must intersect the exported window [trimStart, outEnd] (original
      // timeline coords). Fully-before or fully-after overlays are dropped so a
      // trim never silently burns a degenerate between(t,0,0) gate.
      final e = end >= 9998 ? p.outEnd : end;
      return e > p.trimStart + 0.001 && start < p.outEnd - 0.001;
    }

    // Render each VISIBLE, in-window subtitle to a PNG at video-pixel size.
    final texts = <SubtitleSegment>[];
    final textPaths = <String>[];
    for (var i = 0; i < p.subtitles.length; i++) {
      final s = p.subtitles[i];
      if (s.hidden || !inWindow(s.start, s.end)) continue;
      texts.add(s);
      textPaths.add(await TextRenderService.renderToPng(s, i));
    }
    final hasLogo = p.logoPath != null && !p.logoHidden && File(p.logoPath!).existsSync();
    final stickers = p.stickers.where((s) => !s.hidden && inWindow(s.start, s.end) && File(s.path).existsSync()).toList();

    // Aspect crop (center). The editor now crops the preview LIVE (canvas = crop
    // ratio, video cover-cropped), so overlay dx/dy are already stored relative to
    // the CROPPED frame — identical to FFmpeg's main_w/main_h here. No remap needed:
    // preview and export share the same cropped coordinate space (true WYSIWYG).
    String cropFilter = 'null';
    final ar = p.aspect.ratio;
    if (ar != null) {
      cropFilter = "crop='min(iw\\,ih*${_f(ar)})':'min(ih\\,iw/${_f(ar)})',setsar=1";
    }
    double cropDx(double dx) => dx;
    double cropDy(double dy) => dy;
    const cropScaleW = 1.0;

    final outDir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports')
      ..createSync(recursive: true);
    final output = '${outDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Inputs: base [0], logo [1?], text PNGs [next..]. Built as a raw arg LIST and
    // run via executeWithArguments — no shell splitting, so paths with spaces,
    // apostrophes, unicode (emoji filenames) etc. never break the command.
    final parts = <String>['-y'];
    if (p.trimStart > 0.01) parts.addAll(['-ss', _f(p.trimStart, 3)]);
    parts.addAll(['-i', p.baseClipPath]);
    int idx = 1;
    int? logoIdx;
    if (hasLogo) {
      parts.addAll(['-i', p.logoPath!]);
      logoIdx = idx++;
    }
    final textIdx = <int>[];
    for (final tp in textPaths) {
      parts.addAll(['-i', tp]);
      textIdx.add(idx++);
    }
    final stickerIdx = <int>[];
    for (final st in stickers) {
      parts.addAll(['-i', st.path]);
      stickerIdx.add(idx++);
    }
    // optional music input (seek into the track with -ss before -i)
    final hasMusic = p.musicPath != null && File(p.musicPath!).existsSync();
    int? musicIdx;
    if (hasMusic) {
      if (p.musicStart > 0.01) parts.addAll(['-ss', _f(p.musicStart, 3)]);
      parts.addAll(['-i', p.musicPath!]);
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
        // width fraction scaled up under a crop so on-screen size matches preview
        fc.write("[$ii:v][$cur]scale2ref=w='main_w*${_f(0.18 * p.logoScale * cropScaleW)}':h=-1[lg$k][bgl$k];");
        fc.write('[lg$k]rotate=${_f(p.logoRotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[lgr$k];');
        fc.write("[bgl$k][lgr$k]overlay=x='main_w*${_f(cropDx(p.logoDx))}-overlay_w/2':y='main_h*${_f(cropDy(p.logoDy))}-overlay_h/2'[o$k];");
      } else if (kind == 'sticker') {
        final s = o['stk'] as StickerOverlay;
        final st = (s.start - off) < 0 ? 0.0 : (s.start - off);
        // Bound the window to the exported length so a stray large `end` (e.g. 60
        // on a 10s clip) can't create a multi-thousand-second fade/loop.
        final rawEnd = (s.end >= 9998 ? p.outEnd : s.end);
        final en = (rawEnd.clamp(0.0, p.outEnd) - off).clamp(st, double.infinity).toDouble();
        // scale to fraction of frame width (against a reference of the current bg)
        fc.write("[$ii:v][$cur]scale2ref=w='main_w*${_f(s.baseWidthFrac * s.scale * cropScaleW)}':h=-1[sg$k][bgs$k];");
        String lbl = 'sg$k';
        final fade = _fadeChain(_animFadeIn(s.anim, s.fadeIn), s.fadeOut, st, en, 'sg$k', 'sf$k');
        if (fade != null) { fc.write(fade); lbl = 'sf$k'; }
        fc.write('[$lbl]rotate=${_f(s.rotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[sr$k];');
        final sxy = _animXY(s.anim, st, en, "main_w*${_f(cropDx(s.dx))}-overlay_w/2", "main_h*${_f(cropDy(s.dy))}-overlay_h/2");
        fc.write("[bgs$k][sr$k]overlay=x='${sxy['x']}':y='${sxy['y']}':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})[o$k];");
      } else {
        final s = o['seg'] as SubtitleSegment;
        final st = (s.start - off) < 0 ? 0.0 : (s.start - off);
        final enRaw = (s.end.clamp(0.0, p.outEnd) - off);
        final en = enRaw < st ? st : enRaw;
        String src = '$ii:v';
        // Scale the text PNG up under a crop so it keeps its on-screen size (text
        // is composited 1:1, so pre-scale it against the cropped frame).
        if (cropScaleW != 1.0) {
          fc.write("[$src]scale=w='iw*${_f(cropScaleW)}':h=-1[ts$k];");
          src = 'ts$k';
        }
        final fade = _fadeChain(_animFadeIn(s.anim, s.fadeIn), s.fadeOut, st, en, src, 'tf$k');
        if (fade != null) { fc.write(fade); src = 'tf$k'; }
        fc.write('[$src]rotate=${_f(s.rotation, 4)}:fillcolor=0x00000000:ow=hypot(iw\\,ih):oh=hypot(iw\\,ih)[t$k];');
        final xy = _animXY(s.anim, st, en, "main_w*${_f(cropDx(s.dx))}-overlay_w/2", "main_h*${_f(cropDy(s.dy))}-overlay_h/2");
        fc.write("[$cur][t$k]overlay=x='${xy['x']}':y='${xy['y']}':enable=between(t\\,${_f(st, 2)}\\,${_f(en, 2)})[o$k];");
      }
      cur = 'o$k';
    }
    // App watermark (bottom-right), burned only when enabled. Uses drawtext with the
    // bundled default font; escape the font path for the filtergraph.
    if (p.watermarkOn && p.defaultFontPath.isNotEmpty && File(p.defaultFontPath).existsSync()) {
      final fp = p.defaultFontPath.replaceAll('\\', '/').replaceAll(':', '\\:');
      fc.write("[$cur]drawtext=fontfile='$fp':text='ClipCart':"
          "fontcolor=white@0.55:fontsize=h*0.030:"
          "x=w-tw-h*0.02:y=h-th-h*0.02:"
          "shadowcolor=black@0.5:shadowx=2:shadowy=2[wm];");
      cur = 'wm';
    }
    fc.write('[$cur]null[vout]');

    // ---- audio: original (0:a) optionally ducked under an added music track ----
    final dur = p.outDuration;
    String audioMap = '0:a?'; // default: passthrough original (optional → silent if none)
    if (hasMusic) {
      final fadeSt = (dur - 0.8).clamp(0.0, dur);
      // Music is always trimmed to the clip length and faded out at the end.
      final musicChain =
          "[$musicIdx:a]atrim=0:${_f(dur, 3)},asetpts=PTS-STARTPTS,volume=${_f(p.musicVolume, 2)},aresample=44100,afade=t=out:st=${_f(fadeSt, 3)}:d=0.8";
      if (probe.hasAudio) {
        // Duck the original under the music. duration=longest (music is already
        // trimmed to dur) so a SHORT original audio can't truncate the mix.
        fc.write(";[0:a]volume=${_f(p.originalVolume, 2)},aresample=44100[oa];");
        fc.write("$musicChain[ma];");
        fc.write("[oa][ma]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[aout]");
      } else {
        // No original audio stream → NEVER reference [0:a] (that would abort the
        // graph). Map music alone.
        fc.write(";$musicChain[aout]");
      }
      audioMap = '[aout]';
    }

    parts.addAll(['-filter_complex', fc.toString(), '-map', '[vout]', '-map', audioMap]);
    // Always cap to the intended clip length: with duration=longest the mix can
    // now run longer than the video, so -t guarantees both land at outDuration.
    parts.addAll(['-t', _f(p.outDuration, 3)]);
    parts.addAll([
      // High-quality HD export: crf 18 ≈ visually lossless, medium preset for good
      // quality-per-bit (veryfast+crf23 was destroying quality → tiny files).
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
      '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
      '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-shortest', output,
    ]);

    final session = await FFmpegKit.executeWithArguments(parts);
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

  /// Probes the base clip for an audio stream + native dimensions. Failures are
  /// non-fatal: we default to hasAudio=true (matches the previous always-`0:a`
  /// behavior for clips that DO have audio) and null dims (crop remap becomes a
  /// no-op, i.e. the previous full-frame behavior).
  Future<_ClipProbe> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final streams = info?.getStreams() ?? [];
      final hasAudio = streams.any((s) => s.getType() == 'audio');
      int? w, h;
      for (final s in streams) {
        if (s.getType() == 'video') {
          w = s.getWidth();
          h = s.getHeight();
          break;
        }
      }
      return _ClipProbe(hasAudio, w, h);
    } catch (_) {
      return _ClipProbe(true, null, null);
    }
  }
}
