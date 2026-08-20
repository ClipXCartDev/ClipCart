import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// A saved brand identity: 1-3 colors, a preferred font family, and a logo file.
/// Applied to overlays in one tap so a creator's clips stay on-brand.
class BrandKit {
  BrandKit({List<int>? colors, this.fontFamily, this.fontPath, this.logoPath})
      : colors = colors ?? const [0xFFFFFFFF, 0xFF2563EB, 0xFF17131F];

  List<int> colors; // ARGB, first = primary
  String? fontFamily; // registered family for preview
  String? fontPath; // .ttf on disk for FFmpeg
  String? logoPath; // logo image on disk

  int get primary => colors.isNotEmpty ? colors.first : 0xFFFFFFFF;

  Map<String, dynamic> toJson() => {
        'colors': colors,
        'fontFamily': fontFamily,
        'fontPath': fontPath,
        'logoPath': logoPath,
      };

  factory BrandKit.fromJson(Map<String, dynamic> j) => BrandKit(
        colors: (j['colors'] as List?)?.map((e) => e as int).toList(),
        fontFamily: j['fontFamily'] as String?,
        fontPath: j['fontPath'] as String?,
        logoPath: j['logoPath'] as String?,
      );
}

/// Also holds user-saved custom text styles (Styles gallery "+ Save current").
class SavedStyle {
  SavedStyle(this.name, this.data);
  final String name;
  final Map<String, dynamic> data; // {font,color,bg,bgc,sw,sc,anim}
  Map<String, dynamic> toJson() => {'name': name, 'data': data};
  factory SavedStyle.fromJson(Map<String, dynamic> j) => SavedStyle(j['name'] as String, Map<String, dynamic>.from(j['data'] as Map));
}

class BrandKitService extends ChangeNotifier {
  static const _kBrand = 'cc_brand_kit';
  static const _kStyles = 'cc_saved_styles';
  final _store = const FlutterSecureStorage();

  BrandKit? kit;
  List<SavedStyle> styles = [];
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _store.read(key: _kBrand);
      if (raw != null) kit = BrandKit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    try {
      final raw = await _store.read(key: _kStyles);
      if (raw != null) styles = (jsonDecode(raw) as List).map((e) => SavedStyle.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveKit(BrandKit k) async {
    kit = k;
    await _store.write(key: _kBrand, value: jsonEncode(k.toJson()));
    notifyListeners();
  }

  /// Copies a picked logo into app storage so it persists across sessions.
  Future<String> persistLogo(String srcPath) async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory('${dir.path}/brand')..createSync(recursive: true);
    final ext = srcPath.contains('.') ? srcPath.split('.').last : 'png';
    final dst = '${d.path}/logo.$ext';
    await File(srcPath).copy(dst);
    return dst;
  }

  Future<void> addStyle(SavedStyle s) async {
    styles = [s, ...styles.where((x) => x.name != s.name)];
    if (styles.length > 20) styles = styles.sublist(0, 20);
    await _store.write(key: _kStyles, value: jsonEncode(styles.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> removeStyle(String name) async {
    styles = styles.where((x) => x.name != name).toList();
    await _store.write(key: _kStyles, value: jsonEncode(styles.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
