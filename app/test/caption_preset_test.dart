import 'package:clipcart/models/caption_preset.dart';
import 'package:clipcart/models/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A caption wearing a loud look, to apply presets over.
SubtitleSegment _loud() => SubtitleSegment(
      text: 'hi',
      start: 0,
      end: 2,
      fontFamily: 'Bungee',
      fontSize: 90,
      color: 0xFFFF0000,
      bold: false,
      italic: true,
      align: TextAlignH.right,
      letterSpacing: 9,
      lineHeight: 2.2,
      strokeWidth: 12,
      strokeColor: 0xFF00FF00,
      bgEnabled: true,
      bgColor: 0xFF0000FF,
      shadow: true,
      shadowColor: 0xFF123456,
      shadowOpacity: 0.3,
      shadowBlur: 0.9,
      shadowDistance: 19,
      shadowAngle: 170,
      opacity: 0.4,
      anim: OverlayAnim.shake,
      fadeIn: 1.5,
      fadeOut: 1.5,
    );

void main() {
  group('a preset is a complete look', () {
    test('applying one leaves nothing of what was there before', () {
      // This is the whole reason the preset model exists: the five-field
      // presets it replaces let a stroke or a shadow survive into the next
      // look, so two captions given the same preset did not match.
      const p = CaptionPreset(name: 'Plain', font: 'Inter');
      final a = _loud();
      final b = SubtitleSegment(text: 'other', start: 5, end: 9);
      p.applyTo(a);
      p.applyTo(b);

      for (final s in [a, b]) {
        expect(s.fontFamily, 'Inter');
        expect(s.fontSize, 44);
        expect(s.color, 0xFFFFFFFF);
        expect(s.bold, isTrue);
        expect(s.italic, isFalse);
        expect(s.align, TextAlignH.center);
        expect(s.letterSpacing, 0);
        expect(s.lineHeight, 1.15);
        expect(s.strokeWidth, 0);
        expect(s.bgEnabled, isFalse);
        expect(s.shadow, isFalse);
        expect(s.shadowDistance, 0);
        expect(s.opacity, 1);
        expect(s.anim, OverlayAnim.none);
        expect(s.fadeIn, 0);
      }
    });

    test('what a preset does not touch: the words, the timing, the line', () {
      final s = _loud()..line = 3;
      const CaptionPreset(name: 'Plain').applyTo(s);
      expect(s.text, 'hi');
      expect(s.start, 0);
      expect(s.end, 2);
      expect(s.line, 3);
    });

    test('a caption can be kept as a preset and put back on unchanged', () {
      final s = _loud();
      final saved = CaptionPreset.fromSegment('Mine', s);
      expect(saved.custom, isTrue);

      final other = SubtitleSegment(text: 'x', start: 0, end: 1);
      saved.applyTo(other);
      expect(other.fontSize, s.fontSize);
      expect(other.color, s.color);
      expect(other.align, s.align);
      expect(other.shadowAngle, s.shadowAngle);
      expect(other.anim, s.anim);
      expect(other.fadeOut, s.fadeOut);
    });
  });

  group('the shape the server and the admin speak', () {
    test('a preset survives the round trip', () {
      final s = _loud();
      final before = CaptionPreset.fromSegment('Round', s);
      final after = CaptionPreset.fromJson(before.toJson());
      expect(after.toJson(), before.toJson());
    });

    test('colours are written as #AARRGGBB and read back either way', () {
      final j = const CaptionPreset(name: 'C', color: 0x80FF8800).toJson();
      expect(j['color'], '#80FF8800');
      expect(CaptionPreset.fromJson({'name': 'C', 'color': '#80FF8800'}).color, 0x80FF8800);
      // what an admin is likely to type by hand
      expect(CaptionPreset.fromJson({'name': 'C', 'color': 'FF8800'}).color, 0xFFFF8800);
      expect(CaptionPreset.fromJson({'name': 'C', 'color': '0xFF112233'}).color, 0xFF112233);
    });

    test('a preset saved with a field missing is still usable', () {
      // An editor must not throw in the middle of a session because a key it
      // wanted was not in what the server sent.
      final p = CaptionPreset.fromJson({'name': 'Sparse'});
      expect(p.fontSize, 44);
      expect(p.anim, OverlayAnim.none);
      expect(p.align, TextAlignH.center);
    });

    test('a value the app does not recognise falls back rather than throwing', () {
      final p = CaptionPreset.fromJson({'name': 'Odd', 'anim': 'explode', 'align': 'middle'});
      expect(p.anim, OverlayAnim.none);
      expect(p.align, TextAlignH.center);
    });

    test('a preset with no name is still called something', () {
      expect(CaptionPreset.fromJson({'name': '   '}).name, 'Preset');
    });
  });

  test('what ships with the app is a usable list', () {
    expect(CaptionPreset.bundled.length, greaterThan(5));
    final names = CaptionPreset.bundled.map((p) => p.name.toLowerCase()).toList();
    expect(names.toSet().length, names.length, reason: 'two bundled presets share a name');
    for (final p in CaptionPreset.bundled) {
      expect(p.name.trim(), isNotEmpty);
      expect(p.custom, isFalse, reason: '${p.name} is not somebody\'s own save');
    }
  });
}
