// Layers saved before kinds existed carry no tag, and getting their kind wrong
// means a project's logo, handle, CTA and outro all reappear as plain Text. The
// inference only ever runs on that old data, so it has to be right the first
// time — there is no second chance once a project is saved back with a tag.

import 'package:clipcart/models/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pre-kind saved layer: the fields the old builds wrote, nothing more.
Map<String, dynamic> _legacy({
  String text = 'hello',
  double dx = 0.5,
  double dy = 0.82,
  int bgc = 0x80000000,
}) =>
    {
      't': text, 's': 0.0, 'e': 3.0, 'c': 0xFFFFFFFF, 'fs': 44.0,
      'dx': dx, 'dy': dy, 'bgc': bgc,
    };

String _kindOf(Map<String, dynamic> j) => SubtitleSegment.fromJson(j).kind;

void main() {
  group('an explicit tag always wins', () {
    test('a tagged layer is never re-inferred', () {
      // even when the shape would say otherwise
      final j = _legacy(dx: 0.20, dy: 0.07)..['k'] = 'cta';
      expect(_kindOf(j), 'cta');
    });

    test('a layer tagged plain text stays plain text', () {
      final j = _legacy(bgc: 0xFF0E9E6E)..['k'] = 'text';
      expect(_kindOf(j), 'text');
    });
  });

  group('recovering the kind of an untagged layer', () {
    test('the logo is known by its corner', () {
      expect(_kindOf(_legacy(text: '@yourpage', dx: 0.20, dy: 0.07)), 'logo');
    });

    test('a nudged logo is still a logo', () {
      // users move it; the match has to tolerate that without swallowing
      // unrelated layers that merely sit near the top left
      expect(_kindOf(_legacy(dx: 0.21, dy: 0.06)), 'logo');
      expect(_kindOf(_legacy(dx: 0.30, dy: 0.07)), 'text');
    });

    test('the CTA and outro are known by their backgrounds', () {
      expect(_kindOf(_legacy(bgc: 0xFF0E9E6E)), 'cta');
      expect(_kindOf(_legacy(bgc: 0xE60B0A0C)), 'outro');
    });

    test('the handle needs both its @ and its place at the bottom', () {
      expect(_kindOf(_legacy(text: '@yourhandle', dy: 0.93)), 'handle');
      // a caption that merely mentions someone is not a handle layer
      expect(_kindOf(_legacy(text: '@yourhandle', dy: 0.5)), 'text');
      expect(_kindOf(_legacy(text: 'bottom caption', dy: 0.93)), 'text');
    });

    test('anything else is a caption', () {
      expect(_kindOf(_legacy()), 'text');
    });
  });

  test('the tag survives a save and load', () {
    final s = SubtitleSegment(text: 'hi', start: 0, end: 2, kind: 'outro');
    expect(SubtitleSegment.fromJson(s.toJson()).kind, 'outro');
  });

  test('duplicating a layer keeps its kind', () {
    // a duplicated CTA that came back as Text would land in the wrong group
    final s = SubtitleSegment(text: 'Follow', start: 0, end: 2, kind: 'cta');
    expect(s.copy().kind, 'cta');
  });
}
