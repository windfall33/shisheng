// 拾声 v4 · TTS 引擎隔离区：sherpa-onnx Kokoro int8，独立 isolate 合成。
// 输入：{cmd:'synth', text, sid, speed, out}；输出：s16le mono PCM 文件。
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class TtsReply {
  final int id;
  final bool ok;
  final int sampleRate;
  final int numSamples;
  final String? error;
  TtsReply(this.id, this.ok, {this.sampleRate = 0, this.numSamples = 0, this.error});
}

class _Worker {
  Isolate? iso;
  SendPort? send;
  ReceivePort? lp;                // spawn 端口：ready/init回执/结果全走这里
  final ready = Completer<void>();
  final pending = <int, Completer<TtsReply>>{};
  int nextId = 1;
}

class TtsEngine {
  /// PC 冒烟测试用：Windows DLL 目录（含配套 onnxruntime.dll）。
  /// 设备上为 null → 自动解析插件内置 so。
  static String? nativeLibPath;

  final String modelDir;
  final int numThreads;
  final int workers;              // 并行引擎数：合成吞吐 ≈ workers × 单引擎
  int get workerCount => workers;
  final List<_Worker> _pool = [];
  var _rr = 0;

  TtsEngine(this.modelDir, {this.numThreads = 4, this.workers = 1});

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (var i = 0; i < workers; i++) {
      final w = _Worker();
      // ignore: avoid_print
      print('tts: spawning worker $i');
      final lp = ReceivePort();
      w.lp = lp;
      final errPort = ReceivePort();
      w.iso = await Isolate.spawn(_ttsWorker, lp.sendPort,
          debugName: 'tts-worker-$i',
          onError: errPort.sendPort, onExit: errPort.sendPort);
      errPort.listen((e) {
        // worker 崩溃：立刻失败所有挂起请求，别让渲染等 180 秒
        // ignore: avoid_print
        print('tts: worker died: $e');
        for (final c in w.pending.values) {
          c.complete(TtsReply(0, false, error: 'worker crashed: $e'));
        }
        w.pending.clear();
      });
      // worker 的所有回执都发回 spawn 端口：ready → 派 init；initialized → 就绪；其余 = 结果
      lp.listen((msg) {
        final m = msg as Map;
        if (m['ready'] != null) {
          w.send = m['ready'] as SendPort;
          w.send!.send({'cmd': 'init', 'modelDir': modelDir, 'threads': numThreads});
          return;
        }
        if (m['initialized'] == true) {
          // ignore: avoid_print
          print('tts: worker initialized');
          w.ready.complete();
          return;
        }
        final id = m['id'] as int;
        final c = w.pending.remove(id);
        if (c != null) {
          c.complete(TtsReply(id, m['ok'] == true,
              sampleRate: (m['sampleRate'] as num?)?.toInt() ?? 0,
              numSamples: (m['numSamples'] as num?)?.toInt() ?? 0,
              error: m['error'] as String?));
        }
      });
      // init 超时保护：个别 worker 卡死不拖垮整个引擎池
      try {
        await w.ready.future.timeout(const Duration(seconds: 30));
        _pool.add(w);
      } catch (_) {
        lp.close();
        w.iso?.kill(priority: Isolate.beforeNextEvent);
      }
    }
  }

  /// 轮询取 worker：两段并发调用自然落到不同 isolate，真并行。
  _Worker get _next {
    if (_pool.isEmpty) {
      throw StateError('语音引擎初始化全部失败');
    }
    final w = _pool[_rr % _pool.length];
    _rr++;
    return w;
  }

  Future<TtsReply> synth(String text, int sid,
      {double speed = 1.0, required String outPath}) async {
    final w = _next;
    await w.ready.future;
    final id = w.nextId++;
    final c = Completer<TtsReply>();
    w.pending[id] = c;
    w.send!.send({'cmd': 'synth', 'id': id, 'text': text, 'sid': sid,
        'speed': speed, 'out': outPath});
    // 单段超时兜底：长文本一般 <60s，180s 仍无回复按失败处理
    return c.future.timeout(const Duration(seconds: 180), onTimeout: () {
      w.pending.remove(id);
      return TtsReply(id, false, error: 'synth timeout 180s');
    });
  }

  Future<void> dispose() async {
    for (final w in _pool) {
      w.lp?.close();
      w.iso?.kill(priority: Isolate.beforeNextEvent);
    }
    _pool.clear();
  }
}

void _ttsWorker(SendPort port) {
  // 回执（initialized/结果）发回 spawn 端口；命令经 ready 消息里携带的端口进来
  final cmds = ReceivePort();
  port.send({'ready': cmds.sendPort});
  sherpa.OfflineTts? tts;
  cmds.listen((msg) async {
    final m = msg as Map;
    switch (m['cmd']) {
      case 'init':
        // 每个 isolate 都要先初始化 FFI 绑定（sherpa 文档要求）
        sherpa.initBindings(TtsEngine.nativeLibPath);
        final dir = m['modelDir'] as String;
        final kokoro = sherpa.OfflineTtsKokoroModelConfig(
          model: '$dir/model.int8.onnx',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          lexicon: '$dir/lexicon-us-en.txt,$dir/lexicon-zh.txt',
        );
        final cfg = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(kokoro: kokoro,
              numThreads: (m['threads'] as num).toInt()),
          ruleFsts: '$dir/date-zh.fst,$dir/number-zh.fst,$dir/phone-zh.fst',
        );
        tts = sherpa.OfflineTts(cfg);
        port.send({'initialized': true});
        break;
      case 'synth':
        final id = m['id'] as int;
        try {
          final a = tts!.generate(text: m['text'] as String,
              sid: m['sid'] as int, speed: (m['speed'] as num).toDouble());
          // 写 f32le 原始采样，由渲染层整形后转 s16 入缓存
          final samples = a.samples;
          final raw = Uint8List.view(samples.buffer,
              samples.offsetInBytes, samples.lengthInBytes);
          await File(m['out'] as String).writeAsBytes(raw, flush: true);
          port.send({'id': id, 'ok': true, 'sampleRate': a.sampleRate,
              'numSamples': samples.length});
        } catch (e) {
          port.send({'id': id, 'ok': false, 'error': e.toString()});
        }
        break;
    }
  });
}
