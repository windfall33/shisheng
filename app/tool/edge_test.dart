import 'dart:io';
import 'package:shisheng_reader/cloud_tts.dart';

Future<void> main(List<String> a) async {
  final text = a.isNotEmpty ? a[0] : '李火旺看着她，想起了当初在清风观她拿给自己的馒头，他的表情逐渐变得痛苦起来。';
  final voice = a.length > 1 ? a[1] : 'zh-CN-YunjianNeural';
  final out = a.length > 2 ? a[2] : '${Directory.systemTemp.path}/edge_test.pcm';
  final t = DateTime.now();
  final r = await CloudTts.synth(text, voice, outPath: out);
  print('ok=${r.ok} samples=${r.numSamples} err=${r.error} '
      'wall=${DateTime.now().difference(t).inMilliseconds}ms');
  if (r.ok) print('bytes=${File(out).lengthSync()}');
}
