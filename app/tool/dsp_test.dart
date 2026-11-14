// DSP 客观验证：用真实 Kokoro 音频跑 整形 + 换声淡化，检查爆音与音量跳变。
import 'dart:io';
import 'dart:typed_data';
import 'package:shisheng_reader/dsp.dart';

Float32List readWav16(String path) {
  final b = File(path).readAsBytesSync();
  var off = 12;
  var dataOff = -1, dataLen = 0, sr = 24000;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final len = ByteData.view(b.buffer, off + 4, 4).getUint32(0, Endian.little);
    if (id == 'fmt ') sr = ByteData.view(b.buffer, off + 12, 4).getUint32(0, Endian.little);
    if (id == 'data') { dataOff = off + 8; dataLen = len; break; }
    off += 8 + len + (len & 1);
  }
  final view = ByteData.view(b.buffer, dataOff, dataLen);
  final out = Float32List(dataLen ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  print('wav: sr=$sr samples=${out.length}');
  return out;
}

Uint8List toS16(Float32List x) {
  final out = Uint8List(x.length * 2);
  final v = ByteData.view(out.buffer);
  for (var i = 0; i < x.length; i++) {
    v.setInt16(i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return out;
}

double maxDelta(Uint8List pcm) {
  final v = ByteData.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes);
  var m = 0;
  var prev = v.getInt16(0, Endian.little);
  for (var i = 1; i < pcm.length ~/ 2; i++) {
    final s = v.getInt16(i * 2, Endian.little);
    final d = (s - prev).abs();
    if (d > m) m = d;
    prev = s;
  }
  return m / 32768.0;
}

double rms(Float32List x, int a, int b) {
  var s = 0.0;
  for (var i = a; i < b; i++) { s += x[i] * x[i]; }
  return (s / (b - a)).abs().sqrtSafe();
}

extension on double { double sqrtSafe() => this <= 0 ? 0 : this; }

void main(List<String> args) {
  final src = readWav16(args[0]);
  final shaped = shapeAudio(src);
  final raw = toS16(src);
  final proc = toS16(shaped);
  print('click maxDelta raw=${maxDelta(raw).toStringAsFixed(4)} '
      'shaped=${maxDelta(proc).toStringAsFixed(4)}');

  // 模拟换声：在 1/3 处切开，前后各 80ms 淡化，中间 140ms 静音
  final cut = shaped.length ~/ 3;
  final a = Float32List.sublistView(shaped, 0, cut);
  final b = Float32List.sublistView(shaped, cut);
  final pcmA = crossFadeEdges(toS16(a), sampleRate: 24000, fadeOut: true);
  final pcmB = crossFadeEdges(toS16(b), sampleRate: 24000, fadeIn: true);
  final pause = Uint8List(24000 * 140 ~/ 1000 * 2);
  final joined = BytesBuilder()
    ..add(pcmA)..add(pause)..add(pcmB);
  final out = joined.toBytes();
  print('joined click maxDelta=${maxDelta(out).toStringAsFixed(4)} '
      'duration=${(out.length / 2 / 24000).toStringAsFixed(3)}s');
  File(args[1]).writeAsBytesSync(out);
  // 写出带 RIFF 头的 wav 便于试听
  final ds = out.length;
  final hdr = ByteData(44);
  void tag(int o, String s) { for (var i = 0; i < 4; i++) { hdr.setUint8(o + i, s.codeUnitAt(i)); } }
  tag(0, 'RIFF'); hdr.setUint32(4, 36 + ds, Endian.little); tag(8, 'WAVE');
  tag(12, 'fmt '); hdr.setUint32(16, 16, Endian.little); hdr.setUint16(20, 1, Endian.little);
  hdr.setUint16(22, 1, Endian.little); hdr.setUint32(24, 24000, Endian.little);
  hdr.setUint32(28, 48000, Endian.little); hdr.setUint16(32, 2, Endian.little);
  hdr.setUint16(34, 16, Endian.little); tag(36, 'data'); hdr.setUint32(40, ds, Endian.little);
  File(args[2]).writeAsBytesSync([...hdr.buffer.asUint8List(), ...out]);
  print('OK');
}
