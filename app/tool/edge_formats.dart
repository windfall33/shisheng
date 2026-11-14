import 'dart:io';
import 'package:shisheng_reader/cloud/edge_tts2/edge_tts2.dart';
Future<void> main() async {
  for (final fmt in [
    EdgeTtsOutputFormat.raw24Khz16BitMonoPcm,
    EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
  ]) {
    final tts = FlutterEdgeTts(voice: 'zh-CN-YunjianNeural', outputFormat: fmt,
        enableLogging: true);
    try {
      final out = '${Directory.systemTemp.path}/fmt_${fmt.fileExtension}.bin';
      await tts.synthesizeToFile('李火旺看着她，想起了当初在清风观她拿给自己的馒头。',
          audioFilePath: out);
      final len = File(out).lengthSync();
      print('${fmt.value} -> $len bytes');
    } catch (e) {
      print('${fmt.value} FAIL $e');
    } finally { await tts.dispose(); }
  }
}
