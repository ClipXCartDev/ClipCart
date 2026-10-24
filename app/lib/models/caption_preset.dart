import 'editor_state.dart';

/// A named caption look, complete.
///
/// The old presets set five fields and left the rest alone, so applying one
/// gave a different result depending on what the caption happened to look like
/// before — a stroke from the last preset survived into the next, and a set of
/// captions styled by the same tap did not match. A preset now carries every
/// value it decides, so applying it twice from different starting points lands
/// in the same place.
///
/// Placement is deliberately not here. A preset is how a caption looks, not
/// where it sits; one that moved the caption as well would be unusable on a
/// layout somebody had already arranged.
class CaptionPreset {
  const CaptionPreset({
    required this.name,
    this.font,
    this.fontSize = 44,
    this.color = 0xFFFFFFFF,
    this.bold = true,
    this.italic = false,
    this.align = TextAlignH.center,
    this.letterSpacing = 0,
    this.lineHeight = 1.15,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.bgEnabled = false,
    this.bgColor = 0x00000000,
    this.shadow = false,
    this.shadowColor = 0xFF000000,
    this.shadowOpacity = 1.0,
    this.shadowBlur = 0.5,
    this.shadowDistance = 0.0,
    this.shadowAngle = 45.0,
    this.opacity = 1.0,
    this.anim = OverlayAnim.none,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.custom = false,
  });

  final String name;

  /// Family name, resolved to a file on the device by the font service. Null
  /// means the app's own default face.
  final String? font;

  final double fontSize;
  final int color;
  final bool bold;
  final bool italic;
  final TextAlignH align;
  final double letterSpacing;
  final double lineHeight;
  final double strokeWidth;
  final int strokeColor;
  final bool bgEnabled;
  final int bgColor;
  final bool shadow;
  final int shadowColor;
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowDistance;
  final double shadowAngle;
  final double opacity;
  final OverlayAnim anim;
  final double fadeIn;
  final double fadeOut;

  /// Saved on this device by the person using it, rather than shipped or
  /// configured. Only these can be renamed or deleted from the app.
  final bool custom;

  /// Everything this preset decides, written onto [s].
  void applyTo(SubtitleSegment s, {String? fontPath}) {
    s
      ..fontFamily = font
      ..fontFilePath = fontPath
      ..fontSize = fontSize
      ..color = color
      ..bold = bold
      ..italic = italic
      ..align = align
      ..letterSpacing = letterSpacing
      ..lineHeight = lineHeight
      ..strokeWidth = strokeWidth
      ..strokeColor = strokeColor
      ..bgEnabled = bgEnabled
      ..bgColor = bgColor
      ..shadow = shadow
      ..shadowColor = shadowColor
      ..shadowOpacity = shadowOpacity
      ..shadowBlur = shadowBlur
      ..shadowDistance = shadowDistance
      ..shadowAngle = shadowAngle
      ..opacity = opacity
      ..anim = anim
      ..fadeIn = fadeIn
      ..fadeOut = fadeOut;
  }

  /// The look a caption currently has, as a preset somebody can name and keep.
  factory CaptionPreset.fromSegment(String name, SubtitleSegment s) => CaptionPreset(
        name: name,
        font: s.fontFamily,
        fontSize: s.fontSize,
        color: s.color,
        bold: s.bold,
        italic: s.italic,
        align: s.align,
        letterSpacing: s.letterSpacing,
        lineHeight: s.lineHeight,
        strokeWidth: s.strokeWidth,
        strokeColor: s.strokeColor,
        bgEnabled: s.bgEnabled,
        bgColor: s.bgColor,
        shadow: s.shadow,
        shadowColor: s.shadowColor,
        shadowOpacity: s.shadowOpacity,
        shadowBlur: s.shadowBlur,
        shadowDistance: s.shadowDistance,
        shadowAngle: s.shadowAngle,
        opacity: s.opacity,
        anim: s.anim,
        fadeIn: s.fadeIn,
        fadeOut: s.fadeOut,
        custom: true,
      );

  // ── JSON ────────────────────────────────────────────────────────────────
  // Written to be edited by hand in the admin, so colours are #AARRGGBB and
  // the two enums are their names. Every field has a default on the way in:
  // a preset the admin saved with one key missing must still be usable, not
  // an exception in the middle of the editor.

  static int _colour(Object? v, int fallback) {
    if (v is int) return v;
    if (v is String) {
      var t = v.trim();
      if (t.startsWith('#')) t = t.substring(1);
      if (t.startsWith('0x') || t.startsWith('0X')) t = t.substring(2);
      if (t.length == 6) t = 'FF$t'; // opaque unless told otherwise
      final n = int.tryParse(t, radix: 16);
      if (n != null) return n;
    }
    return fallback;
  }

  static double _num(Object? v, double fallback) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? fallback : fallback);

  static bool _bool(Object? v, bool fallback) =>
      v is bool ? v : (v is String ? v.toLowerCase() == 'true' : fallback);

  static String _hex(int argb) => '#${argb.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';

  factory CaptionPreset.fromJson(Map<String, dynamic> j) {
    final alignName = (j['align'] as String?)?.toLowerCase();
    final animName = (j['anim'] as String?);
    return CaptionPreset(
      name: (j['name'] as String?)?.trim().isNotEmpty == true ? (j['name'] as String).trim() : 'Preset',
      font: (j['font'] as String?)?.trim().isEmpty == true ? null : j['font'] as String?,
      fontSize: _num(j['fontSize'], 44),
      color: _colour(j['color'], 0xFFFFFFFF),
      bold: _bool(j['bold'], true),
      italic: _bool(j['italic'], false),
      align: TextAlignH.values.firstWhere((a) => a.name == alignName,
          orElse: () => TextAlignH.center),
      letterSpacing: _num(j['letterSpacing'], 0),
      lineHeight: _num(j['lineHeight'], 1.15),
      strokeWidth: _num(j['strokeWidth'], 0),
      strokeColor: _colour(j['strokeColor'], 0xFF000000),
      bgEnabled: _bool(j['bgEnabled'], false),
      bgColor: _colour(j['bgColor'], 0x00000000),
      shadow: _bool(j['shadow'], false),
      shadowColor: _colour(j['shadowColor'], 0xFF000000),
      shadowOpacity: _num(j['shadowOpacity'], 1.0),
      shadowBlur: _num(j['shadowBlur'], 0.5),
      shadowDistance: _num(j['shadowDistance'], 0.0),
      shadowAngle: _num(j['shadowAngle'], 45.0),
      opacity: _num(j['opacity'], 1.0),
      anim: OverlayAnim.values.firstWhere((a) => a.name == animName,
          orElse: () => OverlayAnim.none),
      fadeIn: _num(j['fadeIn'], 0),
      fadeOut: _num(j['fadeOut'], 0),
      custom: _bool(j['custom'], false),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'font': font,
        'fontSize': fontSize,
        'color': _hex(color),
        'bold': bold,
        'italic': italic,
        'align': align.name,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'strokeWidth': strokeWidth,
        'strokeColor': _hex(strokeColor),
        'bgEnabled': bgEnabled,
        'bgColor': _hex(bgColor),
        'shadow': shadow,
        'shadowColor': _hex(shadowColor),
        'shadowOpacity': shadowOpacity,
        'shadowBlur': shadowBlur,
        'shadowDistance': shadowDistance,
        'shadowAngle': shadowAngle,
        'opacity': opacity,
        'anim': anim.name,
        'fadeIn': fadeIn,
        'fadeOut': fadeOut,
        if (custom) 'custom': true,
      };

  /// What the app ships with.
  ///
  /// The server decides which presets people actually see; this is what they
  /// see before it has answered, on a first run with no network, and if it
  /// ever answers with nothing usable. The same list is the server's own
  /// default, so the two agree until an admin changes one.
  static const List<CaptionPreset> bundled = [
    CaptionPreset(name: 'Bold Meme', font: 'Anton', fontSize: 52, color: 0xFFFFFFFF,
        strokeWidth: 6, anim: OverlayAnim.popIn),
    CaptionPreset(name: 'Subtitle', font: 'Montserrat', fontSize: 40, color: 0xFFFFFFFF,
        bgEnabled: true, bgColor: 0xB3000000, anim: OverlayAnim.fade),
    CaptionPreset(name: 'Impact', font: 'Archivo Black', fontSize: 50, color: 0xFFFFFFFF,
        strokeWidth: 5, anim: OverlayAnim.zoomIn),
    CaptionPreset(name: 'Neon Pop', font: 'Bebas Neue', fontSize: 50, color: 0xFF0E9E6E,
        strokeWidth: 4, strokeColor: 0xFFFFFFFF, shadow: true, shadowColor: 0xFF0E9E6E,
        shadowBlur: 0.8, anim: OverlayAnim.bounce),
    CaptionPreset(name: 'Sunshine', font: 'Poppins', fontSize: 44, color: 0xFF17131F,
        bgEnabled: true, bgColor: 0xFFFFC400, anim: OverlayAnim.slideUp),
    CaptionPreset(name: 'Marker', font: 'Permanent Marker', fontSize: 46, color: 0xFFFFFFFF,
        strokeWidth: 3, anim: OverlayAnim.shake),
    CaptionPreset(name: 'Retro', font: 'Lobster', fontSize: 46, color: 0xFFFFC400,
        strokeWidth: 3, strokeColor: 0xFF3A2600, anim: OverlayAnim.slideDown),
    CaptionPreset(name: 'Headline', font: 'Oswald', fontSize: 44, color: 0xFFFFFFFF,
        bgEnabled: true, bgColor: 0xFF0E9E6E, anim: OverlayAnim.typewriter),
    CaptionPreset(name: 'Handwrite', font: 'Caveat', fontSize: 52, color: 0xFFFFFFFF,
        strokeWidth: 3, anim: OverlayAnim.fade),
    CaptionPreset(name: 'Party', font: 'Shrikhand', fontSize: 46, color: 0xFF12B886,
        strokeWidth: 3, strokeColor: 0xFFFFFFFF, anim: OverlayAnim.pulse),
    CaptionPreset(name: 'Clean', font: 'Inter', fontSize: 42, color: 0xFFFFFFFF,
        shadow: true, shadowOpacity: 0.8, shadowBlur: 0.4),
    CaptionPreset(name: 'Boxed', font: 'Montserrat', fontSize: 42, color: 0xFF000000,
        bgEnabled: true, bgColor: 0xFFFFFFFF, anim: OverlayAnim.popIn),
    CaptionPreset(name: 'Fire', font: 'Anton', fontSize: 52, color: 0xFFFFC400,
        strokeWidth: 5, strokeColor: 0xFFC2272D, anim: OverlayAnim.zoomIn),
    CaptionPreset(name: 'Mint', font: 'Poppins', fontSize: 44, color: 0xFFFFFFFF,
        bgEnabled: true, bgColor: 0xFF12B76A, anim: OverlayAnim.slideUp),
    CaptionPreset(name: 'Ocean', font: 'Oswald', fontSize: 44, color: 0xFFFFFFFF,
        bgEnabled: true, bgColor: 0xFF2D7FF9, anim: OverlayAnim.slideDown),
    CaptionPreset(name: 'Comic', font: 'Bungee', fontSize: 46, color: 0xFFFFFFFF,
        strokeWidth: 5, anim: OverlayAnim.bounce),
    CaptionPreset(name: 'Script', font: 'Pacifico', fontSize: 48, color: 0xFFFFFFFF,
        strokeWidth: 3, anim: OverlayAnim.fade),
    CaptionPreset(name: 'Gold', font: 'Playfair Display', fontSize: 46, color: 0xFFD89A3C,
        strokeWidth: 2, strokeColor: 0xFF3A2600, anim: OverlayAnim.slideUp),
  ];
}
