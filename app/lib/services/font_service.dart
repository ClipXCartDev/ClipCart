import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CustomFont {
  CustomFont({required this.name, required this.family, required this.path, this.builtin = false});
  final String name; // display name
  final String family; // registered Flutter family
  final String path; // on-disk .ttf/.otf for FFmpeg
  final bool builtin; // bundled default vs user upload
}

/// The bundled meme/caption font set (asset file → display name). Regular weight
/// static or variable .ttf — all OFL/Apache, free for commercial use.
const _kBundledFonts = <String, String>{
  'Roboto': 'Roboto',
  'Anton': 'Anton',
  'BebasNeue': 'Bebas Neue',
  'Oswald': 'Oswald',
  'ArchivoBlack': 'Archivo Black',
  'Montserrat': 'Montserrat',
  'Poppins': 'Poppins',
  'Inter': 'Inter',
  'Bungee': 'Bungee',
  'PassionOne': 'Passion One',
  'Caveat': 'Caveat',
  'Pacifico': 'Pacifico',
  'PermanentMarker': 'Permanent Marker',
  'Shrikhand': 'Shrikhand',
  'Lobster': 'Lobster',
  'PlayfairDisplay': 'Playfair Display',
  'Bitter': 'Bitter',
};

/// Custom font upload (§11.7): pick .ttf/.otf → register for preview (FontLoader)
/// + keep the file path for FFmpeg export (drawtext fontfile=).
class FontService extends ChangeNotifier {
  final List<CustomFont> fonts = []; // user uploads
  final List<CustomFont> builtins = []; // bundled defaults (loaded once)
  String? _defaultFontPath;
  bool _builtinsLoaded = false;
  bool _userFontsLoaded = false;

  /// All fonts a user can pick from: bundled first, then their uploads.
  List<CustomFont> get all => [...builtins, ...fonts];

  /// On-disk manifest of the user's imported fonts, so they persist across
  /// launches (the bug: imports lived only in memory and vanished on restart).
  Future<File> _manifestFile() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/fonts/user_fonts.json');
    f.parent.createSync(recursive: true);
    return f;
  }

  /// Re-registers every previously-imported font (reads the manifest, loads each
  /// .ttf/.otf back into a FontLoader) so imported families render after a
  /// restart. Idempotent; drops manifest entries whose file no longer exists.
  Future<void> loadUserFonts() async {
    if (_userFontsLoaded) return;
    _userFontsLoaded = true;
    try {
      final mf = await _manifestFile();
      if (!mf.existsSync()) return;
      final raw = jsonDecode(await mf.readAsString());
      if (raw is! List) return;
      var changed = false;
      for (final e in raw) {
        if (e is! Map) continue;
        final name = e['name'] as String?;
        final family = e['family'] as String?;
        final path = e['path'] as String?;
        if (name == null || family == null || path == null) continue;
        if (fonts.any((f) => f.family == family)) continue; // already registered
        final file = File(path);
        if (!file.existsSync()) { changed = true; continue; } // prune missing
        try {
          final bytes = await file.readAsBytes();
          final loader = FontLoader(family)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
          await loader.load();
          fonts.add(CustomFont(name: name, family: family, path: path));
        } catch (_) {/* skip a bad font file */}
      }
      if (changed) await _writeManifest();
    } catch (_) {/* malformed manifest — ignore */}
    notifyListeners();
  }

  Future<void> _writeManifest() async {
    try {
      final mf = await _manifestFile();
      await mf.writeAsString(jsonEncode([
        for (final f in fonts) {'name': f.name, 'family': f.family, 'path': f.path},
      ]));
    } catch (_) {/* best-effort persistence */}
  }

  /// Loads every bundled font: copies the asset to disk (for FFmpeg) and
  /// registers its family for live preview (FontLoader). Idempotent.
  Future<void> loadBuiltins() async {
    if (_builtinsLoaded) return;
    _builtinsLoaded = true;
    final dir = await getApplicationSupportDirectory();
    for (final entry in _kBundledFonts.entries) {
      final asset = 'assets/fonts/${entry.key}.ttf';
      try {
        final data = await rootBundle.load(asset);
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        // persist for FFmpeg export
        final path = '${dir.path}/fonts/${entry.key}.ttf';
        final file = File(path)..parent.createSync(recursive: true);
        if (!file.existsSync()) await file.writeAsBytes(bytes);
        // register family for canvas preview
        final loader = FontLoader(entry.value)..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
        builtins.add(CustomFont(name: entry.value, family: entry.value, path: path, builtin: true));
      } catch (_) {/* asset missing — skip */}
    }
    notifyListeners();
    // Bring back any fonts the user imported in a previous session.
    await loadUserFonts();
  }

  /// Copies the bundled default font to disk once; returns its path.
  Future<String> ensureDefaultFont() async {
    if (_defaultFontPath != null) return _defaultFontPath!;
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/fonts/Roboto.ttf';
    final file = File(path);
    if (!file.existsSync()) {
      final data = await rootBundle.load('assets/fonts/Roboto.ttf');
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    _defaultFontPath = path;
    // kick off loading the rest of the family in the background
    loadBuiltins();
    return path;
  }

  /// Lets the user pick a font file, registers it for preview, returns it.
  Future<CustomFont?> uploadFont() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final picked = res.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return null;

    final family = 'cf_${picked.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}';

    // persist to disk (for FFmpeg)
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/fonts/${picked.name}';
    final file = File(path)..parent.createSync(recursive: true);
    await file.writeAsBytes(bytes);

    // register for preview rendering
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();

    final font = CustomFont(name: picked.name, family: family, path: path);
    fonts.add(font);
    await _writeManifest(); // persist so the import survives a restart
    notifyListeners();
    return font;
  }
}
