import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
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
  /// [onProgress] receives 0.0..1.0 during the render (from real FFmpeg frame
  /// statistics — honest progress, no fake bar). It may not reach exactly 1.0.
  Future<ExportResult> export(EditorProject p, {void Function(double)? onProgress}) async {
    final off = p.trimStart;

    // Audio is mapped as an OPTIONAL original stream (`0:a?`) so a silent clip
    // simply produces a video with no audio track — no probe needed. Music was
    // removed per client (edit/add music no longer supported).

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

    // Aspect crop (center) + optional video PAN/ZOOM inside the frame. The editor
    // crops the preview LIVE (canvas = crop ratio, video cover-cropped) AND lets the
    // user zoom/pan the video inside that frame, so overlay dx/dy are stored relative
    // to the CROPPED frame — identical to FFmpeg's main_w/main_h. True WYSIWYG.
    //
    // Pipeline for a crop with pan/zoom: crop to aspect → scale up by videoScale →
    // crop back to the aspect box at the panned offset. Center pan (0,0) = cover.
    final cropChain = StringBuffer();
    final ar = p.aspect.ratio;
    final vz = p.videoScale.clamp(1.0, 4.0);
    final panX = p.videoDx.clamp(-0.5, 0.5);
    final panY = p.videoDy.clamp(-0.5, 0.5);
    if (ar != null && p.videoFitContain) {
      // FIT mode: letterbox the whole video onto a bg fill of the target aspect.
      // Build a box sized to the aspect (based on the input's larger dimension),
      // scale the video to fit inside it (× videoScale), pad to the box centre.
      final bg = _ffColor(p.videoBgColor);
      // target box: width = max(iw, ih*ar), height = width/ar → contains the source
      cropChain.write("scale=w='iw*${_f(vz)}':h='ih*${_f(vz)}',");
      cropChain.write("pad=w='max(iw\\,ih*${_f(ar)})':h='max(iw\\,ih*${_f(ar)})/${_f(ar)}'"
          ":x='(ow-iw)/2+(ow-iw)*${_f(panX)}':y='(oh-ih)/2+(oh-ih)*${_f(panY)}':color=$bg,setsar=1");
    } else if (ar != null) {
      // FILL mode: cover-crop to the target aspect
      cropChain.write("crop='min(iw\\,ih*${_f(ar)})':'min(ih\\,iw/${_f(ar)})'");
      if (vz > 1.001 || panX.abs() > 0.001 || panY.abs() > 0.001) {
        // 2) zoom (scale the cropped box up), 3) re-crop to the box at the pan offset
        cropChain.write(",scale=iw*${_f(vz)}:ih*${_f(vz)}");
        cropChain.write(",crop=iw/${_f(vz)}:ih/${_f(vz)}"
            ":'(iw-ow)*(0.5+${_f(panX)})':'(ih-oh)*(0.5+${_f(panY)})'");
      }
      cropChain.write(',setsar=1');
    } else if (vz > 1.001 || panX.abs() > 0.001 || panY.abs() > 0.001) {
      // no aspect change but user zoomed/panned the native frame
      cropChain.write("scale=iw*${_f(vz)}:ih*${_f(vz)}");
      cropChain.write(",crop=iw/${_f(vz)}:ih/${_f(vz)}"
          ":'(iw-ow)*(0.5+${_f(panX)})':'(ih-oh)*(0.5+${_f(panY)})',setsar=1");
    } else {
      cropChain.write('null');
    }
    final cropFilter = cropChain.toString();
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
    // Scale the finished frame to the target output resolution. [resolution.shortEdge]
    // is the SHORT edge; keep even dimensions (h264 needs mod-2). The aspect ratio is
    // already correct (crop above), so we scale the short edge and let the long edge
    // follow. Guard: never UPSCALE past the source (min with iw/ih).
    final shortEdge = p.resolution.shortEdge;
    fc.write("[$cur]scale=w='if(gt(iw\\,ih)\\,-2\\,min($shortEdge\\,iw))':"
        "h='if(gt(iw\\,ih)\\,min($shortEdge\\,ih)\\,-2)':flags=bicubic[vout]");

    // ---- audio: original clip audio, optionally mixed under an imported track ----
    final dur = p.outDuration;
    String audioMap = '0:a?'; // default: passthrough original (silent if none)
    if (hasMusic) {
      final clipHasAudio = await _hasAudio(p.baseClipPath);
      final fadeSt = (dur - 0.8).clamp(0.0, dur);
      final fade = p.musicFadeOut ? ",afade=t=out:st=${_f(fadeSt, 3)}:d=0.8" : '';
      // Music trimmed to clip length, level set, optional end fade-out.
      final musicChain = "[$musicIdx:a]atrim=0:${_f(dur, 3)},asetpts=PTS-STARTPTS,"
          "volume=${_f(p.musicVolume, 2)},aresample=44100$fade";
      if (clipHasAudio) {
        // Duck the original clip audio under the music. duration=longest so a short
        // original can't truncate the mix; -t below caps both to the clip length.
        fc.write(";[0:a]volume=${_f(p.originalVolume, 2)},aresample=44100[oa];");
        fc.write("$musicChain[ma];");
        fc.write("[oa][ma]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[aout]");
      } else {
        // Silent clip → never reference [0:a] (would abort the graph). Music alone.
        fc.write(";$musicChain[aout]");
      }
      audioMap = '[aout]';
    }

    parts.addAll(['-filter_complex', fc.toString(), '-map', '[vout]', '-map', audioMap]);
    // Cap to the intended clip length.
    parts.addAll(['-t', _f(p.outDuration, 3)]);
    parts.addAll([
      // High-quality HD export: crf 18 ≈ visually lossless, medium preset for good
      // quality-per-bit. Output frame rate per the user's fps choice (30/60).
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
      '-r', '${p.fps}',
      '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.1',
      '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-shortest', output,
    ]);

    // Total output frames (for honest progress from FFmpeg statistics).
    final totalFrames = (p.outDuration * p.fps).round().clamp(1, 1 << 30);
    // Run async so the Statistics callback fires; await completion via a Completer.
    final done = Completer<void>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      parts,
      (_) => done.complete(),
      (_) {},
      (Statistics stats) {
        if (onProgress != null) {
          final frame = stats.getVideoFrameNumber();
          if (frame > 0) onProgress((frame / totalFrames).clamp(0.0, 0.999));
        }
      },
    );
    await done.future;
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Export failed (rc=$rc)\n${logs ?? ''}');
    }

    // Write a poster-frame thumbnail sidecar (same name, .jpg) so the Exports tab
    // can show what each video is — no extra plugin, just one FFmpeg still grab.
    try {
      final thumb = output.replaceAll('.mp4', '.jpg');
      final tParts = ['-y', '-ss', '0.5', '-i', output, '-frames:v', '1', '-q:v', '3', thumb];
      final tDone = Completer<void>();
      await FFmpegKit.executeWithArgumentsAsync(tParts, (_) => tDone.complete());
      await tDone.future;
    } catch (_) {/* thumbnail is best-effort */}

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

  /// ARGB int → FFmpeg colour literal `0xRRGGBB` (alpha dropped for pad fill).
  String _ffColor(int argb) => '0x${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// True if the clip has an audio stream — so a silent clip never wires a
  /// non-existent [0:a] into the music mix. Non-fatal (defaults true).
  Future<bool> _hasAudio(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final streams = session.getMediaInformation()?.getStreams() ?? [];
      return streams.any((s) => s.getType() == 'audio');
    } catch (_) {
      return true;
    }
  }
}
