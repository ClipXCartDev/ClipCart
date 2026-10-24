// Guards the one rule the editor cannot be allowed to break: the preview and
// the export have to place the video identically. They are different renderers,
// so the only thing that can be tested here is that they are fed the same
// numbers — which is exactly what used to drift when the rules were written out
// twice.

import 'package:clipcart/models/video_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pull a numeric argument out of a built filter chain so the test reads what
/// FFmpeg would actually be told, not what we hoped we wrote.
double? _argAfter(String chain, String marker) {
  final i = chain.indexOf(marker);
  if (i < 0) return null;
  final m = RegExp(r'-?\d+\.?\d*').firstMatch(chain.substring(i + marker.length));
  return m == null ? null : double.parse(m.group(0)!);
}

VideoGeometry _geo({
  double? ar,
  double scale = 1.0,
  double dx = 0,
  double dy = 0,
  bool contain = false,
}) =>
    VideoGeometry.resolve(
      aspectRatio: ar,
      scale: scale,
      dx: dx,
      dy: dy,
      fitContain: contain,
      bgColor: 0xFF000000,
    );

void main() {
  group('mode selection', () {
    test('an untouched source clip does nothing at all', () {
      final g = _geo();
      expect(g.mode, VideoFitMode.passthrough);
      expect(g.filterChain(), 'null');
    });

    test('a cropped frame fills by default and letterboxes on request', () {
      expect(_geo(ar: 9 / 16, scale: 1.5).mode, VideoFitMode.fillZoom);
      expect(_geo(ar: 9 / 16, scale: 0.6).mode, VideoFitMode.fillShrink);
      expect(_geo(ar: 9 / 16, scale: 1.5, contain: true).mode, VideoFitMode.contain);
    });

    test('a pan alone is enough to stop being a passthrough', () {
      expect(_geo(dx: 0.1).mode, VideoFitMode.originalZoom);
      expect(_geo(scale: 0.8).mode, VideoFitMode.originalShrink);
    });
  });

  group('clamping is shared', () {
    test('zoom is held inside the pinch limits', () {
      expect(_geo(scale: 99).scale, kMaxVideoScale);
      expect(_geo(scale: 0.01).scale, kMinVideoScale);
    });

    test('pan cannot exceed the travel the zoom actually allows', () {
      // At 2x, half the frame is cropped away, so the picture can travel a
      // quarter of the frame before an edge pulls in.
      final g = _geo(ar: 9 / 16, scale: 2.0, dx: 0.9, dy: -0.9);
      expect(g.panX, closeTo(0.25, 1e-9));
      expect(g.panY, closeTo(-0.25, 1e-9));
    });

    test('an unzoomed frame has nowhere to pan', () {
      expect(VideoGeometry.panLimitFor(1.0), 0.0);
      expect(_geo(ar: 9 / 16, scale: 1.0, dx: 0.4).panX, 0.0);
    });

    test('a shrunk frame pans across its empty gap', () {
      expect(VideoGeometry.panLimitFor(0.5), closeTo(0.25, 1e-9));
    });
  });

  group('preview and filtergraph agree', () {
    test('both sides scale by the same number, overscan included', () {
      final g = _geo(ar: 9 / 16, scale: 2.0);
      expect(g.effectiveScale, closeTo(2.0 * kVideoOverscan, 1e-9));
      // the filtergraph's scale step must carry that same factor
      expect(_argAfter(g.filterChain(), 'scale=iw*'),
          closeTo(g.effectiveScale, 1e-4));
    });

    test('overscan applies only where there is a crop seam to hide', () {
      // letterboxing leaves no seam, and neither does the source's own aspect
      expect(_geo(ar: 9 / 16, scale: 2.0, contain: true).effectiveScale, 2.0);
      expect(_geo(scale: 2.0).effectiveScale, 2.0);
      // shrinking never overscans either
      expect(_geo(ar: 9 / 16, scale: 0.5).effectiveScale, 0.5);
    });

    test('the pan the preview translates by is the pan the chain shifts by', () {
      const frame = 1080.0;
      final g = _geo(ar: 9 / 16, scale: 2.0, dx: 0.1);
      expect(g.panPixelsX(frame), closeTo(0.1 * frame, 1e-9));
      // the second crop's x origin is offset by that same fraction
      expect(_argAfter(g.filterChain(), "-ow*"), closeTo(g.panX, 1e-4));
    });

    test('a clamped pan reaches the filtergraph already clamped', () {
      // the preview and the export must agree even when the user over-drags
      final g = _geo(ar: 9 / 16, scale: 2.0, dx: 5.0);
      expect(g.panX, closeTo(0.25, 1e-9));
      expect(_argAfter(g.filterChain(), "-ow*"), closeTo(0.25, 1e-4));
    });
  });

  group('filter chain shape', () {
    test('every mode sets the sample aspect so players do not stretch it', () {
      for (final g in [
        _geo(ar: 9 / 16, scale: 1.5),
        _geo(ar: 9 / 16, scale: 0.6),
        _geo(ar: 9 / 16, scale: 1.0, contain: true),
        _geo(scale: 0.6),
        _geo(scale: 1.5),
      ]) {
        expect(g.filterChain(), contains('setsar=1'), reason: '${g.mode}');
      }
    });

    test('commas inside filter arguments stay escaped', () {
      // an unescaped comma here would split the filtergraph and fail the render
      final chain = _geo(ar: 9 / 16, scale: 1.5).filterChain();
      expect(chain, contains('min(iw\\,'));
    });

    test('the background colour reaches the pad fill', () {
      final g = VideoGeometry.resolve(
        aspectRatio: 9 / 16,
        scale: 0.5,
        dx: 0,
        dy: 0,
        fitContain: false,
        bgColor: 0xFFFFFFFF,
      );
      expect(g.filterChain(), contains('color=0xffffff'));
    });
  });

  // A letterbox that sized its box from the already-zoomed video swallowed the
  // zoom whole (the export never zoomed while the preview did) and, once the
  // zoomed frame outgrew the box, made FFmpeg refuse the render outright.
  group('letterboxing survives the zoom', () {
    String contain(double scale) =>
        _geo(ar: 9 / 16, scale: scale, contain: true).filterChain();

    test('the box is measured before the zoom, not after', () {
      // the box must read the source's own size; a vz in the pad means the box
      // grows with the zoom and the zoom cancels itself out
      final pad = contain(1.5).split('pad=')[1].split(',setsar')[0];
      expect(pad, isNot(contains('1.5')));
    });

    test('zooming past the frame crops instead of padding', () {
      // pad cannot make a frame smaller than its input - FFmpeg errors - so the
      // overflow has to be cropped away
      expect(contain(1.5), contains('crop='));
      expect(contain(1.0184), contains('crop='));
    });

    test('zooming out still pads back to the frame', () {
      expect(contain(0.6), contains('pad=w=iw/0.6'));
      expect(contain(0.6), isNot(contains('crop=')));
    });

    test('an unzoomed letterbox is just the box', () {
      final c = contain(1.0);
      expect(c, isNot(contains('crop=')));
      expect(c, isNot(contains('scale=')));
    });
  });

  group('contentRect — where the picture is, for the mark that sits on it', () {
    VideoGeometry g({double? ar, double scale = 1, bool contain = false, double dx = 0, double dy = 0}) =>
        VideoGeometry.resolve(
            aspectRatio: ar, scale: scale, dx: dx, dy: dy, fitContain: contain, bgColor: 0xFF000000);

    test('untouched, the picture is the whole frame', () {
      final r = g().contentRect(9 / 16);
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, 1);
      expect(r.height, 1);
    });

    test('cover-cropped and zoomed in, it is still the whole frame', () {
      final r = g(ar: 1.0, scale: 2).contentRect(9 / 16);
      expect(r.width, 1);
      expect(r.height, 1);
    });

    test('letterboxed, the bars are not part of the picture', () {
      // a 16:9 clip in a 9:16 frame: full width, bars above and below
      final r = g(ar: 9 / 16, contain: true).contentRect(16 / 9);
      expect(r.width, closeTo(1, 1e-9));
      expect(r.height, closeTo((9 / 16) / (16 / 9), 1e-9));
      expect(r.top, closeTo((1 - r.height) / 2, 1e-9));
    });

    test('pillarboxed, the bars are on the sides', () {
      final r = g(ar: 16 / 9, contain: true).contentRect(9 / 16);
      expect(r.height, closeTo(1, 1e-9));
      expect(r.width, closeTo((9 / 16) / (16 / 9), 1e-9));
      expect(r.left, closeTo((1 - r.width) / 2, 1e-9));
    });

    test('shrunk, the picture is smaller and centred', () {
      final r = g(ar: 1.0, scale: 0.5).contentRect(1.0);
      expect(r.width, closeTo(0.5, 1e-9));
      expect(r.left, closeTo(0.25, 1e-9));
    });

    test('panned, the picture moves with it and never leaves the frame', () {
      final r = g(ar: 1.0, scale: 0.5, dx: 0.2).contentRect(1.0);
      expect(r.left, closeTo(0.45, 1e-9));
      expect(r.left + r.width, lessThanOrEqualTo(1.0));
    });

    test('a source with no aspect to speak of does not produce nonsense', () {
      final r = g(ar: 9 / 16, contain: true).contentRect(0);
      expect(r.width, inInclusiveRange(0, 1));
      expect(r.height, inInclusiveRange(0, 1));
    });
  });
}
