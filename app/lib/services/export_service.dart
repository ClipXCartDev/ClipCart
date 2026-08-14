import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../models/editor_state.dart';

/// On-device MP4 export (decisions §5, §9). Burns timed subtitles via drawtext
/// (`enable='between(t,start,end)'` per line, each with its own font) + logo overlay.
class ExportService {
  Future<String> export(EditorProject project) async {
    final tmp = await getTemporaryDirectory();

    // Build one drawtext filter per timed subtitle line.
    final draws = <String>[];
    for (var i = 0; i < project.subtitles.length; i++) {
      final s = project.subtitles[i];
      final textFile = File('${tmp.path}/sub_$i.txt');
      await textFile.writeAsString(s.text); // textfile= avoids escaping headaches
      final font = s.fontFilePath ?? project.defaultFontPath;
      draws.add(
        "drawtext=fontfile='$font'"
        ":textfile='${textFile.path}'"
        ":fontcolor=0x${_rgb(s.color)}"
        ":fontsize=${s.fontSize.round()}"
        ":x=(w-text_w)/2:y=h-text_h-120"
        ":box=1:boxcolor=black@0.5:boxborderw=14"
        ":enable='between(t\\,${s.start.toStringAsFixed(2)}\\,${s.end.toStringAsFixed(2)})'",
      );
    }
    final drawChain = draws.join(',');

    final outDir = Directory('${(await getApplicationDocumentsDirectory()).path}/exports')
      ..createSync(recursive: true);
    final output = '${outDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final args = <String>['-y', '-i', project.baseClipPath];

    if (project.logoPath != null) {
      args.addAll(['-i', project.logoPath!]);
      final fc = StringBuffer('[0:v][1:v]overlay=W-w-24:24');
      if (drawChain.isNotEmpty) {
        fc..write('[ov];[ov]')..write(drawChain);
      }
      fc.write('[vout]');
      args.addAll(['-filter_complex', fc.toString(), '-map', '[vout]', '-map', '0:a?']);
    } else if (drawChain.isNotEmpty) {
      args.addAll(['-vf', drawChain]);
    }

    args.addAll([
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
      '-c:a', 'aac', '-movflags', '+faststart', output,
    ]);

    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (ReturnCode.isSuccess(rc)) return output;

    final logs = await session.getAllLogsAsString();
    throw Exception('Export failed (rc=$rc)\n${logs ?? ''}');
  }

  String _rgb(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
}
