// Smoke test: the animation-preset math is pure and deterministic, so we can
// verify it without a device. Keeps `flutter analyze`/`flutter test` green.

import 'package:flutter_test/flutter_test.dart';

import 'package:clipcart/models/editor_state.dart';

void main() {
  test('computeAnim: none is identity', () {
    final f = computeAnim(OverlayAnim.none, 1.0, 0.0, 3.0);
    expect(f.opacity, 1.0);
    expect(f.scale, 1.0);
    expect(f.ox, 0.0);
    expect(f.oy, 0.0);
  });

  test('computeAnim: fade ramps opacity in at the start', () {
    final atStart = computeAnim(OverlayAnim.fade, 0.0, 0.0, 3.0);
    final settled = computeAnim(OverlayAnim.fade, 1.0, 0.0, 3.0);
    expect(atStart.opacity, lessThan(settled.opacity));
    expect(settled.opacity, closeTo(1.0, 0.001));
  });

  test('computeAnim: pop overshoots scale then settles', () {
    // easeOutBack overshoots past 1.0 in the later part of the entry window.
    // in-duration = min(0.5, dur*0.5) = 0.5s here, so t≈0.42 → tin≈0.84.
    final mid = computeAnim(OverlayAnim.popIn, 0.42, 0.0, 3.0);
    expect(mid.scale, greaterThan(1.0));
    final settled = computeAnim(OverlayAnim.popIn, 1.5, 0.0, 3.0);
    expect(settled.scale, closeTo(1.0, 0.001)); // back to normal after entry
  });

  test('SubtitleSegment json round-trips animation + fade', () {
    final s = SubtitleSegment(text: 'hi', start: 1, end: 4, anim: OverlayAnim.bounce, fadeIn: 0.5)
        .copy();
    final j = s.toJson();
    final back = SubtitleSegment.fromJson(j);
    expect(back.anim, OverlayAnim.bounce);
    expect(back.fadeIn, 0.5);
    expect(back.text, 'hi');
  });

  test('a caption remembers which line it was put on', () {
    // Undo, duplicate and reopening a draft all go through copy() and json.
    // Losing the line there drops a second speaker's captions back into the
    // first speaker's row, silently, some time after the author set them.
    final s = SubtitleSegment(text: 'reply', start: 2, end: 5, line: 2);
    expect(s.copy().line, 2);
    expect(SubtitleSegment.fromJson(s.toJson()).line, 2);
  });

  test('a caption written before lines existed reads as line 1', () {
    final j = SubtitleSegment(text: 'old', start: 0, end: 1).toJson()..remove('ln');
    expect(SubtitleSegment.fromJson(j).line, 0);
  });
}
