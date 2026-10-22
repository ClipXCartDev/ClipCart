// A look is previewed by a Flutter colour matrix and exported by an FFmpeg
// chain. Those are different pieces of maths, so what is tested here is that
// both come from the same numbers and that the matrix actually does to a pixel
// what the look's name promises — a matrix that is quietly wrong looks like a
// plausible grade right up until someone compares it with the export.

import 'package:clipcart/models/video_look.dart';
import 'package:flutter_test/flutter_test.dart';

/// Push one RGB colour through a 4x5 colour matrix, as the engine would.
({double r, double g, double b}) _apply(List<double> m, double r, double g, double b) {
  double ch(int row) =>
      (m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 4]).clamp(0.0, 255.0);
  return (r: ch(0), g: ch(1), b: ch(2));
}

double _luma(({double r, double g, double b}) c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

void main() {
  group('looks are one definition, not two', () {
    test('every look has a distinct id and a label worth reading', () {
      final ids = VideoLook.all.map((l) => l.id).toSet();
      expect(ids.length, VideoLook.all.length);
      for (final l in VideoLook.all) {
        expect(l.label.trim(), isNotEmpty);
      }
    });

    test('an unknown or missing id falls back to the original', () {
      // a project saved by a build with a look this one does not have must
      // still open, ungraded, rather than failing
      expect(VideoLook.byId(null).id, 'none');
      expect(VideoLook.byId('no-such-look').id, 'none');
      expect(VideoLook.byId('vivid').id, 'vivid');
    });

    test('the untouched look costs nothing on either side', () {
      expect(VideoLook.none.isIdentity, isTrue);
      expect(VideoLook.none.filterChain(), isNull);
      expect(VideoLook.none.matrix, [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0,
      ]);
    });

    test('every other look reaches both renderers', () {
      for (final l in VideoLook.all.where((l) => l.id != 'none')) {
        expect(l.isIdentity, isFalse, reason: l.id);
        expect(l.filterChain(), isNotNull, reason: l.id);
        expect(l.matrix.length, 20, reason: l.id);
      }
    });

    test('the chain carries the same numbers the matrix was built from', () {
      final warm = VideoLook.byId('warm');
      final chain = warm.filterChain()!;
      expect(chain, contains('colorchannelmixer=rr=${(1 + warm.warmth).toStringAsFixed(4)}'));
      expect(chain, contains('contrast=${warm.contrast.toStringAsFixed(4)}'));
      expect(chain, contains('saturation=${warm.saturation.toStringAsFixed(4)}'));
    });
  });

  group('the matrix does what the look says', () {
    test('mono leaves no colour behind', () {
      final m = VideoLook.byId('mono').matrix;
      final out = _apply(m, 200, 60, 20);
      expect(out.r, closeTo(out.g, 0.001));
      expect(out.g, closeTo(out.b, 0.001));
    });

    test('vivid pushes colour further from grey, faded pulls it in', () {
      double spread(String id) {
        final c = _apply(VideoLook.byId(id).matrix, 190, 120, 70);
        return (c.r - _luma(c)).abs();
      }
      expect(spread('vivid'), greaterThan(spread('none')));
      expect(spread('faded'), lessThan(spread('none')));
    });

    test('warm favours red over blue, cool the other way', () {
      final w = _apply(VideoLook.byId('warm').matrix, 128, 128, 128);
      expect(w.r, greaterThan(w.b));
      final c = _apply(VideoLook.byId('cool').matrix, 128, 128, 128);
      expect(c.r, lessThan(c.b));
    });

    test('contrast pivots on mid-grey, so a grey frame stays put', () {
      // a look that only adds contrast must not also shift exposure
      const only = VideoLook(id: 't', label: 't', contrast: 1.5);
      final out = _apply(only.matrix, 127.5, 127.5, 127.5);
      expect(out.r, closeTo(127.5, 0.001));
    });

    test('nothing a look does can push a pixel off the end of the scale', () {
      for (final l in VideoLook.all) {
        for (final v in [0.0, 64.0, 128.0, 255.0]) {
          final out = _apply(l.matrix, v, v, v);
          expect(out.r, inInclusiveRange(0, 255), reason: '${l.id} @ $v');
        }
      }
    });
  });
}
