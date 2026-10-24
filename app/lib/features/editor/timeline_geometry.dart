import 'dart:math' as math;

/// Where time sits on the timeline, and what a drag is allowed to land on.
///
/// The old timeline squeezed the whole clip into the screen's width, so a
/// 47-second clip gave about seven pixels per second: nothing could be placed
/// accurately, and no amount of tidy grouping made that feel like an editor.
/// A professional timeline is instead *longer than the screen* and zoomable —
/// the pixels-per-second is the thing the user controls.
///
/// This holds only the arithmetic, so the rules can be tested without a phone:
/// the widget that draws the tracks reads every position from here.
class TimelineScale {
  const TimelineScale._(this.zoom);

  /// Pixels per second at zoom 1 — a comfortable default where a 10-second
  /// clip fills roughly a phone width.
  static const double basePps = 38;

  /// The floor has to be low enough that [fit] can actually fit the content,
  /// or opening a clip starts part-way zoomed in with the end off-screen: a
  /// 47-second clip on a phone needs about 0.2, and a 10-minute one far less.
  /// Zoomed all the way in, a frame at 30fps is about ten pixels wide, which
  /// is as fine as a fingertip can usefully aim.
  static const double minZoom = 0.05;
  static const double maxZoom = 8.0;

  /// A drag snaps when it comes within this many pixels of a landmark. In
  /// pixels rather than seconds so it feels the same at every zoom.
  static const double snapPx = 10;

  final double zoom;

  factory TimelineScale([double zoom = 1.0]) =>
      TimelineScale._(zoom.clamp(minZoom, maxZoom).toDouble());

  /// Pixels per second at this zoom.
  double get pps => basePps * zoom;

  /// A zoom that is this one scaled by [factor], clamped — what a pinch gives.
  TimelineScale scaled(double factor) => TimelineScale(zoom * factor);

  /// The zoom at which [duration] exactly fills [width]. Used for "fit", and
  /// as the starting zoom so the clip is visible before the user touches it.
  static TimelineScale fit(double duration, double width) {
    if (duration <= 0 || width <= 0) return TimelineScale();
    return TimelineScale(width / duration / basePps);
  }

  double xOf(double seconds) => seconds * pps;

  double secondsOf(double x) => pps <= 0 ? 0 : x / pps;

  /// How wide the whole clip is at this zoom.
  double contentWidth(double duration) => math.max(0, duration) * pps;

  /// [seconds] pulled onto the nearest landmark within [snapPx], or left alone.
  ///
  /// Snapping is what stops a layer from ending three frames before the cut and
  /// makes edges line up without the user having to be precise. Landmarks come
  /// from the caller — the playhead, the clip's own ends, and the edges of
  /// every other layer.
  double snap(double seconds, Iterable<double> landmarks) {
    final tolerance = secondsOf(snapPx);
    double? best;
    var bestGap = double.infinity;
    for (final l in landmarks) {
      final gap = (l - seconds).abs();
      if (gap <= tolerance && gap < bestGap) {
        best = l;
        bestGap = gap;
      }
    }
    return best ?? seconds;
  }

  /// Whether [seconds] would snap — the widget uses this to show the guide
  /// line and fire the haptic exactly when the value is actually being moved.
  bool wouldSnap(double seconds, Iterable<double> landmarks) =>
      snap(seconds, landmarks) != seconds;

  /// How often to draw a ruler tick so the labels never collide: the smallest
  /// step from a human-readable set that is still at least [minGapPx] apart.
  ///
  /// Without this the ruler either crowds into unreadable mush when zoomed out
  /// or shows three lonely marks when zoomed in.
  double tickStep({double minGapPx = 56}) {
    const steps = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
    for (final s in steps) {
      if (s * pps >= minGapPx) return s.toDouble();
    }
    return steps.last.toDouble();
  }
}
