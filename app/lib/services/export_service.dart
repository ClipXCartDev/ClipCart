import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';

class ExportResult {
  ExportResult(this.path, this.savedToGallery);
  final String path;
  final bool savedToGallery;
}

/// On-device MP4 export (decisions §5, §9). Burns timed subtitles via drawtext
/// (`enable=between(t,start,end)` per line, each with its own font) + logo overlay.
/// Uses ffmpeg_kit_flutter_new v4.x `execute(String)` API.
class ExportService {
  Future<ExportResult> export(EditorProject project) async {
    final tmp = await getTemporaryDirectory();

    // One drawtext filter per timed subtitle line (no quotes/spaces → parser-safe).
    final draws = <String>[];
    for (var i = 0; i < project.subtitles.length; i++) {
      final s = project.subtitles[i];
      final textFile = File('${tmp.path}/sub_$i.txt');
      await textFile.writeAsString(s.text); // textfile= avoids escaping the text
      final font = s.fontFilePath ?? project.defaultFontPath;
      draws.add(
        'drawtext=fontfile=$font'
        ':textfile=${textFile.path}'
        ':fontcolor=0x${_rgb(s.color)}'
        ':fontsize=${s.fontSize.round()}'
        ':x=(w*${s.dx.toStringAsFixed(4)}-text_w/2):y=(h*${s.dy.toStringAsFixed(4)}-text_h/2)'
        ':box=1:boxcolor=black@0.5:boxborderw=14'
        ':enable=between(t\\,${s.start.toStringAsFixed(2)}\\,${s.end.toStringAsFixed(2)})',
      );
    }
    final drawChain = draws.join(',');

    final outDir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports')
      ..createSync(recursive: true);
    final output = '${outDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final parts = <String>['-y', '-i', '"${project.baseClipPath}"'];

    if (project.logoPath != null) {
      parts.addAll(['-i', '"${project.logoPath}"']);
      final lx = project.logoDx.toStringAsFixed(4);
      final ly = project.logoDy.toStringAsFixed(4);
      final fc = StringBuffer('[1:v]scale=160:-1[lg];[0:v][lg]overlay=W*$lx-w/2:H*$ly-h/2');
      if (drawChain.isNotEmpty) {
        fc..write('[ov];[ov]')..write(drawChain);
      }
      fc.write('[vout]');
      parts.addAll(['-filter_complex', fc.toString(), '-map', '"[vout]"', '-map', '"0:a?"']);
    } else if (drawChain.isNotEmpty) {
      parts.addAll(['-vf', drawChain]);
    }

    parts.addAll([
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
      '-c:a', 'aac', '-movflags', '+faststart', '"$output"',
    ]);

    final session = await FFmpegKit.execute(parts.join(' '));
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Export failed (rc=$rc)\n${logs ?? ''}');
    }

    // Save to the phone Gallery (ClipCart album) so it's easy to find + share.
    bool savedToGallery = false;
    try {
      await Gal.putVideo(output, album: 'ClipCart');
      savedToGallery = true;
    } catch (_) {/* still available at [output] */}
    return ExportResult(output, savedToGallery);
  }

  String _rgb(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
}
