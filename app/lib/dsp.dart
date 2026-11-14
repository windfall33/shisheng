// 拾声 · 音频 DSP 与文本规整（纯 Dart，可单测）。
import 'dart:math' as math;
import 'dart:typed_data';

/// 引号是给人看的，不是给引擎听的：句首句尾的引号去掉再送合成，
/// 句中的引号（“起来，”他说）保留。
String stripQuotes(String s) => s
    .replaceFirst(RegExp(r'^[「『“"‘]+'), '')
    .replaceFirst(RegExp(r'[」』”"’]+$'), '');

/// 送给 TTS 前的文本规整：统一停顿线索，减少机械顿挫与错误断句。
String ttsNormalize(String text) {
  var t = text.trim();
  t = t.replaceAll(RegExp(r'[\s　]+'), ' ');
  // 汉字之间夹的空格会让引擎停顿，直接去掉
  t = t.split('').fold<StringBuffer>(StringBuffer(), (buf, ch) {
    final isSpace = ch == ' ' || ch == '　';
    if (isSpace) {
      final prev = buf.isEmpty ? '' : buf.toString()[buf.length - 1];
      // 前后都是汉字才删（英文单词间空格保留）
      if (RegExp(r'[一-鿿]').hasMatch(prev)) return buf;
    }
    buf.write(ch);
    return buf;
  }).toString();
  t = t.replaceAll('——', '，').replaceAll('—', '，');
  t = t.replaceAll(RegExp(r'…+'), '…');
  t = t.replaceAll(RegExp(r'[~～]+'), '，');
  t = t.replaceAll(RegExp(r'[，,]{2,}'), '，');
  t = t.replaceAll(RegExp(r'[。．]{2,}'), '。');
  // 段首标点没有语义，去掉
  t = t.replaceFirst(RegExp(r'^[，。、；：！？…\s]+'), '');
  // 没有收尾标点时补句号，避免引擎把最后一句读得发飘
  if (t.isNotEmpty && !RegExp(r'[。！？…]$').hasMatch(t)) t = '$t。';
  return t;
}

/// 段首/段尾 80ms 余弦淡入淡出：换音色时避免爆音与音量硬跳。
/// 只改变包络，不改变段长，时间轴与高亮不受影响。
Uint8List crossFadeEdges(Uint8List pcm, {bool fadeIn = false, bool fadeOut = false,
    int sampleRate = 24000, int voiceFadeMs = 80}) {
  final n = sampleRate * voiceFadeMs ~/ 1000;
  final samples = pcm.length ~/ 2;
  if (samples < 2 * n || (!fadeIn && !fadeOut)) return pcm;
  final view = ByteData.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes);
  if (fadeIn) {
    for (var i = 0; i < n; i++) {
      final g = 0.5 - 0.5 * math.cos(math.pi * i / n);
      final v = (view.getInt16(i * 2, Endian.little) * g).round();
      view.setInt16(i * 2, v, Endian.little);
    }
  }
  if (fadeOut) {
    for (var i = 0; i < n; i++) {
      final g = 0.5 - 0.5 * math.cos(math.pi * i / n);
      final idx = samples - 1 - i;
      final v = (view.getInt16(idx * 2, Endian.little) * g).round();
      view.setInt16(idx * 2, v, Endian.little);
    }
  }
  return pcm;
}

Float32List shapeAudio(Float32List audio, {
    int sampleRate = 24000,
    double trimThr = 1e-3,
    int edgeFadeMs = 10,
    double targetRmsDb = -18.0,
    double peakCeil = 0.85,
}) {
  final thr = trimThr;
  var a = 0, b = audio.length;
  for (var i = 0; i < audio.length; i++) {
    if (audio[i].abs() > thr) { a = i; break; }
  }
  for (var i = audio.length - 1; i >= 0; i--) {
    if (audio[i].abs() > thr) { b = i + 1; break; }
  }
  if (a >= b) return audio;
  a = math.max(a - 64, 0);
  b = math.min(b + 64, audio.length);
  var n = sampleRate * edgeFadeMs ~/ 1000;
  final len = b - a;
  if (n > 0 && len > 2 * n) {
    for (var i = 0; i < n; i++) {
      audio[a + i] *= i / n;
      audio[b - 1 - i] *= i / n;
    }
  }
  // 去直流：消除 int8 模型偶发的基线偏移（杂音/嗡嗡声来源之一）
  var mean = 0.0;
  for (var i = a; i < b; i++) {
    mean += audio[i];
  }
  mean /= len;
  // 一阶高通 ~70Hz（去低频轰鸣）+ 一阶低通 ~11kHz（磨掉高频毛刺）
  final sr = sampleRate.toDouble();
  final hpAlpha = 1.0 / (1.0 + 2 * math.pi * 70 / sr);
  final lpAlpha = (2 * math.pi * 11000 / sr) / (1 + 2 * math.pi * 11000 / sr);
  var hpPrevIn = 0.0, hpPrevOut = 0.0, lpPrev = 0.0;
  var sum = 0.0;
  var peak = 0.0;
  for (var i = a; i < b; i++) {
    final x = audio[i] - mean;
    final hp = hpAlpha * (hpPrevOut + x - hpPrevIn);
    hpPrevIn = x;
    hpPrevOut = hp;
    lpPrev += lpAlpha * (hp - lpPrev);
    audio[i] = lpPrev;
    sum += lpPrev * lpPrev;
    final av = lpPrev.abs();
    if (av > peak) peak = av;
  }
  final rms = math.sqrt(sum / math.max(len, 1));
  var gain = (rms <= 1e-6)
      ? 1.0
      : math.pow(10.0, (targetRmsDb - (20 * math.log(rms) / math.ln10)) / 20).toDouble();
  if (peak * gain > peakCeil) {
    gain = peakCeil / math.max(peak, 1e-9);
  }
  final out = Float32List(len);
  for (var i = 0; i < len; i++) {
    var v = audio[a + i] * gain;
    if (v > peakCeil) v = peakCeil;
    if (v < -peakCeil) v = -peakCeil;
    out[i] = v;
  }
  return out;
}

/// 云端音频（Edge 已做降噪/响度）：只做静音修剪、边缘淡化和轻归一。
Float32List shapeCloud(Float32List audio, {
    int sampleRate = 24000,
    double trimThr = 0.002,
    int edgeFadeMs = 10,
    double targetRmsDb = -18.0,
    double peakCeil = 0.9,
}) {
  var a = 0, b = audio.length;
  for (var i = 0; i < audio.length; i++) {
    if (audio[i].abs() > trimThr) { a = i; break; }
  }
  for (var i = audio.length - 1; i >= 0; i--) {
    if (audio[i].abs() > trimThr) { b = i + 1; break; }
  }
  if (a >= b) return audio;
  final n = sampleRate * edgeFadeMs ~/ 1000;
  final len = b - a;
  if (n > 0 && len > 2 * n) {
    for (var i = 0; i < n; i++) {
      audio[a + i] *= i / n;
      audio[b - 1 - i] *= i / n;
    }
  }
  var sum = 0.0, peak = 0.0;
  for (var i = a; i < b; i++) {
    sum += audio[i] * audio[i];
    final av = audio[i].abs();
    if (av > peak) peak = av;
  }
  final rms = math.sqrt(sum / math.max(len, 1));
  var gain = rms <= 1e-6
      ? 1.0
      : math.pow(10.0, (targetRmsDb - (20 * math.log(rms) / math.ln10)) / 20).toDouble();
  if (peak * gain > peakCeil) gain = peakCeil / math.max(peak, 1e-9);
  final out = Float32List(len);
  for (var i = 0; i < len; i++) {
    var v = audio[a + i] * gain;
    if (v > peakCeil) v = peakCeil;
    if (v < -peakCeil) v = -peakCeil;
    out[i] = v;
  }
  return out;
}
