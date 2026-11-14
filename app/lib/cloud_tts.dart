// 拾声 · Edge 云端音色（flutter_edge_tts，raw PCM）。
// 在线时优先云端；不可用或失败时由渲染层回退 Kokoro。
// 设置里选「仅本机」时这里直接返回 false：一段都不会发出去。
import 'dart:io';

import 'package:flutter/services.dart';

import 'cloud/edge_tts2/edge_tts2.dart';
import 'settings.dart';

class CloudReply {
  final bool ok;
  final int numSamples;
  final String? error;
  CloudReply(this.ok, {this.numSamples = 0, this.error});
}

class CloudTts {
  static bool _online = false;
  static DateTime? _checkedAt;
  static bool? _lastAllowed;
  static const _ttl = Duration(minutes: 2);

  static Future<bool> available() async {
    final allowed = AppSettings.instance.cloudAllowed.value;
    if (!allowed) {
      _lastAllowed = false;
      return false;
    }
    // 用户刚从「仅本机」切回自动：把网络探测的 2 分钟缓存作废，立刻重测。
    if (_lastAllowed == false) _checkedAt = null;
    _lastAllowed = true;
    final now = DateTime.now();
    if (_checkedAt != null && now.difference(_checkedAt!) < _ttl) return _online;
    try {
      final r = await InternetAddress.lookup('speech.platform.bing.com')
          .timeout(const Duration(seconds: 3));
      _online = r.isNotEmpty;
    } catch (_) {
      _online = false;
    }
    _checkedAt = now;
    return _online;
  }

  /// 按「性别 + 年龄 + 气质」映射到 Edge 中文音色，并给出韵律参数。
  /// rate 为倍率（1.0=正常），pitch 为 ±Hz。
  static ({String voice, double rate, String pitch}) profile({
    required bool narration,
    required String gender,
    String? age,
    String? type,
    String? speaker,
  }) {
    final male = gender != 'female';
    String voice;
    var rate = 1.0;
    var pitch = '+0Hz';

    if (narration) {
      voice = 'zh-CN-YunjianNeural';
      rate = 0.98;
    } else {
      switch (age) {
        case 'child':
          voice = male ? 'zh-CN-YunxiaNeural' : 'zh-CN-XiaoyiNeural';
          rate = 1.04;
          pitch = '+18Hz';
          break;
        case 'old':
          voice = male ? 'zh-CN-YunjianNeural' : 'zh-CN-XiaobeiNeural';
          rate = 0.92;
          pitch = '-12Hz';
          break;
        case 'youth':
          voice = male ? 'zh-CN-YunxiNeural' : 'zh-CN-XiaoyiNeural';
          pitch = '+5Hz';
          break;
        default:
          voice = male ? 'zh-CN-YunxiNeural' : 'zh-CN-XiaoxiaoNeural';
      }
      switch (type) {
        case 'rough':
          voice = male ? 'zh-CN-YunjianNeural' : 'zh-CN-XiaobeiNeural';
          rate = 0.97;
          pitch = '-8Hz';
          break;
        case 'frail':
          voice = male ? 'zh-CN-YunxiNeural' : 'zh-CN-XiaoyiNeural';
          rate = 0.95;
          pitch = '+4Hz';
          break;
        case 'sinister':
          voice = male ? 'zh-CN-YunjianNeural' : 'zh-CN-XiaoniNeural';
          rate = 0.96;
          pitch = '-6Hz';
          break;
        case 'gentle':
          voice = male ? 'zh-CN-YunxiNeural' : 'zh-CN-XiaoxiaoNeural';
          rate = 0.98;
          pitch = '+2Hz';
          break;
        case 'stern':
          voice = male ? 'zh-CN-YunyangNeural' : 'zh-CN-XiaobeiNeural';
          rate = 0.97;
          pitch = '-8Hz';
          break;
      }
    }
    return (voice: voice, rate: rate, pitch: pitch);
  }

  static const _audioChannel = MethodChannel('shisheng/audio');

  static Future<CloudReply> synth(String text, String voice,
      {double rate = 1.0, String pitch = '+0Hz', required String outPath}) async {
    FlutterEdgeTts? tts;
    final mp3Path = '$outPath.mp3';
    try {
      tts = FlutterEdgeTts(voice: voice);
      await tts.synthesizeToFile(
        text,
        audioFilePath: mp3Path,
        prosody: EdgeTtsProsody(
            rate: rate.toStringAsFixed(2), pitch: pitch, volume: '100'),
      );
      final mp3 = File(mp3Path);
      if (!await mp3.exists() || await mp3.length() == 0) {
        return CloudReply(false, error: 'empty mp3');
      }
      final pcm = await _audioChannel.invokeMethod<Uint8List>(
          'decodeMp3', {'path': mp3Path});
      if (pcm == null || pcm.isEmpty) {
        return CloudReply(false, error: 'decode empty');
      }
      await File(outPath).writeAsBytes(pcm, flush: true);
      return CloudReply(true, numSamples: pcm.length ~/ 2);
    } catch (e) {
      return CloudReply(false, error: e.toString());
    } finally {
      try {
        final f = File(mp3Path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await tts?.dispose();
    }
  }
}
