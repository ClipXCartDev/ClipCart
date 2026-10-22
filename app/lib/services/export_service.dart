import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';
import '../models/video_geometry.dart';
import 'text_render.dart';

/// Thrown when the user stopped the render themselves. Separate from a
/// failure so the UI can close quietly instead of reporting an error for
/// something that went exactly as asked.
class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'Export cancelled';
}

/// A render that failed. [message] is the one sentence a person should read;
/// the encoder's own output goes to the log, where it is useful, rather than
/// into a snackbar, where it is not.
class ExportFailure implements Exception {
  const ExportFailure(this.message);
  final String message;
  @override
  String toString() => message;
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
  /// Set while a render is being stopped, so a cancelled session is reported as
  /// a cancellation rather than as a failed encode. FFmpegKit's own cancel
  /// return code is checked too; this covers the window before it lands.
  static bool _cancelRequested = false;

  /// Completes when a render is cancelled, so every wait in [export] has a
  /// second way to wake. FFmpegKit does not reliably call a session's
  /// completion callback after that session is cancelled, and a waiter that
  /// never wakes leaves the whole export hung on "Stopping...".
  static Completer<void>? _cancelWait;

  /// Stop the render in progress. The partially written file is cleaned up by
  /// the export itself when it unwinds.
  static Future<void> cancel() async {
    _cancelRequested = true;
    try {
      await FFmpegKit.cancel();
    } catch (_) {/* nothing running */}
    final w = _cancelWait;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// Waits for [done], or for a cancel, whichever comes first.
  static Future<void> _until(Completer<void> done) =>
      Future.any([done.future, _cancelWait?.future ?? done.future]);

  /// Whether this device can really encode through MediaCodec.
  ///
  /// The encoder being compiled into the FFmpeg build says nothing about the
  /// device exposing it, and finding out the hard way would mean losing a whole
  /// render. So it is settled once with a throwaway frame — well under a second
  /// — and the answer kept for the rest of the session.
  static bool? _hwEncode;

  static Future<bool> _hardwareEncodeWorks() async {
    if (_hwEncode != null) return _hwEncode!;
    try {
      final probe = '${(await getTemporaryDirectory()).path}/hwprobe.mp4';
      final done = Completer<void>();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-y', '-f', 'lavfi', '-i', 'color=c=black:s=320x240:d=0.1',
        '-c:v', 'h264_mediacodec', '-b:v', '200k', '-pix_fmt', 'yuv420p', probe,
      ], (_) => done.complete());
      await _until(done);  // a stop during the probe must not hang either
      final ok = !_cancelRequested && ReturnCode.isSuccess(await session.getReturnCode());
      try { File(probe).deleteSync(); } catch (_) {}
      _hwEncode = ok;
    } catch (_) {
      _hwEncode = false;
    }
    return _hwEncode!;
  }

  /// The encoder's own last words, to the log where they are diagnosable.
  /// FFmpeg front-loads its output with build configuration nobody needs; the
  /// reason a render failed is always at the end.
  static void _logTail(String log, [int lines = 30]) {
    final all = log.trimRight().split('\n');
    for (final l in all.sublist(all.length > lines ? all.length - lines : 0)) {
      debugPrint('[export] $l');
    }
  }

  /// Target bitrate for the hardware encoder, which works to a bitrate rather
  /// than to a quality level the way libx264's CRF does. Chosen for clips that
  /// are going straight to a social feed: visually clean, and small enough that
  /// uploading one on mobile data is not a punishment.
  static String _hwBitrate(int shortEdge) => shortEdge >= 1080 ? '6M' : '3M';

  /// [onProgress] receives 0.0..1.0 during the render (from real FFmpeg frame
  /// statistics — honest progress, no fake bar). It may not reach exactly 1.0.
  /// Short edge of the source's video stream, or null if it can't be probed.
  static Future<int?> _shortEdge(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      for (final st in session.getMediaInformation()?.getStreams() ?? const []) {
        if (st.getType() == 'video') {
          final w = st.getWidth(), h = st.getHeight();
          if (w != null && h != null && w > 0 && h > 0) return w < h ? w : h;
        }
      }
    } catch (_) {}
    return null;
  }

  /// A copy of [s] with every absolute-pixel value scaled by [k] — the text PNG
  /// is rasterised at the ORIGINAL's resolution, not the preview's, so it stays
  /// crisp and the same relative size the user saw.
  static SubtitleSegment _scaled(SubtitleSegment s, double k) => s.copy()
    ..fontSize = s.fontSize * k
    ..strokeWidth = s.strokeWidth * k
    ..letterSpacing = s.letterSpacing * k;

  /// [sourcePath] overrides the project's base clip (the editor authors on the
  /// 720p preview; export supplies the full-res original fetched just for the
  /// render). Coordinates are fractions and survive the swap; pixel sizes are
  /// scaled by the probed short-edge ratio.
  Future<ExportResult> export(EditorProject p, {void Function(double)? onProgress, String? sourcePath}) async {
    _cancelRequested = false;
    _cancelWait = Completer<void>();
    final off = p.trimStart;
    final src = sourcePath ?? p.baseClipPath;
    double k = 1.0;
    if (p.authoredShort > 0) {
      final short = await _shortEdge(src);
      if (short != null && short > 0) k = short / p.authoredShort;
    }

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
      textPaths.add(await TextRenderService.renderToPng(k == 1.0 ? s : _scaled(s, k), i));
    }
    final hasLogo = p.logoPath != null && !p.logoHidden && File(p.logoPath!).existsSync();
    final stickers = p.stickers.where((s) => !s.hidden && inWindow(s.start, s.end) && File(s.path).existsSync()).toList();

    // Where the video sits in the frame is resolved by VideoGeometry, which the
    // editor preview reads from as well. The preview and this filtergraph cannot
    // drift apart on scale or pan any more, because neither one works them out.
    final geo = VideoGeometry.resolve(
      aspectRatio: p.aspect.ratio,
      scale: p.videoScale,
      dx: p.videoDx,
      dy: p.videoDy,
      fitContain: p.videoFitContain,
      bgColor: p.videoBgColor,
    );
    final cropFilter = geo.filterChain();
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
    parts.addAll(['-i', src]);
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
    // Both output dims MUST be even for libx264/yuv420p. The long edge uses -2
    // (auto-even); the short edge is even-rounded too — a scale-down pad can make
    // the short edge odd (iw/vz), which otherwise aborts the encode.
    fc.write("[$cur]scale=w='if(gt(iw\\,ih)\\,-2\\,2*floor(min($shortEdge\\,iw)/2))':"
        "h='if(gt(iw\\,ih)\\,2*floor(min($shortEdge\\,ih)/2)\\,-2)':flags=bicubic[vout]");

    // ---- audio: the clip's own audio only (music feature removed per client) ----
    const audioMap = '0:a?'; // passthrough original (silent if the clip has none)

    parts.addAll(['-filter_complex', fc.toString(), '-map', '[vout]', '-map', audioMap]);
    // Cap to the intended clip length.
    parts.addAll(['-t', _f(p.outDuration, 3)]);
    // Hand the encode to the phone's video chip where that is possible, and
    // fall back to the CPU where it is not. The fallback is not a rare path to
    // be ignored: emulators and some older devices have no usable encoder.
    // Everything above describes the picture; what follows is only how it is
    // encoded, which is why the two can be retried independently.
    final common = <String>[
      '-r', '${p.fps}',
      '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-shortest',
    ];
    List<String> encoder(bool hw) => hw
        ? ['-c:v', 'h264_mediacodec', '-b:v', _hwBitrate(p.resolution.shortEdge)]
        // crf 18 is visually lossless; medium trades a little speed for size.
        : ['-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-profile:v', 'high', '-level', '4.1'];

    // Total output frames (for honest progress from FFmpeg statistics).
    final totalFrames = (p.outDuration * p.fps).round().clamp(1, 1 << 30);

    /// Runs one encode. Returns null on success, or the encoder's log.
    Future<String?> run(bool hw) async {
      // Run async so the Statistics callback fires; await via a Completer.
      final done = Completer<void>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        [...parts, ...encoder(hw), ...common, output],
        (_) => done.complete(),
        (_) {},
        (Statistics stats) {
          if (onProgress != null) {
            final frame = stats.getVideoFrameNumber();
            if (frame > 0) onProgress((frame / totalFrames).clamp(0.0, 0.999));
          }
        },
      );
      await _until(done);
      final rc = _cancelRequested ? null : await session.getReturnCode();
      if (_cancelRequested || ReturnCode.isCancel(rc)) {
        // leave nothing half-written behind for My Clips to find
        try { File(output).deleteSync(); } catch (_) {}
        throw const ExportCancelled();
      }
      if (ReturnCode.isSuccess(rc)) return null;
      // the graph that failed, in one piece — reconstructing it from the
      // project afterwards is guesswork, and guesswork is what cost the time
      debugPrint('[export] args: ${[...parts, ...encoder(hw), ...common, output].join(' ')}');
      return 'rc=$rc\n${await session.getAllLogsAsString() ?? ''}';
    }

    // The probe proves the device HAS a MediaCodec encoder, not that it will
    // accept these frames. When it balks, fall back instead of losing a render
    // the CPU path can finish.
    var failure = await run(await _hardwareEncodeWorks());
    if (failure != null && _hwEncode == true) {
      debugPrint('[export] hardware encode refused the render; retrying on CPU');
      _logTail(failure);
      _hwEncode = false; // do not pay for that attempt twice in one session
      onProgress?.call(0);
      failure = await run(false);
    }
    // a stop that arrived between the encode finishing and the work below
    if (_cancelRequested) {
      try { File(output).deleteSync(); } catch (_) {}
      throw const ExportCancelled();
    }
    if (failure != null) {
      _logTail(failure);
      throw const ExportFailure(
          'Could not finish the video on this phone. Try 720p, or close other apps and export again.');
    }

    // Write a poster-frame thumbnail sidecar (same name, .jpg) so the Exports tab
    // can show what each video is — no extra plugin, just one FFmpeg still grab.
    try {
      final thumb = output.replaceAll('.mp4', '.jpg');
      final tParts = ['-y', '-ss', '0.5', '-i', output, '-frames:v', '1', '-q:v', '3', thumb];
      final tDone = Completer<void>();
      await FFmpegKit.executeWithArgumentsAsync(tParts, (_) => tDone.complete());
      await _until(tDone);
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
}
