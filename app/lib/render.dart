// 拾声 v4 · 渲染管线 + 队列（端侧版）。
// 块 = 原子渲染单元：逐句合成 → 修剪/归一 → 停顿 → 追加到章级 s16le PCM 文件。
// 章 = audio/<seq>.pcm（本地虚拟 WAV 由 HTTP 层包装）；index.json 记录毫秒/字节双时间轴。
// 队列 = 单工作者 + 优先级（NOW=0 听 > USER=1 指定 > AUTO=2 顺序预渲）。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'cloud_tts.dart';
import 'dsp.dart';
import 'engine.dart';
import 'pipeline.dart';
import 'store.dart';
import 'textfront.dart';
import 'voices.dart';

export 'pipeline.dart' show audioPipelineVersion;

class RenderCfg {
  static const sampleRate = 24000; // Kokoro 输出
  static const bytesPerSample = 2;
  static const targetRmsDb = -18.0;
  static const peakCeil = 0.85;
  static const trimThr = 1e-3;
  static const edgeFadeMs = 10;
  static const voiceFadeMs = 80;   // 换声交叉淡化
  static const pausePara = 0.35;
  static const pauseVoice = 0.14;
  static const pauseSent = 0.06;
  static const pauseLead = 0.20;
  static const blockTargetSec = 25.0;
  static const blockTargetChars = 160;
  static const blockFirstSec = 7.0;
  static const blockHardSec = 45.0;
  static const cps = 4.3;
  static const bytesPerMs = sampleRate * bytesPerSample ~/ 1000; // 48
}


double estSec(Segment seg) => math.max(seg.text.length / RenderCfg.cps, 0.6);

List<List<Segment>> makeBlocks(Chapter chapter) {
  final blocks = <List<Segment>>[];
  var cur = <Segment>[];
  var curSec = 0.0;
  var target = RenderCfg.blockFirstSec;
  for (final seg in chapter.segments) {
    final s = estSec(seg);
    if (cur.isNotEmpty &&
        (curSec + s > RenderCfg.blockHardSec ||
            (curSec >= target && seg.para != cur.last.para))) {
      blocks.add(cur);
      cur = [];
      curSec = 0;
      target = RenderCfg.blockTargetSec;
    }
    cur.add(seg);
    curSec += s;
  }
  if (cur.isNotEmpty) blocks.add(cur);
  return blocks.isEmpty ? [<Segment>[]] : blocks;
}


String cacheKey(String text, String voiceKey, String dirtyVer) {
  final h = sha256.convert(utf8.encode(
      '${text.trim()}\x00$voiceKey\x00${VoicePool.engineId}\x00${VoicePool.engineModelId}\x00$dirtyVer'
      '\x00$audioPipelineVersion'));
  return h.toString();
}

class _Job implements Comparable<_Job> {
  final String bid;
  final int seq;
  int pri;
  final int order;
  _Job(this.bid, this.seq, this.pri, this.order);
  @override
  int compareTo(_Job o) {
    if (pri != o.pri) return pri - o.pri;
    return order - o.order;
  }
}

class Renderer {
  static Renderer? _inst;
  static Renderer get instance => _inst!;

  static const priNow = 0;
  static const priUser = 1;
  static const priAuto = 2;

  final TtsEngine engine;
  final _jobs = <_Job>[];
  var _order = 0;
  bool _running = false;
  String? curBid;
  int? curSeq;
  int _curPri = 99;

  /// 当前渲染任务之后是否有更高优先级在排队（块边界让位）
  bool _hasHigherThanCurrent() {
    for (final j in _jobs) {
      if (j.pri < _curPri) return true;
    }
    return false;
  }

  Renderer._(this.engine);
  static Future<Renderer> ensure(TtsEngine Function() engineFactory) async {
    if (_inst == null) {
      _inst = Renderer._(engineFactory());
      await _inst!.engine.start();
      _inst!._loop();
    }
    return _inst!;
  }

  String? _focusBid;
  int? _focusSeq;

  /// 用户点播：把该章设为唯一焦点（NOW），其它排队的 NOW 降为 USER。
  /// 这样切章能抢占旧章，又不会出现"同优先级互相让位"的活锁。
  Future<bool> focus(String bid, int seq) async {
    _focusBid = bid;
    _focusSeq = seq;
    for (final j in _jobs) {
      if (j.pri == priNow && !(j.bid == bid && j.seq == seq)) {
        j.pri = priUser;
      }
    }
    if (curBid != null && !(curBid == bid && curSeq == seq) && _curPri == priNow) {
      _curPri = priUser;   // 正在渲的旧章降级 → 块边界让位
    }
    _jobs.sort();
    return touch(bid, seq, priNow);
  }

  bool isFocus(String bid, int seq) => _focusBid == bid && _focusSeq == seq;

  Future<bool> touch(String bid, int seq, int pri) async {
    final idx = await Data.readIndex(bid, seq);
    // 只有"当前管线版本"渲染完的章才算完成；旧版本音频要重渲
    if (idx != null && idx['done'] == true &&
        idx['pipe'] == audioPipelineVersion) {
      return false;
    }
    for (final j in _jobs) {
      if (j.bid == bid && j.seq == seq && j.pri <= pri) return true;
    }
    if (curBid == bid && curSeq == seq) {
      // 正在渲的章被点播：把当前优先级提到最高，继续渲完本章即可
      if (pri < _curPri) _curPri = pri;
      return true;
    }
    _jobs.removeWhere((j) => j.bid == bid && j.seq == seq);
    _jobs.add(_Job(bid, seq, pri, _order++));
    _jobs.sort();
    _kick();
    return true;
  }

  void _kick() {
    if (_running) return;
    _running = true;
    _loop();
  }

  Future<void> _loop() async {
    // 单工作者循环（任何异常都不能让它静默死掉）
    try {
    while (true) {
      if (_jobs.isEmpty) {
        _running = false;
        curBid = null;
        curSeq = null;
        return;
      }
      final job = _jobs.removeAt(0);
      curBid = job.bid;
      curSeq = job.seq;
      _curPri = job.pri;
      var done = false;
      try {
        final ir = await Data.loadBook(job.bid);
        final voices = await Data.loadVoices(job.bid);
        if (ir != null && job.seq < ir.chapters.length) {
          done = await renderChapter(job.bid, ir, job.seq, voices,
              yieldCheck: _hasHigherThanCurrent);
        }
      } catch (e) {
        // ignore: avoid_print
        print('render: chapter failed $job.bid/$job.seq: $e');
      }
      // 被高优先级抢占：把本章放回队列（保持原优先级），让新任务先走
      if (!done && !_jobs.any((j) => j.bid == job.bid && j.seq == job.seq)) {
        // 用（可能已被降级的）当前优先级重新排队，避免多个"最高优先级"堆积
        _jobs.add(_Job(job.bid, job.seq, _curPri, _order++));
        _jobs.sort();
      }
      _curPri = 99;
    }
    } catch (e) {
      // ignore: avoid_print
      print('render: loop crashed: $e');
      _running = false;
    }
  }

  Future<bool> renderChapter(String bid, BookIR ir, int seq, BookVoices voices,
      {bool Function()? yieldCheck}) async {
    final chapter = ir.chapters[seq];
    var idx = (await Data.readIndex(bid, seq)) ?? <String, dynamic>{
      'seq': seq, 'blocks': <dynamic>[], 'done': false,
      'plan_blocks': 0, 'total_bytes': 0, 'total_ms': 0,
    };
    // 管线版本变了（DSP/拼接策略升级）：旧音频作废，整章重渲
    final stale = idx['pipe'] != audioPipelineVersion;
    if (stale) {
      idx = <String, dynamic>{
        'seq': seq, 'blocks': <dynamic>[], 'done': false,
        'plan_blocks': 0, 'total_bytes': 0, 'total_ms': 0,
        'pipe': audioPipelineVersion,
      };
      try {
        final oldAudio = File(await Data.audioPcm(bid, seq));
        if (await oldAudio.exists()) await oldAudio.delete();
      } catch (_) {}
    }
    final blocks = makeBlocks(chapter);
    idx['plan_blocks'] = blocks.length;
    // 预估章总时长（给边播边合成的进度条一个像样的总长）
    idx['est_ms'] ??= () {
      var sec = 0.0;
      for (final block in blocks) {
        for (final seg in block) {
          sec += estSec(seg);
        }
      }
      sec += blocks.length * 0.35 + chapter.segments.length * 0.15;
      return (sec * 1000).round();
    }();
    var posMs = (idx['total_ms'] as num?)?.toInt() ?? 0;
    final cloudOn = await CloudTts.available();
    final wantBackend = cloudOn ? 'edge' : 'local';
    // 音色来源被切换过：本章已渲的部分是另一种后端。一章里中途换人比从头再渲更糟，
    // 所以只保留已经渲完的章（音频已在本机，不再联网），渲了一半的整章重来。
    final hadBackend = idx['backend'] as String? ?? _firstBackend(idx);
    if (idx['done'] != true &&
        hadBackend != null &&
        hadBackend != wantBackend &&
        (idx['blocks'] as List).isNotEmpty) {
      idx = <String, dynamic>{
        'seq': seq, 'blocks': <dynamic>[], 'done': false,
        'plan_blocks': 0, 'total_bytes': 0, 'total_ms': 0,
        'pipe': audioPipelineVersion,
      };
      try {
        final oldAudio = File(await Data.audioPcm(bid, seq));
        if (await oldAudio.exists()) await oldAudio.delete();
      } catch (_) {}
      posMs = 0;
    }
    // 已渲完的章不改记录：它确实是云端合成的，播放页那条「云端音色」不能撒谎。
    if (idx['done'] != true) idx['backend'] = wantBackend;
    final doneBlockIds = (idx['blocks'] as List)
        .map((b) => (b as Map)['bidx'] as int).toSet();
    final dirtyVer = dirtyMapVersion;
    final audioPath = await Data.audioPcm(bid, seq);
    final audioFile = File(audioPath);
    await audioFile.parent.create(recursive: true);   // 首次渲染时 audio/ 可能还不存在
    final sink = audioFile.openWrite(mode: FileMode.append);
    try {
      for (var bidx = 0; bidx < blocks.length; bidx++) {
        if (doneBlockIds.contains(bidx)) continue;
        // 块边界让位：有更高优先级任务排队时先结束本章（进度已落盘，稍后续渲）
        if (yieldCheck != null && yieldCheck()) {
          return false;
        }
        final block = blocks[bidx];
        final blockStartMs = posMs;
        final blockStartByte = posMs * RenderCfg.bytesPerMs;
        final segsMeta = <Map<String, dynamic>>[];
        final lead = (idx['blocks'] as List).isEmpty
            ? 0.10
            : RenderCfg.pauseLead;
        posMs += (lead * 1000).round();
        sink.add(Uint8List(
            (lead * RenderCfg.sampleRate).round() * RenderCfg.bytesPerSample));
        // 段级流水线：同时保持 workers 个段在跑（每个引擎一个），按顺序落盘
        final jobs = <_SegJob>[];
        for (var i = 0; i < block.length; i++) {
          final seg = block[i];
          if (!hasWord(seg.text)) continue;
          final persona = seg.speaker == null ? null : ir.personas[seg.speaker!];
          final sid = voices.resolve(seg.type, seg.speaker, persona: persona);
          final spoken = ttsNormalize(stripQuotes(seg.text));
          var edgeVoice = '';
          var edgeRate = 1.0;
          var edgePitch = '+0Hz';
          if (cloudOn) {
            final prof = CloudTts.profile(
                narration: seg.type == 'narration',
                gender: persona?.gender ?? guessGenderName(seg.speaker),
                age: persona?.age,
                type: persona?.type,
                speaker: seg.speaker);
            edgeVoice = prof.voice;
            edgeRate = prof.rate;
            edgePitch = prof.pitch;
          }
          final voiceKey = cloudOn
              ? 'edge:$edgeVoice:${edgeRate.toStringAsFixed(2)}:$edgePitch'
              : 'k$sid';
          final key = cacheKey(spoken, voiceKey, dirtyVer);
          final cp = await Data.cachePath(key);
          jobs.add(_SegJob(spoken, sid, key, cp, seg.seq, seg.type,
              seg.speaker, seg.para, cloudOn, display: seg.text,
              edgeVoice: edgeVoice, edgeRate: edgeRate, edgePitch: edgePitch));
        }
        final depth = engine.workerCount.clamp(1, 4);
        final inflight = <int, Future<_SegOut>>{};
        var failStreak = 0;
        for (var n = 0; n < jobs.length; n++) {
          final job = jobs[n];
          Uint8List? pcm;
          if (await File(job.cp).exists()) {
            final cached = await File(job.cp).readAsBytes();
            if (cached.isNotEmpty) pcm = cached;
          }
          if (pcm != null) continue;
          // 补满流水线：往后找未命中缓存的段派发。
          // 返回值带上「这段音频实际是谁合成的」——云端失败会临时改用本机音色，
          // 那时的采样是 f32（本机）而不是 s16（云端），落盘也必须落在本机音色的
          // 缓存 key 下：写进 edge 的 key，下次联网就会直接命中一段 Kokoro 的声音，
          // 时间轴还标着「云端音色」。
          Future<_SegOut> dispatch(_SegJob j) async {
            if (j.cloud) {
              final r = await CloudTts.synth(j.text, j.edgeVoice,
                  rate: j.edgeRate, pitch: j.edgePitch, outPath: '${j.cp}.tmp');
              if (r.ok) {
                return _SegOut(
                  TtsReply(0, true,
                      sampleRate: RenderCfg.sampleRate,
                      numSamples: r.numSamples),
                  cloud: true,
                  tmp: '${j.cp}.tmp',
                  cp: j.cp,
                );
              }
              final lcp =
                  await Data.cachePath(cacheKey(j.text, 'k${j.sid}', dirtyVer));
              return _SegOut(
                await engine.synth(j.text, j.sid,
                    speed: 1.0, outPath: '$lcp.tmp'),
                cloud: false,
                tmp: '$lcp.tmp',
                cp: lcp,
              );
            }
            return _SegOut(
              await engine.synth(j.text, j.sid,
                  speed: 1.0, outPath: '${j.cp}.tmp'),
              cloud: false,
              tmp: '${j.cp}.tmp',
              cp: j.cp,
            );
          }

          if (inflight[n] == null) {
            inflight[n] = dispatch(job);
          }
          for (var k = n + 1; k < jobs.length && inflight.length < depth; k++) {
            if (inflight.containsKey(k)) continue;
            if (await File(jobs[k].cp).exists()) continue;
            inflight[k] = dispatch(jobs[k]);
          }
          final out = await inflight.remove(n)!;
          final reply = out.reply;
          if (!reply.ok || reply.numSamples == 0) {
            failStreak++;
            if (failStreak >= 5) {
              idx['error'] = '连续 5 段合成失败：${reply.error ?? '未知原因'}';
              break;
            }
            continue;
          }
          failStreak = 0;
          final raw = await File(out.tmp).readAsBytes();
          Float32List samples;
          if (out.cloud) {
            final i16 = Int16List.view(
                raw.buffer, raw.offsetInBytes, raw.lengthInBytes ~/ 2);
            samples = Float32List(i16.length);
            for (var q = 0; q < i16.length; q++) {
              samples[q] = i16[q] / 32768.0;
            }
            samples = shapeCloud(samples);
          } else {
            samples = Float32List.view(
                raw.buffer, raw.offsetInBytes, raw.lengthInBytes ~/ 4);
            samples = shapeAudio(samples);
          }
          pcm = _f32ToS16(samples);
          final prevSid = n > 0 ? jobs[n - 1].sid : null;
          final nextSid = n + 1 < jobs.length ? jobs[n + 1].sid : null;
          pcm = crossFadeEdges(pcm, sampleRate: RenderCfg.sampleRate, voiceFadeMs: RenderCfg.voiceFadeMs,
              fadeIn: prevSid != null && prevSid != job.sid,
              fadeOut: nextSid != null && nextSid != job.sid);
          await File(out.tmp).rename(out.cp);
          sink.add(pcm);
          final durMs = pcm.length ~/ RenderCfg.bytesPerMs;
          segsMeta.add({
            'seq': job.seq, 'start_ms': posMs, 'end_ms': posMs + durMs,
            'voice': job.sid, 'type': job.type, 'speaker': job.speaker,
            // 索引里存原文：播放页显示的必须是书里那句话，不是送进引擎的规整文本
            'backend': out.cloud ? 'edge' : 'local',
            'text': job.display.isEmpty ? job.text : job.display,
          });
          posMs += durMs;
          final nxtJob = n + 1 < jobs.length ? jobs[n + 1] : null;
          final pause = nxtJob == null || nxtJob.para != job.para
              ? RenderCfg.pausePara
              : (nxtJob.type != job.type || nxtJob.speaker != job.speaker
                  ? RenderCfg.pauseVoice
                  : RenderCfg.pauseSent);
          if (pause > 0) {
            sink.add(Uint8List(
                (pause * RenderCfg.sampleRate).round() * RenderCfg.bytesPerSample));
            posMs += (pause * 1000).round();
          }
        }
        (idx['blocks'] as List).add({
          'bidx': bidx,
          'start_byte': blockStartByte,
          'bytes': (posMs - blockStartMs) * RenderCfg.bytesPerMs,
          'segs': segsMeta,
        });
        idx['total_ms'] = posMs;
        idx['total_bytes'] = posMs * RenderCfg.bytesPerMs;
        await Data.writeIndex(bid, seq, idx);
      }
      idx['done'] = idx['error'] == null;
      idx['pipe'] = audioPipelineVersion;
      await Data.writeIndex(bid, seq, idx);
      return idx['error'] == null;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }
}

Uint8List _f32ToS16(Float32List samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.view(out.buffer);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(),
        Endian.little);
  }
  return out;
}

/// 老索引没记章级 backend：从第一段的 segs 里倒推。
String? _firstBackend(Map<String, dynamic> idx) {
  for (final b in idx['blocks'] as List) {
    final segs = (b as Map)['segs'] as List?;
    if (segs != null && segs.isNotEmpty) {
      return (segs.first as Map)['backend'] as String?;
    }
  }
  return null;
}

/// 一段合成的实际结果：谁合成的、临时文件在哪、应该落到哪个缓存路径。
class _SegOut {
  final TtsReply reply;
  final bool cloud;
  final String tmp;
  final String cp;
  const _SegOut(this.reply, {required this.cloud, required this.tmp,
      required this.cp});
}

class _SegJob {
  final String text;        // 送进引擎的规整文本
  final String display;     // 书里的原话（含引号），写进索引给播放页显示
  final int sid;            // 本地 Kokoro 音色（回退/时间轴展示）
  final String key;
  final String cp;
  final int seq;
  final String type;
  final String? speaker;
  final int para;
  final bool cloud;
  final String edgeVoice;
  final double edgeRate;
  final String edgePitch;
  _SegJob(this.text, this.sid, this.key, this.cp, this.seq, this.type,
      this.speaker, this.para, this.cloud,
      {this.display = '',
      this.edgeVoice = '',
      this.edgeRate = 1.0,
      this.edgePitch = '+0Hz'});
}

