// The timeline's arithmetic, pinned without a phone in the loop.
//
// What made the old timeline feel like a toy was not its looks: it fitted the
// whole clip into the screen's width, so precision was impossible. These tests
// hold the rules that replace that — a zoom the user controls, a ruler that
// stays readable at every zoom, and snapping measured in pixels so it feels the
// same whether you are looking at ten seconds or ten minutes.

import 'package:clipcart/features/editor/timeline_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zoom', () {
    test('is held inside limits a fingertip can use', () {
      expect(TimelineScale(0.0001).zoom, TimelineScale.minZoom);
      expect(TimelineScale(999).zoom, TimelineScale.maxZoom);
      expect(TimelineScale(2).zoom, 2);
    });

    test('a pinch multiplies, and cannot escape the limits', () {
      expect(TimelineScale(1).scaled(2).zoom, 2);
      expect(TimelineScale(1).scaled(0.5).zoom, 0.5);
      expect(TimelineScale(4).scaled(100).zoom, TimelineScale.maxZoom);
    });

    test('fit puts the whole clip on screen exactly once', () {
      final s = TimelineScale.fit(47, 360);
      expect(s.contentWidth(47), closeTo(360, 0.01));
    });

    test('fit survives a clip with no duration yet', () {
      expect(() => TimelineScale.fit(0, 360), returnsNormally);
      expect(TimelineScale.fit(0, 360).zoom, 1);
    });
  });

  group('time to pixels', () {
    test('round-trips', () {
      final s = TimelineScale(1.7);
      expect(s.secondsOf(s.xOf(12.345)), closeTo(12.345, 1e-9));
    });

    test('zooming in spreads the same second over more pixels', () {
      expect(TimelineScale(2).xOf(1), TimelineScale(1).xOf(1) * 2);
    });

    test('the old fit-to-width problem is what zoom exists to solve', () {
      // a 47s clip across a 360px phone: seven pixels a second, which is why
      // nothing could be placed accurately
      expect(TimelineScale.fit(47, 360).pps, lessThan(10));
      // zoomed in, a 30fps frame is wide enough to aim at
      expect(TimelineScale(TimelineScale.maxZoom).pps / 30, greaterThan(3));
    });
  });

  group('snapping', () {
    test('pulls onto a nearby landmark', () {
      final s = TimelineScale(1);
      final near = s.secondsOf(TimelineScale.snapPx - 2);
      expect(s.snap(5 + near, const [5]), 5);
    });

    test('leaves a value that is not near anything alone', () {
      final s = TimelineScale(1);
      final far = s.secondsOf(TimelineScale.snapPx + 5);
      expect(s.snap(5 + far, const [5]), 5 + far);
    });

    test('chooses the closest landmark when several are in reach', () {
      final s = TimelineScale(1);
      expect(s.snap(5.0, const [4.9, 5.05, 5.4]), 5.05);
    });

    test('the pull is the same distance on screen at every zoom', () {
      // in seconds the tolerance shrinks as you zoom in, which is the point:
      // it always feels like the same few pixels under the finger
      final out = TimelineScale(0.5), inn = TimelineScale(4);
      expect(out.secondsOf(TimelineScale.snapPx),
          greaterThan(inn.secondsOf(TimelineScale.snapPx)));
      expect(out.xOf(out.secondsOf(TimelineScale.snapPx)),
          closeTo(inn.xOf(inn.secondsOf(TimelineScale.snapPx)), 1e-9));
    });

    test('says when it would snap, so the guide and the haptic agree', () {
      final s = TimelineScale(1);
      expect(s.wouldSnap(5.02, const [5]), isTrue);
      expect(s.wouldSnap(9.0, const [5]), isFalse);
    });

    test('no landmarks means nothing moves', () {
      expect(TimelineScale(1).snap(3.3, const []), 3.3);
    });
  });

  group('ruler', () {
    test('ticks stay far enough apart to read at any zoom', () {
      for (final z in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]) {
        final s = TimelineScale(z);
        expect(s.tickStep() * s.pps, greaterThanOrEqualTo(56),
            reason: 'zoom $z crowds its labels');
      }
    });

    test('zooming in asks for a finer step, never a coarser one', () {
      var prev = double.infinity;
      for (final z in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]) {
        final step = TimelineScale(z).tickStep();
        expect(step, lessThanOrEqualTo(prev));
        prev = step;
      }
    });

    test('steps are numbers a person reads as time', () {
      const human = <double>[0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
      for (final z in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]) {
        expect(human.contains(TimelineScale(z).tickStep()), isTrue);
      }
    });
  });

  group('packRows — layers of one kind share a track', () {
    test('captions that never coincide all sit on one row', () {
      expect(packRows([(0, 2), (2, 4), (4, 6.5), (7, 9)]),
          [0, 0, 0, 0]);
    });

    test('touching exactly is not overlapping', () {
      // one ends where the next begins: a cut, not two captions at once
      expect(packRows([(0, 3), (3, 6)]), [0, 0]);
    });

    test('a real overlap costs a second row, and only the overlap does', () {
      //  a ──────
      //     b ──────        (overlaps a)
      //              c ──   (clear of both)
      expect(packRows([(0, 4), (2, 6), (7, 9)]), [0, 1, 0]);
    });

    test('rows are reused as soon as they are free', () {
      expect(packRows([(0, 5), (1, 2), (3, 4)]), [0, 1, 1]);
    });

    test('three at once need three rows', () {
      expect(packRows([(0, 9), (1, 9), (2, 9)]), [0, 1, 2]);
    });

    test('the answer does not depend on the order they were written in', () {
      expect(packRows([(7, 9), (0, 4), (2, 6)]), [0, 0, 1]);
    });

    test('nothing to place is no rows', () {
      expect(packRows([]), isEmpty);
    });
  });
}
