import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The frames drawn along the base video track.
///
/// The track used to be ten identical film icons, which told the user nothing
/// about their own clip — you could not see where the cut was, or which bit of
/// the shot you were trimming. Every editor that feels professional shows the
/// actual footage along the timeline, so this pulls real frames out of the clip.
///
/// Extraction is slow enough to matter (a second or two), so it never blocks
/// the editor opening: the strip renders as plain blocks until the frames
/// arrive, then fills in. The result is cached per clip, so reopening a draft
/// is instant.
class Filmstrip {
  const Filmstrip._(this.frames, this.interval, [this.aspect = 16 / 9]);

  /// Frame images in time order. Empty while extraction is still running, or
  /// if it failed — the timeline simply stays plain in that case.
  final List<File> frames;

  /// Seconds between consecutive frames, so a frame can be placed on the
  /// timeline without storing a timestamp per image.
  final double interval;

  /// Width over height of a frame. The strip draws its tiles at this shape, so
  /// a face stays a face instead of being cropped to a strip.
  final double aspect;

  static const empty = Filmstrip._(<File>[], 1);

  bool get isReady => frames.isNotEmpty;

  /// The frame to show for [seconds], or null when there is nothing yet.
  File? frameAt(double seconds) {
    if (frames.isEmpty) return null;
    final i = (seconds / interval).floor().clamp(0, frames.length - 1);
    return frames[i];
  }

  /// Roughly one frame per [targetCount] across the clip, capped so a long clip
  /// does not spend ages extracting images nobody will look at closely.
  static const int targetCount = 40;

  /// Height of each extracted frame. Small on purpose: these are thumbnails
  /// behind a 56-pixel track, and decoding forty large JPEGs on a phone to draw
  /// them two centimetres tall is wasted work.
  static const int frameHeight = 72;

  static final Map<String, Future<Filmstrip>> _inFlight = {};

  /// Frames for [videoPath], extracting them if they are not already cached.
  ///
  /// Calls for the same clip share one extraction — the timeline rebuilds
  /// often, and each rebuild must not start another FFmpeg run.
  static Future<Filmstrip> forClip(String videoPath, double duration) {
    final key = '$videoPath|${duration.toStringAsFixed(2)}';
    return _inFlight[key] ??= _extract(videoPath, duration)
      ..catchError((_) {
        _inFlight.remove(key);
        return empty;
      });
  }

  /// Throw away cached strips for clips that are no longer open. The editor
  /// calls this when it closes; without it the cache directory grows with every
  /// clip the user ever edited.
  static Future<void> purge({String? keepForPath}) async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/filmstrip');
      if (!dir.existsSync()) return;
      final keep = keepForPath == null ? null : _dirNameFor(keepForPath);
      for (final e in dir.listSync()) {
        if (keep != null && e.path.endsWith(keep)) continue;
        try {
          e.deleteSync(recursive: true);
        } catch (_) {/* in use; it will go next time */}
      }
      _inFlight.clear();
    } catch (_) {/* best effort */}
  }

  /// A stable folder name for a clip. Deliberately not a crypto hash: this
  /// only has to separate one cache folder from another, and that is not worth
  /// a dependency. Length is mixed in so two paths that collide on hashCode
  /// still get their own folder.
  static String _dirNameFor(String videoPath) =>
      '${videoPath.hashCode.toUnsigned(32).toRadixString(16)}_${videoPath.length}';

  static Future<Filmstrip> _extract(String videoPath, double duration) async {
    if (duration <= 0 || !File(videoPath).existsSync()) return empty;
    // one frame every `interval` seconds, never finer than about 4 per second
    final interval = (duration / targetCount).clamp(0.25, 60.0).toDouble();
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory('${root.path}/filmstrip/${_dirNameFor(videoPath)}');

      // already extracted for this clip
      if (dir.existsSync()) {
        final cached = _sortedFrames(dir);
        if (cached.isNotEmpty) {
          return Filmstrip._(cached, interval, await _aspectOf(videoPath));
        }
      }
      dir.createSync(recursive: true);

      final done = Completer<void>();
      final session = await FFmpegKit.executeWithArgumentsAsync([
        '-y', '-i', videoPath,
        // fps filter rather than -ss per frame: one pass over the file instead
        // of one seek-and-decode per thumbnail
        '-vf', 'fps=1/${interval.toStringAsFixed(4)},scale=-2:$frameHeight',
        '-q:v', '6',
        '${dir.path}/f_%04d.jpg',
      ], (_) => done.complete());
      await done.future;

      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        debugPrint('[filmstrip] extraction failed; the track stays plain');
        return empty;
      }
      return Filmstrip._(_sortedFrames(dir), interval, await _aspectOf(videoPath));
    } catch (e) {
      debugPrint('[filmstrip] $e');
      return empty;
    }
  }

  /// The source's shape. Falls back to 16:9, which is only ever used to lay
  /// out tiles, so a wrong guess costs a little cropping and nothing else.
  static Future<double> _aspectOf(String videoPath) async {
    try {
      final info = await FFprobeKit.getMediaInformation(videoPath);
      for (final st in info.getMediaInformation()?.getStreams() ?? const []) {
        if (st.getType() == 'video') {
          final w = st.getWidth(), h = st.getHeight();
          if (w != null && h != null && w > 0 && h > 0) return w / h;
        }
      }
    } catch (_) {/* the default is fine */}
    return 16 / 9;
  }

  static List<File> _sortedFrames(Directory dir) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }
}
