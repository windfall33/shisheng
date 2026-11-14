// PC 端引擎冒烟：TtsEngine（isolate + sherpa FFI）合成一句话并量 RTF。
// 运行前把 sherpa-onnx-c-api.dll 所在目录加进 PATH。
// 用法: dart run tool/e2e_test.dart <modelDir>
import 'dart:io';

import 'package:shisheng_reader/engine.dart';

Future<void> main(List<String> args) async {
  final modelDir = args[0];
  final out = args.length > 1 ? args[1] : 'e2e_out.pcm';
  // PC 冒烟：显式指定与 PATH 里 onnxruntime 配套的 c-api DLL 目录
  final dllDir = Platform.environment['SHERPA_DLL_DIR'];
  if (dllDir != null && dllDir.isNotEmpty) TtsEngine.nativeLibPath = dllDir;
  final eng = TtsEngine(modelDir, numThreads: 2, workers: 2);
  final t0 = DateTime.now();
  await eng.start();
  print('engine start: ${DateTime.now().difference(t0).inMilliseconds}ms');
  const text = '邑有王生，行七，故家子。少慕道，闻劳山多仙人。道士曰：“恐娇情不能作苦。”';
  final r = await eng.synth(text, 102, outPath: out);
  if (!r.ok) {
    print('SYNTH FAIL: ${r.error}');
    exit(1);
  }
  final bytes = await File(out).length();
  final durSec = bytes / 4 / r.sampleRate;
  final wall = DateTime.now().difference(t0).inMilliseconds / 1000;
  print('sr=${r.sampleRate} dur=${durSec.toStringAsFixed(2)}s '
      'wall=${wall.toStringAsFixed(2)}s rtf=${(wall / durSec).toStringAsFixed(3)}');
  print('E2E OK');
  await eng.dispose();
  exit(0);
}
