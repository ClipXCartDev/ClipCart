import 'package:flutter/widgets.dart';

/// A colour grade — a "look" — written down once for both renderers.
///
/// The editor previews a look with a Flutter colour matrix and the export
/// bakes it in with an FFmpeg chain. Those are different pieces of maths, and
/// the only way they can be trusted to agree is for both to be generated from
/// the same four numbers, in the same order, from this one file. Writing a look
/// out twice is how a preview starts lying about the finished video.
///
/// The four knobs are the ones that actually carry a look on phone footage:
/// warmth, contrast, brightness and saturation. They are applied in that order
/// by both sides.
@immutable
class VideoLook {
  const VideoLook({
    required this.id,
    required this.label,
    this.warmth = 0,
    this.contrast = 1,
    this.brightness = 0,
    this.saturation = 1,
  });

  /// Stored in the project. Never shown, never translated.
  final String id;

  /// What the chip says.
  final String label;

  /// Positive pushes red up and blue down — the usual "warmer" slider.
  /// A plain per-channel gain, because that is expressible in both renderers
  /// exactly; FFmpeg's own colorbalance weights midtones and cannot be matched
  /// by a colour matrix.
  final double warmth;

  /// 1 leaves contrast alone. Pivots around mid-grey, as FFmpeg's eq does.
  final double contrast;

  /// Added after contrast, in 0..1 of full scale. FFmpeg's eq does the same.
  final double brightness;

  /// 0 is greyscale, 1 untouched. Luma weights below match the BT.709 the
  /// clips are encoded in, so this agrees with the chroma scaling eq performs
  /// in YUV rather than drifting from it.
  final double saturation;

  bool get isIdentity =>
      warmth == 0 && contrast == 1 && brightness == 0 && saturation == 1;

  // BT.709 luma, the same weights the YUV the clips live in is built from.
  static const double _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

  /// The look as a single 4x5 colour matrix, for the preview.
  ///
  /// Built by composing the same three steps the export chain performs, in the
  /// same order, rather than by hand-expanding the product — the expansion is
  /// where a preview quietly stops matching its export.
  List<double> get matrix {
    // warmth: a per-channel gain, matching colorchannelmixer
    final warm = <double>[
      1 + warmth, 0, 0, 0, 0,
      0, 1, 0, 0, 0,
      0, 0, 1 - warmth, 0, 0,
      0, 0, 0, 1, 0,
    ];
    // contrast about mid-grey then brightness, matching eq
    final off = 255 * (0.5 * (1 - contrast) + brightness);
    final tone = <double>[
      contrast, 0, 0, 0, off,
      0, contrast, 0, 0, off,
      0, 0, contrast, 0, off,
      0, 0, 0, 1, 0,
    ];
    // saturation towards BT.709 luma, matching eq's chroma scaling
    final s = saturation, d = 1 - saturation;
    final sat = <double>[
      d * _lr + s, d * _lg, d * _lb, 0, 0,
      d * _lr, d * _lg + s, d * _lb, 0, 0,
      d * _lr, d * _lg, d * _lb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return _compose(sat, _compose(tone, warm));
  }

  /// `a` applied after `b` — the product of two 4x5 colour matrices, each read
  /// as a 5x5 with an implicit [0,0,0,0,1] bottom row.
  static List<double> _compose(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += a[r * 5 + k] * b[k * 5 + c];
        }
        if (c == 4) v += a[r * 5 + 4]; // the implicit 1 in b's bottom row
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  /// The look as an FFmpeg filter chain, for the export.
  ///
  /// Returns null when the look changes nothing, so an untouched clip is never
  /// put through a colour pass it does not need.
  String? filterChain() {
    if (isIdentity) return null;
    final parts = <String>[];
    if (warmth != 0) {
      parts.add('colorchannelmixer=rr=${_n(1 + warmth)}:gg=1:bb=${_n(1 - warmth)}');
    }
    if (contrast != 1 || brightness != 0 || saturation != 1) {
      parts.add('eq=contrast=${_n(contrast)}'
          ':brightness=${_n(brightness)}'
          ':saturation=${_n(saturation)}');
    }
    return parts.join(',');
  }

  static String _n(double v) => v.toStringAsFixed(4);

  /// The looks offered in the editor, in the order they appear.
  ///
  /// Deliberately a short, usable set rather than a wall of thumbnails: each
  /// one has to be a look somebody would actually publish, and a customer
  /// picking from eight tries them all.
  static const List<VideoLook> all = [
    VideoLook(id: 'none', label: 'Original'),
    VideoLook(id: 'natural', label: 'Natural', contrast: 1.06, saturation: 1.08),
    VideoLook(id: 'vivid', label: 'Vivid', contrast: 1.14, saturation: 1.38),
    VideoLook(id: 'warm', label: 'Warm', warmth: 0.07, contrast: 1.05, saturation: 1.12),
    VideoLook(id: 'cool', label: 'Cool', warmth: -0.07, contrast: 1.06, saturation: 1.05),
    VideoLook(id: 'punch', label: 'Punch', contrast: 1.26, brightness: -0.02, saturation: 1.3),
    VideoLook(id: 'faded', label: 'Faded', warmth: 0.03, contrast: 0.88, brightness: 0.06, saturation: 0.82),
    VideoLook(id: 'mono', label: 'Mono', contrast: 1.1, saturation: 0),
  ];

  static const VideoLook none = VideoLook(id: 'none', label: 'Original');

  /// The look with this id, or [none] for an unknown or missing one — an old
  /// project, or one saved by a build that had a look this one does not.
  static VideoLook byId(String? id) {
    if (id == null) return none;
    for (final l in all) {
      if (l.id == id) return l;
    }
    return none;
  }
}
