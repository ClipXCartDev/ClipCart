/// The single source of truth for how the video sits inside the export frame.
///
/// The preview and the export are two different renderers — Flutter widgets on
/// screen, an FFmpeg filtergraph on disk — and the spec requires they agree:
/// "Canvas is WYSIWYG — the preview is the export." They used to agree only
/// because the same rules were written out twice, in two languages, with a
/// duplicated overscan constant and a comment asking the next reader to keep
/// them in step. That is a promise, not a guarantee, and it has broken before.
///
/// Both renderers now take their numbers from here. The two backends still draw
/// differently — that is unavoidable — but they can no longer disagree about
/// *what* to draw, because neither one computes the scale or the pan itself.
library;

/// Cover-crop overscan. A hair of zoom on a cover-crop hides the 1px seam that
/// otherwise shows on the frame edge after an aspect change. Defined once:
/// if this ever changes, both renderers move together or neither does.
const double kVideoOverscan = 1.012;

/// Hard limits on the user's zoom, matching the editor's pinch clamp.
const double kMinVideoScale = 0.25;
const double kMaxVideoScale = 4.0;

/// How the video is placed in the frame. The branch is named once here so the
/// preview and the filtergraph can never pick different branches for the same
/// project.
/// How far inside the picture the app's mark sits, as a fraction of the
/// picture's own width and height. Free exports carry it; a plan removes it.
const double kWatermarkInset = 0.10;

enum VideoFitMode {
  /// Letterboxed onto a background fill of the target aspect.
  contain,

  /// Cover-cropped to the target aspect, then zoomed in.
  fillZoom,

  /// Cover-cropped to the target aspect, then shrunk and padded.
  fillShrink,

  /// Source aspect kept, shrunk and padded back to source size.
  originalShrink,

  /// Source aspect kept, zoomed and/or panned inside the native frame.
  originalZoom,

  /// Source aspect, no zoom, no pan — nothing to do.
  passthrough,
}

/// Resolved placement of the video inside its frame.
///
/// Construct with [VideoGeometry.resolve] and read [effectiveScale], [panX] and
/// [panY] for the preview, or [filterChain] for the export. Every one of those
/// is derived from the same four inputs, so there is no second opinion.
class VideoGeometry {
  const VideoGeometry._({
    required this.aspectRatio,
    required this.scale,
    required this.panX,
    required this.panY,
    required this.contain,
    required this.bgColor,
    required this.mode,
  });

  /// Target aspect, or null to keep the source's own.
  final double? aspectRatio;

  /// The user's zoom, already clamped. Below 1 shrinks and pads; above 1 zooms.
  final double scale;

  /// Pan as a fraction of the OUTPUT frame, already clamped to what the current
  /// zoom can actually travel. Positive x moves the picture right.
  final double panX;
  final double panY;

  /// Letterbox instead of cover-crop.
  final bool contain;

  /// ARGB fill shown wherever the video does not cover the frame.
  final int bgColor;

  final VideoFitMode mode;

  /// Resolve a project's raw fields into a placement both renderers can use.
  ///
  /// Clamping happens here and only here: a caller that passes an out-of-range
  /// zoom or a pan beyond the travel limit gets the same correction the other
  /// renderer would have applied.
  factory VideoGeometry.resolve({
    required double? aspectRatio,
    required double scale,
    required double dx,
    required double dy,
    required bool fitContain,
    required int bgColor,
  }) {
    final s = scale.clamp(kMinVideoScale, kMaxVideoScale).toDouble();
    final lim = panLimitFor(s);
    final cropped = aspectRatio != null;

    final VideoFitMode mode;
    if (cropped && fitContain) {
      mode = VideoFitMode.contain;
    } else if (cropped) {
      mode = s < 1.0 ? VideoFitMode.fillShrink : VideoFitMode.fillZoom;
    } else if (s < 1.0) {
      mode = VideoFitMode.originalShrink;
    } else if (s > 1.001 || dx.abs() > 0.001 || dy.abs() > 0.001) {
      mode = VideoFitMode.originalZoom;
    } else {
      mode = VideoFitMode.passthrough;
    }

    return VideoGeometry._(
      aspectRatio: aspectRatio,
      scale: s,
      panX: dx.clamp(-lim, lim).toDouble(),
      panY: dy.clamp(-lim, lim).toDouble(),
      contain: fitContain,
      bgColor: bgColor,
      mode: mode,
    );
  }

  /// How far the picture can travel before it pulls away from the frame edge.
  /// Zoomed in, that is the cropped-away margin; shrunk, it is the empty gap.
  static double panLimitFor(double scale) {
    final s = scale.clamp(kMinVideoScale, kMaxVideoScale).toDouble();
    return (s >= 1.0 ? (1 - 1 / s) / 2 : (1 - s) / 2).clamp(0.0, 0.5).toDouble();
  }

  /// The zoom actually applied to pixels, overscan included.
  ///
  /// This is what the preview scales by and what the filtergraph scales by;
  /// reading it from one place is the whole point of this class.
  double get effectiveScale =>
      mode == VideoFitMode.fillZoom ? scale * kVideoOverscan : scale;

  /// Pan in output pixels, for a frame of [width] × [height]. The preview
  /// translates by exactly this; the filtergraph shifts its pad/crop origin by
  /// the same fraction of its own output box.
  double panPixelsX(double width) => panX * width;
  double panPixelsY(double height) => panY * height;

  /// Where the picture actually sits inside the output frame, as fractions of
  /// that frame.
  ///
  /// A mark that is "10% in from the edge" has to be 10% in from the edge of
  /// the *picture*. Letterboxed, the frame's edge is a bar the picture never
  /// reaches, so measuring from it would float the mark off the video
  /// entirely. Both renderers ask this so they agree on where the picture is.
  ///
  /// [sourceAspect] is the clip's own width over height.
  ({double left, double top, double width, double height}) contentRect(
      double sourceAspect) {
    final src = sourceAspect > 0 ? sourceAspect : 16 / 9;
    final out = aspectRatio ?? src;
    double w, h;
    switch (mode) {
      case VideoFitMode.contain:
        // boxed into the target aspect: whichever side runs out first leaves
        // the bar on the other
        if (src > out) {
          w = 1.0;
          h = out / src;
        } else {
          w = src / out;
          h = 1.0;
        }
        // then the zoom, which in this mode pads below 1 and crops above it
        if (scale < 1.0) {
          w *= scale;
          h *= scale;
        } else if (scale > 1.0) {
          w = w * scale > 1 ? 1.0 : w * scale;
          h = h * scale > 1 ? 1.0 : h * scale;
        }
      case VideoFitMode.fillShrink:
      case VideoFitMode.originalShrink:
        // cover-cropped to the frame first, so the only gap is the shrink
        w = scale;
        h = scale;
      case VideoFitMode.fillZoom:
      case VideoFitMode.originalZoom:
      case VideoFitMode.passthrough:
        w = 1.0;
        h = 1.0;
    }
    final left = ((1 - w) / 2 + panX).clamp(0.0, 1.0).toDouble();
    final top = ((1 - h) / 2 + panY).clamp(0.0, 1.0).toDouble();
    return (
      left: left,
      top: top,
      width: w.clamp(0.0, 1 - left).toDouble(),
      height: h.clamp(0.0, 1 - top).toDouble(),
    );
  }

  /// The FFmpeg filter chain that places the source in the frame.
  ///
  /// Returns a chain with no leading or trailing comma, ready to sit between
  /// `[0:v]` and its output label. Commas inside filter arguments are escaped
  /// for the filtergraph, as FFmpeg requires.
  String filterChain() {
    final ar = aspectRatio;
    final vz = scale;
    final ez = effectiveScale;
    final bg = ffmpegColor(bgColor);
    final px = _n(panX), py = _n(panY);

    switch (mode) {
      case VideoFitMode.contain:
        // Box the SOURCE into the target aspect first, at its native size. The
        // box must not depend on the zoom: derived from the scaled video it
        // grew in step with the zoom, so the export never zoomed at all, and at
        // some zooms it came out smaller than its own input, which FFmpeg
        // refuses and the render died on.
        final box = "pad=w='max(iw\\,ih*${_n(ar!)})':h='max(iw\\,ih*${_n(ar)})/${_n(ar)}'"
            ":x='(ow-iw)/2':y='(oh-ih)/2':color=$bg,setsar=1";
        // Then zoom that boxed frame, exactly as the preview scales the video
        // inside a fixed frame. The fill is flat, so scaling it along with the
        // video and trimming back is indistinguishable from scaling the video
        // alone. Pan is a fraction of the FULL output box - matching the
        // preview's translate - not of the empty slack, which would under-pan.
        if (vz < 1.0) {
          return "$box,scale=iw*${_n(vz)}:ih*${_n(vz)}"
              ",pad=w=iw/${_n(vz)}:h=ih/${_n(vz)}"
              ":x='(ow-iw)/2+ow*$px':y='(oh-ih)/2+oh*$py':color=$bg";
        }
        if (vz > 1.0 || panX != 0 || panY != 0) {
          return "$box,scale=iw*${_n(vz)}:ih*${_n(vz)}"
              ",crop=iw/${_n(vz)}:ih/${_n(vz)}"
              ":'(iw-ow)/2-ow*$px':'(ih-oh)/2-oh*$py'";
        }
        return box;

      case VideoFitMode.fillShrink:
        // Cover-crop to the aspect, shrink, then pad back out to the box.
        return "crop='min(iw\\,ih*${_n(ar!)})':'min(ih\\,iw/${_n(ar)})'"
            ",scale=iw*${_n(vz)}:ih*${_n(vz)}"
            ",pad=w=iw/${_n(vz)}:h=ih/${_n(vz)}"
            ":x='(ow-iw)/2+ow*$px':y='(oh-ih)/2+oh*$py':color=$bg,setsar=1";

      case VideoFitMode.fillZoom:
        // Cover-crop, scale up (with overscan), then re-crop to the box at the
        // panned offset. A larger crop origin shows content further right, so
        // the offset is subtracted to move the picture the way the pan reads.
        return "crop='min(iw\\,ih*${_n(ar!)})':'min(ih\\,iw/${_n(ar)})'"
            ",scale=iw*${_n(ez)}:ih*${_n(ez)}"
            ",crop=iw/${_n(ez)}:ih/${_n(ez)}"
            ":'(iw-ow)/2-ow*$px':'(ih-oh)/2-oh*$py',setsar=1";

      case VideoFitMode.originalShrink:
        return "scale=iw*${_n(vz)}:ih*${_n(vz)}"
            ",pad=w=iw/${_n(vz)}:h=ih/${_n(vz)}"
            ":x='(ow-iw)/2+ow*$px':y='(oh-ih)/2+oh*$py':color=$bg,setsar=1";

      case VideoFitMode.originalZoom:
        // No overscan on the source's own aspect: there is no crop seam to hide.
        return "scale=iw*${_n(vz)}:ih*${_n(vz)}"
            ",crop=iw/${_n(vz)}:ih/${_n(vz)}"
            ":'(iw-ow)/2-ow*$px':'(ih-oh)/2-oh*$py',setsar=1";

      case VideoFitMode.passthrough:
        return 'null';
    }
  }

  /// ARGB int to an FFmpeg colour literal. Alpha is dropped: a pad fill is
  /// opaque by definition.
  static String ffmpegColor(int argb) =>
      '0x${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static String _n(num v) => v.toStringAsFixed(4);
}
