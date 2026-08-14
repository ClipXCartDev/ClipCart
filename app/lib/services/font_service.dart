import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CustomFont {
  CustomFont({required this.name, required this.family, required this.path});
  final String name; // display name
  final String family; // registered Flutter family
  final String path; // on-disk .ttf/.otf for FFmpeg
}

/// Custom font upload (§11.7): pick .ttf/.otf → register for preview (FontLoader)
/// + keep the file path for FFmpeg export (drawtext fontfile=).
class FontService extends ChangeNotifier {
  final List<CustomFont> fonts = [];
  String? _defaultFontPath;

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
    notifyListeners();
    return font;
  }
}
