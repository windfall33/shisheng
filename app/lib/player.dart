// 拾声 v4 · 播放器：本地虚拟 WAV 流（边合成边播）+ 句级高亮 + 续播 + 变速 + 睡眠定时。
// 书卷版式：封面/当前句是主角，金色只做动词。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'boot.dart';
import 'design.dart';
import 'globals.dart' show audioPlayer, prefs;
import 'models.dart';
import 'playback.dart';
import 'render.dart';
import 'screens.dart' show ChaptersScreen, SettingsScreen;
import 'settings.dart';
import 'store.dart';
import 'ui_kit.dart';

Route<void> playerRoute(Widget page) => PageRouteBuilder<void>(
  transitionDuration: AppMotion.hero,
  reverseTransitionDuration: AppMotion.base,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: .965, end: 1).animate(curved),
        child: child,
      ),
    );
  },
);

class PlayerScreen extends StatefulWidget {
  final BookItem book;
  final int startSeq;
  final int startMs;
  final bool attach;
  final bool previewOnly;
  final String? previewText;
  final String? previewNext;

  /// 只给截图/预览用：直接喂段落文本，绕开索引里的时间轴。
  final List<List<String>>? previewParagraphs;

  /// 只给截图/预览用：喂一条带真实时间戳的分句表
  /// （text / start_ms / end_ms / type / speaker / backend），
  /// 让正文高亮和进度条跟着一段真音频走，而不是按固定 3.2 秒假推。
  final List<Map<String, dynamic>>? previewTimeline;

  /// 只给截图/预览用：把时间轴定在某一毫秒。逐帧取图时每帧换一个值。
  final int? previewAtMs;

  /// 只给截图/预览用：中间那行状态文字（还没合成完时是「边播边合成 7/12 块」）。
  final String? previewRenderStat;

  const PlayerScreen({
    super.key,
    required this.book,
    required this.startSeq,
    this.startMs = 0,
    this.attach = false,
    this.previewOnly = false,
    this.previewText,
    this.previewNext,
    this.previewParagraphs,
    this.previewTimeline,
    this.previewAtMs,
    this.previewRenderStat,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int seq = 0;
  List<Map<String, dynamic>> timeline = <Map<String, dynamic>>[];
  Map<String, dynamic>? curSeg;
  Map<String, dynamic>? nextSeg;
  String renderStat = '';
  double speed = 1.0;
  Timer? detailTimer;
  bool buffering = false;
  bool waiting = false;
  int playToken = 0;
  DateTime? _pausedAt;
  bool _wasPlaying = false;
  DateTime? _lastNpPosition;
  final ScrollController _pageScroll = ScrollController();
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];
  bool _claimed = false;
  String? _loadedBid;
  int? _loadedSeq;
  bool _switching = false;
  DateTime? _lastSaveAt;

  final NowPlaying now = NowPlaying.instance;

  String get title {
    final c = widget.book.ir.chapter(seq);
    return c?.title ?? '';
  }

  bool hasNext(int s) => widget.book.ir.chapters.any((c) => c.seq == s + 1);

  bool get _isOwner => mounted && PlaybackSession.instance.owns(this);

  bool get _audioMatches =>
      _loadedBid == widget.book.bid && _loadedSeq == seq;

  @override
  void initState() {
    super.initState();
    if (widget.previewOnly) {
      speed = 1.0;
      seq = widget.startSeq;
      curSeg = <String, dynamic>{
        'text': widget.previewText ?? '正在准备音频…',
        'type': 'narration',
        'seq': 0,
      };
      nextSeg = <String, dynamic>{
        'text': widget.previewNext ?? '',
        'type': 'dialogue',
        'speaker': '王生',
        'seq': 1,
      };
      // 合成完了就不用再报一遍「已完整合成」：中间那格只留给还没好的事。
      renderStat = widget.previewRenderStat ?? '';
      final real = widget.previewTimeline;
      if (real != null && real.isNotEmpty) {
        // 真时间轴：高亮和进度都跟着它走，取图时每帧只换 previewAtMs。
        timeline = real;
        final at = widget.previewAtMs ?? (real.first['start_ms'] as num).toInt();
        _highlightAt(at);
        now.setDuration(
          Duration(milliseconds: (real.last['end_ms'] as num).toInt()),
        );
        now.setPosition(Duration(milliseconds: at));
        now.setPlaying(true);
        now.setStatus(renderStat);
        now.setBook(widget.book, seq, title);
        return;
      }
      final paras = widget.previewParagraphs;
      if (paras != null && paras.isNotEmpty) {
        // 造一条只有时间戳的假时间轴，让正文走真实的段落排版路径。
        var ms = 0;
        final tl = <Map<String, dynamic>>[];
        for (final p in paras) {
          for (final s in p) {
            tl.add(<String, dynamic>{
              'seq': 0,
              'start_ms': ms,
              'end_ms': ms + 3200,
              'type': 'narration',
              'text': s,
            });
            ms += 3200;
          }
          ms += 400;
        }
        timeline = tl;
        final mid = paras.length > 1 ? paras.first.length : 0;
        curSeg = mid < tl.length ? tl[mid] : tl.first;
        nextSeg = tl.indexOf(curSeg!) + 1 < tl.length
            ? tl[tl.indexOf(curSeg!) + 1]
            : null;
      }
      now.setBook(widget.book, seq, title);
      now.setDuration(const Duration(minutes: 28));
      now.setPosition(const Duration(minutes: 12, seconds: 34));
      now.setPlaying(true);
      now.setStatus(renderStat);
      return;
    }
    speed = prefs.getDouble('speed') ?? AppSettings.instance.defaultSpeed.value;
    // 只有栈顶播放器页能碰全局 audioPlayer。后压上来的页会接管，
    // 旧页仍在栈里时只负责显示，不再自动续章、不再写进度。
    PlaybackSession.instance.claim(this);
    _claimed = true;

    if (widget.attach && now.book?.bid == widget.book.bid) {
      seq = now.seq;
      now.setBook(widget.book, seq, title);
      now.setSpeed(speed);
      _loadDetailLoop(seq);
      detailTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _loadDetailLoop(seq),
      );
      if (audioPlayer.audioSource == null) {
        unawaited(playChapter(seq, seekMs: now.position.inMilliseconds));
      } else {
        _loadedBid = widget.book.bid;
        _loadedSeq = seq;
        if (audioPlayer.duration != null) {
          now.setDuration(audioPlayer.duration!);
        }
        _updateHighlight(audioPlayer.position);
      }
    } else {
      unawaited(playChapter(widget.startSeq, seekMs: widget.startMs));
    }

    _subs.add(audioPlayer.positionStream.listen((pos) {
      // 旧页收不到新音源的事件；即使收到，也不许写全局进度。
      if (!_isOwner) return;
      if (_loadedSeq != null && !_audioMatches) return;
      final tick = DateTime.now();
      if (_lastNpPosition == null ||
          tick.difference(_lastNpPosition!).inMilliseconds >= 500) {
        _lastNpPosition = tick;
        now.setPosition(pos);
      }
      _saveProgress(pos);
      _updateHighlight(pos);
    }));
    _subs.add(audioPlayer.durationStream.listen((d) {
      if (!_isOwner || _loadedSeq == null || !_audioMatches) return;
      if (d != null) now.setDuration(d);
    }));
    _subs.add(audioPlayer.playingStream.listen((playing) {
      if (!_isOwner) return;
      now.setPlaying(playing);
      if (!playing) {
        // 切章时的 stop 不是「用户暂停」，不能拿它做 5 秒回退。
        if (!_switching) _pausedAt = DateTime.now();
      } else {
        if (!_wasPlaying &&
            _pausedAt != null &&
            AppSettings.instance.autoRewind.value &&
            !_switching &&
            _audioMatches) {
          final gap = DateTime.now().difference(_pausedAt!);
          if (gap > const Duration(seconds: 30)) {
            final target = audioPlayer.position - const Duration(seconds: 5);
            unawaited(
              audioPlayer.seek(target < Duration.zero ? Duration.zero : target),
            );
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已回退 5 秒，接上刚才那句')));
            }
          }
        }
        _pausedAt = null;
      }
      _wasPlaying = playing;
      if (mounted) setState(() {});
    }));
    _subs.add(audioPlayer.playerStateStream.listen((st) {
      if (!_isOwner) return;
      final b = st.processingState == ProcessingState.buffering;
      now.setBuffering(b);
      if (buffering != b && mounted) setState(() => buffering = b);
    }));
    _subs.add(audioPlayer.playerStateStream.listen((st) {
      if (st.processingState != ProcessingState.completed) return;
      // 只有「这一页、这一章、这段音源」播完才续章。旧页的 completed
      // 事件、切章中途的 completed 事件都不能改当前播放。
      if (!_isOwner || _switching || waiting || !_audioMatches) return;
      if (PlaybackSleep.instance.endOfChapter) {
        unawaited(audioPlayer.pause());
        PlaybackSleep.instance.cancel();
        return;
      }
      if (hasNext(seq)) unawaited(playChapter(seq + 1));
    }));
  }

  @override
  void dispose() {
    detailTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (_claimed) PlaybackSession.instance.release(this);
    _pageScroll.dispose();
    super.dispose();
  }

  Future<void> _saveProgress(Duration pos) async {
    if (!_isOwner || !_audioMatches) return;
    final now = DateTime.now();
    if (_lastSaveAt != null &&
        now.difference(_lastSaveAt!).inMilliseconds < 1500) {
      return;
    }
    _lastSaveAt = now;
    await Data.saveProgress(widget.book.bid, <String, dynamic>{
      'seq': seq,
      'pos_ms': pos.inMilliseconds,
      'updated_at': now.millisecondsSinceEpoch / 1000,
    });
    await prefs.setString(
      'last',
      '{"bid":${_jstr(widget.book.bid)},"title":${_jstr(widget.book.title)},'
          '"seq":$seq,"pos":${pos.inMilliseconds},'
          '"t":${now.millisecondsSinceEpoch}}',
    );
  }

  String _jstr(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// 在时间轴上找 ms 落在哪一句，只改状态不 setState（initState 里用）。
  void _highlightAt(int ms) {
    if (timeline.isEmpty) return;
    Map<String, dynamic>? cur;
    for (final s in timeline) {
      if (ms >= (s['start_ms'] as num).toInt() &&
          ms < (s['end_ms'] as num).toInt()) {
        cur = s;
        break;
      }
      if ((s['start_ms'] as num).toInt() > ms) {
        cur = s;
        break;
      }
    }
    cur ??= timeline.last;
    final i = timeline.indexOf(cur);
    curSeg = cur;
    nextSeg = i + 1 < timeline.length ? timeline[i + 1] : null;
  }

  Future<void> _updateHighlight(Duration pos) async {
    if (timeline.isEmpty || !mounted) return;
    final ms = pos.inMilliseconds;
    Map<String, dynamic>? cur;
    for (final s in timeline) {
      if (ms >= (s['start_ms'] as num).toInt() &&
          ms < (s['end_ms'] as num).toInt()) {
        cur = s;
        break;
      }
      if ((s['start_ms'] as num).toInt() > ms) {
        cur = s;
        break;
      }
    }
    Map<String, dynamic>? nxt;
    if (cur != null) {
      final i = timeline.indexOf(cur);
      if (i + 1 < timeline.length) nxt = timeline[i + 1];
    }
    if (cur != null && !identical(cur, curSeg)) {
      setState(() {
        curSeg = cur;
        nextSeg = nxt;
      });
    }
  }

  Future<void> _loadDetailLoop(int s) async {
    final idx = await Data.readIndex(widget.book.bid, s);
    if (!_isOwner || seq != s) return;
    if (idx == null) {
      setState(() => renderStat = '正在合成第一块…');
      now.setStatus(renderStat);
      return;
    }
    final tl = <Map<String, dynamic>>[];
    for (final b in (idx['blocks'] as List)) {
      for (final e in (((b as Map)['segs'] ?? []) as List)) {
        tl.add(Map<String, dynamic>.from(e as Map));
      }
    }
    timeline = tl;
    final done = idx['done'] == true;
    if (done) detailTimer?.cancel();
    final backends = tl.map((e) => e['backend']).toSet();
    final edge = backends.contains('edge');
    final voiceStudio = backends.contains('voicestudio');
    final sourceTag = voiceStudio
        ? '，VoiceStudio 音色'
        : (edge ? '，云端音色' : '');
    setState(() {
      // 合成完了就不必再报一遍「已完整合成」——那行只在还没好、或音色来自云端时才有话说。
      renderStat = done
          ? (voiceStudio
              ? 'VoiceStudio 音色'
              : (edge ? '云端音色' : ''))
          : '边播边合成 ${(idx['blocks'] as List).length}/${idx['plan_blocks']} 块$sourceTag';
    });
    now.setStatus(renderStat);
    if (idx['total_ms'] != null) {
      now.setDuration(Duration(milliseconds: (idx['total_ms'] as num).toInt()));
    }
    _updateHighlight(audioPlayer.position);
  }

  Future<void> playChapter(int s, {int seekMs = 0}) async {
    final chapter = widget.book.ir.chapter(s);
    if (chapter == null) return;
    if (!PlaybackSession.instance.owns(this)) return;
    final token = ++playToken;
    _switching = true;
    _loadedBid = null;
    _loadedSeq = null;
    _pausedAt = null;
    _wasPlaying = false;
    _lastSaveAt = null;
    waiting = false;
    detailTimer?.cancel();
    setState(() {
      seq = s;
      curSeg = nextSeg = null;
      timeline = <Map<String, dynamic>>[];
    });
    now.setBook(widget.book, s, chapter.title);
    now.setStatus('正在准备音频…');
    detailTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadDetailLoop(s),
    );
    unawaited(_loadDetailLoop(s));

    // 先把旧章停掉，再去做任何可能耗时的事（读进度、等引擎、等首块）。
    // 否则等第一集合成的那几十秒里，第三集还在后台响，甚至播完触发续章。
    try {
      await audioPlayer.stop();
    } catch (_) {}
    if (token != playToken || !mounted) return;

    if (Boot.preview) {
      await Future<void>.delayed(
        const Duration(milliseconds: 400),
        () => _loadDetailLoop(s),
      );
      if (timeline.length > 2 && mounted) {
        setState(() {
          curSeg = timeline[1];
          nextSeg = timeline[2];
        });
      }
      _switching = false;
      return;
    }

    if (seekMs == 0) {
      try {
        final p = await Data.loadProgress(widget.book.bid);
        final pos = (p['pos_ms'] as num?)?.toInt() ?? 0;
        if ((p['seq'] as num?)?.toInt() == s && pos > 3000) {
          final idx = await Data.readIndex(widget.book.bid, s);
          final rendered = (idx?['total_ms'] as num?)?.toInt() ?? 0;
          seekMs = (pos < rendered - 5000) ? pos : 0;
        }
      } catch (_) {}
    }

    await Renderer.ensure(() => Boot.tts);
    if (token != playToken || !mounted || !_isOwner) return;
    await Renderer.instance.focus(widget.book.bid, s);
    if (token != playToken || !mounted || !_isOwner) return;
    for (var k = 1; k <= 3; k++) {
      if (widget.book.ir.chapter(s + k) != null) {
        unawaited(
          Renderer.instance.touch(widget.book.bid, s + k, Renderer.priUser),
        );
      }
    }

    setState(() => waiting = true);
    now.setStatus('正在准备音频…');

    final bufferMs = (30000 * speed).round();
    final waitStart = DateTime.now();
    Map<String, dynamic>? widx;
    var hasData = false;
    while (DateTime.now().difference(waitStart).inSeconds <= 120) {
      widx = await Data.readIndex(widget.book.bid, s);
      final gotMs = (widx?['total_ms'] as num?)?.toInt() ?? 0;
      final fresh = widx?['pipe'] == audioPipelineVersion;
      final done = widx?['done'] == true && fresh;
      hasData =
          widx != null &&
          fresh &&
          ((widx['blocks'] as List?)?.isNotEmpty ?? false) &&
          (gotMs >= bufferMs || done);
      if (hasData || token != playToken || !mounted) break;
      if (widx != null &&
          widx['blocks'] is List &&
          (widx['blocks'] as List).isNotEmpty) {
        setState(
          () => renderStat =
              '正在缓冲 ${(gotMs / 1000).round()}/${(bufferMs / 1000).round()} 秒',
        );
        now.setStatus(renderStat);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (token != playToken || !mounted || !_isOwner) return;
    if (!hasData) {
      setState(() => waiting = false);
      _switching = false;
      final err = widx?['error'];
      setState(() => renderStat = err != null ? '合成失败' : '等待超时');
      now.setStatus(renderStat);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err != null
                ? '合成失败了：$err。重启 App 再试，仍不行请告诉我书名'
                : '90 秒没等到合成结果。点重试再等一轮；反复出现请重启 App 并告诉我',
          ),
        ),
      );
      return;
    }

    final url = Boot.server.audioUrl(widget.book.bid, s);
    final src = AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(
        id: '${widget.book.bid}:$s',
        title: title,
        album: widget.book.title,
        artist: '拾声',
      ),
    );
    try {
      await audioPlayer.setAudioSource(src);
      if (token != playToken || !mounted || !_isOwner) return;
      _loadedBid = widget.book.bid;
      _loadedSeq = s;
      _switching = false;
      setState(() {
        waiting = false;
        if (widx?['total_ms'] != null) {
          now.setDuration(
            Duration(milliseconds: (widx!['total_ms'] as num).toInt()),
          );
        }
      });
      await audioPlayer.setSpeed(speed);
      now.setSpeed(speed);
      if (seekMs > 0) await audioPlayer.seek(Duration(milliseconds: seekMs));
      await audioPlayer.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (token != playToken || !mounted) return;
      _switching = false;
      setState(() => waiting = false);
      now.setStatus('播放失败');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => playChapter(s, seekMs: seekMs),
          ),
        ),
      );
    }
  }

  /// 把底层异常翻译成人话 + 出路。
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('render not started') || msg.contains('503')) {
      return '语音引擎还没准备好，等几秒再点重试';
    }
    if (msg.contains('timeout') ||
        msg.contains('Timeout') ||
        msg.contains('408')) {
      return '这一段合成有点慢，已插队优先，稍等再试';
    }
    return '播放失败，点重试；若反复出现请重启 App';
  }

  int _estTotalMs() {
    final c = widget.book.ir.chapter(seq);
    if (c == null) return 0;
    var ch = 0;
    for (final s in c.segments) {
      ch += s.text.length;
    }
    return (ch / 4.3 * 1000).round();
  }

  void _applySpeed(double value) {
    final v = value.clamp(0.5, 3.0);
    speed = v;
    unawaited(prefs.setDouble('speed', v));
    unawaited(audioPlayer.setSpeed(v));
    now.setSpeed(v);
    if (mounted) setState(() {});
  }

  String _speedLabel(double v) {
    final s = v.toStringAsFixed(2);
    final trimmed = s.endsWith('0') ? s.substring(0, s.length - 1) : s;
    return '${trimmed}x';
  }

  String get _sleepLabel {
    if (PlaybackSleep.instance.endOfChapter) return '本章结束';
    final at = now.sleepAt;
    if (at == null) return '定时';
    final left = at.difference(DateTime.now());
    final m = left.inMinutes;
    final s = (left.inSeconds % 60).clamp(0, 59);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _skip(int seconds) {
    final target = audioPlayer.position + Duration(seconds: seconds);
    unawaited(
      audioPlayer.seek(target < Duration.zero ? Duration.zero : target),
    );
  }

  Future<void> _openChapters() async {
    // 从播放器进目录时不叠第二个播放器页：目录只把选中的章号带回来，
    // 由当前页自己切章。否则旧页留在栈里，退出新页后会看到错章。
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => ChaptersScreen(
          book: widget.book,
          activeSeq: seq,
          pickOnly: true,
        ),
      ),
    );
    if (picked != null && mounted) {
      await playChapter(picked);
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _showSleepSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xxl,
            AppSpace.sm,
            AppSpace.xxl,
            AppSpace.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '睡眠定时',
                style: AppType.book.copyWith(color: AppTokens.of(ctx).text),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                PlaybackSleep.instance.active
                    ? '还剩 $_sleepLabel 后暂停，最后 20 秒淡出。'
                    : '到点后声音渐弱并暂停，适合睡前。',
                style: AppType.body.copyWith(
                  color: AppTokens.of(ctx).muted,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: <Widget>[
                  for (final m in <int>[15, 30, 45, 60])
                    AppPill(
                      '$m 分钟',
                      selected: now.sleepMinutes == m && now.sleepAt != null,
                      onTap: () {
                        PlaybackSleep.instance.startMinutes(m);
                        Navigator.pop(ctx);
                      },
                    ),
                  AppPill(
                    '本章结束',
                    selected: PlaybackSleep.instance.endOfChapter,
                    onTap: () {
                      PlaybackSleep.instance.startEndOfChapter();
                      Navigator.pop(ctx);
                    },
                  ),
                  if (PlaybackSleep.instance.active)
                    AppPill(
                      '+5 分钟',
                      onTap: () {
                        PlaybackSleep.instance.addMinutes(5);
                        Navigator.pop(ctx);
                      },
                    ),
                  if (PlaybackSleep.instance.active)
                    AppPill(
                      '关闭定时',
                      onTap: () {
                        PlaybackSleep.instance.cancel();
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSpeedSheet() async {
    var temp = speed;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xxl,
              AppSpace.sm,
              AppSpace.xxl,
              AppSpace.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '播放语速',
                      style: AppType.book.copyWith(
                        color: AppTokens.of(ctx).text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _speedLabel(temp),
                      style: AppType.readout.copyWith(
                        color: AppTokens.of(ctx).gold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: temp,
                  min: .5,
                  max: 3,
                  divisions: 50,
                  onChanged: (v) {
                    setSheet(() => temp = v);
                    _applySpeed(v);
                  },
                ),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: <Widget>[
                    for (final s in <double>[0.75, 1.0, 1.25, 1.5, 2.0, 2.5])
                      AppPill(
                        _speedLabel(s),
                        selected: (temp - s).abs() < .01,
                        onTap: () {
                          setSheet(() => temp = s);
                          _applySpeed(s);
                        },
                      ),
                    AppPill(
                      '恢复 1.0x',
                      onTap: () {
                        setSheet(() => temp = 1.0);
                        _applySpeed(1.0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFullText() async {
    final t = AppTokens.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface,
      builder: (ctx) {
        final tt = AppTokens.of(ctx);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .72,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xxl,
                AppSpace.sm,
                AppSpace.xxl,
                AppSpace.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.isEmpty ? '第 ${seq + 1} 章' : title,
                    style: AppType.caption.copyWith(
                      color: tt.goldText,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    curSeg?['text'] ?? '',
                    style: AppType.reading.copyWith(
                      height: 2.0,
                      color: tt.text,
                    ),
                  ),
                  if (nextSeg != null) ...<Widget>[
                    const SizedBox(height: AppSpace.lg),
                    // 分隔用 line，不用半透明金：金色只标「正在播」，不做装饰线。
                    Container(height: .5, color: tt.line),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      nextSeg?['text'] ?? '',
                      style: AppType.body.copyWith(
                        color: tt.muted,
                        height: 1.8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMore() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.list_rounded),
              title: const Text('章节目录'),
              onTap: () {
                Navigator.pop(ctx);
                _openChapters();
              },
            ),
            ListTile(
              leading: const Icon(Icons.nightlight_round),
              title: const Text('睡眠定时'),
              onTap: () {
                Navigator.pop(ctx);
                _showSleepSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('播放语速'),
              onTap: () {
                Navigator.pop(ctx);
                _showSpeedSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('播放设置'),
              onTap: () {
                Navigator.pop(ctx);
                _openSettings();
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
  }


  String _whoTag() {
    final s = curSeg;
    if (s == null) return '';
    return s['type'] == 'narration' ? '旁白' : ((s['speaker'] ?? '对白') as String);
  }

  Widget _progressBlock(AppTokens t, Duration duration) {
    return StreamBuilder<Duration>(
      stream: audioPlayer.positionStream,
      initialData: audioPlayer.position,
      builder: (ctx, snap) {
        final pos = widget.previewOnly
            ? now.position
            : (waiting ? Duration.zero : (snap.data ?? Duration.zero));
        final totalMs = duration.inMilliseconds;
        final value = totalMs > 0
            ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;
        final remain = duration - pos;
        return Column(
          children: <Widget>[
              // 条尾给一个终点刻度：否则「还剩 15:26」在画面上找不到对应的长度。
              Stack(
                children: <Widget>[
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      padding: EdgeInsets.zero,
                      trackHeight: 3,
                      activeTrackColor: t.gold,
                      inactiveTrackColor: t.track,
                      thumbColor: t.gold,
                      overlayColor: t.gold.withValues(alpha: .12),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: value,
                      onChanged: waiting
                          ? null
                          : (v) => audioPlayer.seek(duration * v),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(width: 1, height: 9, color: t.track),
                    ),
                  ),
                ],
              ),
            Row(
              children: <Widget>[
                Text(fmt(pos), style: AppType.time.copyWith(color: t.muted)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm,
                    ),
                    child: Text(
                      renderStat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppType.caption.copyWith(
                        color: t.faint,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ),
                Text(
                  '-${fmt(remain)}',
                  style: AppType.time.copyWith(color: t.muted),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final duration = widget.previewOnly
        ? (now.duration.inMilliseconds > 0
              ? now.duration
              : Duration(milliseconds: _estTotalMs()))
        : (audioPlayer.duration ?? Duration(milliseconds: _estTotalMs()));

    var curText = '';
    var nextText = '';
    var curIndex = -1;
    final c = curSeg;
    if (c != null) {
      curText = (c['text'] ?? '').toString();
      nextText = (nextSeg?['text'] ?? '').toString();
      curIndex = timeline.indexOf(c);
    }
    final who = _whoTag();
    // 章名里已经带了「第 N 章」，下面这一行就别再重复一次章号。
    final headHasNo = RegExp(r'^第\s*[0-9０-９一二三四五六七八九十百千零两]+\s*[章回节]')
        .hasMatch(title);
    final by = <String>[
      widget.book.title,
      if (!headHasNo) '第 ${seq + 1} 章',
      if (who.isNotEmpty) who,
    ].join(' · ');

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    children: <Widget>[
                      _TopIcon(
                        icon: Icons.arrow_back_ios_new_rounded,
                        label: '返回',
                        onTap: () => Navigator.maybePop(context),
                      ),
                      const Spacer(),
                      _TopIcon(
                        icon: Icons.more_horiz_rounded,
                        label: '更多',
                        onTap: _showMore,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xxl,
                    AppSpace.sm,
                    AppSpace.xxl,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title.isEmpty ? '第 ${seq + 1} 章' : title,
                        style: AppType.display.copyWith(color: t.text),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        by,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta.copyWith(color: t.faint),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, box) => SingleChildScrollView(
                      controller: _pageScroll,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xxl,
                        AppSpace.lg,
                        AppSpace.xxl,
                        AppSpace.md,
                      ),
                      child: ConstrainedBox(
                        // 段落不满一屏时垂直居中，别把正文晾在顶上留一大块空。
                        constraints: BoxConstraints(
                          minHeight: box.maxHeight - AppSpace.lg - AppSpace.md,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _ReadingPage(
                              timeline: timeline,
                              curIndex: curIndex,
                              fallback: curText.isEmpty ? '正在准备音频…' : curText,
                              fallbackNext: nextText,
                              onTapCurrent: curText.length > 36
                                  ? _showFullText
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
                  child: _progressBlock(t, duration),
                ),
                const SizedBox(height: AppSpace.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _SkipButton(
                      seconds: AppSettings.instance.skipSeconds.value,
                      back: true,
                      onTap: () =>
                          _skip(-AppSettings.instance.skipSeconds.value),
                    ),
                    const SizedBox(width: 40),
                    _MainButton(
                      playing: now.playing,
                      onTap: () {
                        if (now.playing) {
                          unawaited(audioPlayer.pause());
                        } else {
                          unawaited(audioPlayer.play());
                        }
                      },
                    ),
                    const SizedBox(width: 40),
                    _SkipButton(
                      seconds: AppSettings.instance.skipSeconds.value,
                      back: false,
                      onTap: () =>
                          _skip(AppSettings.instance.skipSeconds.value),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                _OptsRow(
                  speedLabel: _speedLabel(speed),
                  speedActive: (speed - 1.0).abs() > .01,
                  sleepLabel: _sleepLabel,
                  sleepActive: PlaybackSleep.instance.active,
                  onSpeed: _showSpeedSheet,
                  onSleep: _showSleepSheet,
                  onChapters: _openChapters,
                  onSettings: _openSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TopIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 18, color: t.text),
        ),
      ),
    );
  }
}

/// 正文页：按段落排版，当前句最亮，其余句子暗一档但仍然可读。
///
/// 索引里没有段落字段，只能从相邻句的时间空隙推断：渲染时段间停顿
/// [RenderCfg.pausePara]（350ms）明显大于句间与换声停顿，因此 gap ≥ 300ms
/// 视为换段；对白以引号开头且上一句已收尾时也单独成段。
class _ReadingPage extends StatefulWidget {
  final List<Map<String, dynamic>> timeline;
  final int curIndex;
  final String fallback;
  final String fallbackNext;
  final VoidCallback? onTapCurrent;

  const _ReadingPage({
    required this.timeline,
    required this.curIndex,
    required this.fallback,
    required this.fallbackNext,
    this.onTapCurrent,
  });

  @override
  State<_ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<_ReadingPage> {
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  static const String _indent = '　　';

  @override
  void didUpdateWidget(_ReadingPage old) {
    super.didUpdateWidget(old);
    if (old.curIndex != widget.curIndex) _revealCurrent();
  }

  @override
  void initState() {
    super.initState();
    _revealCurrent();
  }

  void _revealCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keys[widget.curIndex]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: .34,
        duration: AppMotion.base,
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _breakBefore(int i) {
    final tl = widget.timeline;
    final prev = tl[i - 1];
    final cur = tl[i];
    final gap =
        ((cur['start_ms'] as num?)?.toInt() ?? 0) -
        ((prev['end_ms'] as num?)?.toInt() ?? 0);
    if (gap >= 300) return true;
    final pt = (prev['text'] ?? '').toString();
    final ct = (cur['text'] ?? '').toString();
    const closed = '。！？…」”';
    if (ct.startsWith('“') || ct.startsWith('「')) {
      return pt.isNotEmpty && closed.contains(pt[pt.length - 1]);
    }
    return false;
  }

  /// 当前段前后各留两段做上下文，总句数封顶 30，避免长段落撑爆版面。
  List<List<int>> _window() {
    final tl = widget.timeline;
    final paras = <List<int>>[];
    for (var i = 0; i < tl.length; i++) {
      if (i == 0 || _breakBefore(i)) {
        paras.add(<int>[i]);
      } else {
        paras.last.add(i);
      }
    }
    var here = 0;
    for (var p = 0; p < paras.length; p++) {
      if (paras[p].contains(widget.curIndex)) {
        here = p;
        break;
      }
    }
    final from = (here - 2).clamp(0, paras.length - 1);
    final to = (here + 2).clamp(0, paras.length - 1);
    final out = <List<int>>[];
    var count = 0;
    for (var p = from; p <= to; p++) {
      final seg = paras[p];
      if (count > 0 && count + seg.length > 30) break;
      out.add(seg);
      count += seg.length;
    }
    return out;
  }

  TextStyle _base(AppTokens t, Color color) =>
      AppType.reading.copyWith(color: color, letterSpacing: .1);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final tl = widget.timeline;

    if (tl.isEmpty) {
      final cur = widget.fallback;
      final nxt = widget.fallbackNext;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapCurrent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$_indent$cur',
              style: _base(t, t.text).copyWith(
                fontVariations: const <FontVariation>[
                  FontVariation('wght', 480),
                ],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (nxt.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.md),
              Text('$_indent$nxt', style: _base(t, t.muted)),
            ],
          ],
        ),
      );
    }

    final paras = _window();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapCurrent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var p = 0; p < paras.length; p++) ...<Widget>[
            if (p > 0) const SizedBox(height: AppSpace.md),
            _paragraph(t, paras[p]),
          ],
        ],
      ),
    );
  }

  Widget _paragraph(AppTokens t, List<int> idxs) {
    final inPara = idxs.contains(widget.curIndex);
    final spans = <InlineSpan>[];
    for (var k = 0; k < idxs.length; k++) {
      final i = idxs[k];
      final text = (widget.timeline[i]['text'] ?? '').toString();
      if (text.isEmpty) continue;
      final isCur = i == widget.curIndex;
      final style = isCur
          ? _base(t, t.text).copyWith(
              fontVariations: const <FontVariation>[FontVariation('wght', 480)],
              fontWeight: FontWeight.w500,
            )
          : _base(t, t.muted);
      if (k == 0) {
        spans.add(TextSpan(text: _indent, style: style));
      }
      spans.add(TextSpan(text: text, style: style));
    }
    if (spans.isEmpty) return const SizedBox.shrink();
    return Container(
      key: inPara ? (_keys[widget.curIndex] ??= GlobalKey()) : null,
      child: Text.rich(
        TextSpan(children: spans),
        // 中文禁止两端对齐：会撑出难看的字间空隙。
        textAlign: TextAlign.start,
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;

  const _MainButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    // 56 的描边圆，不是 76 的实心盘：76 实心在 #0A0A0A 上有 4300 个白像素，
    // 是整页标题的五倍，夜里看就是一块手电筒。描边 + 实心字形一样按得准。
    return Semantics(
      button: true,
      label: playing ? '暂停' : '播放',
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.text, width: 1.5),
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: t.text,
          ),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  final int seconds;
  final bool back;
  final VoidCallback onTap;

  const _SkipButton({
    required this.seconds,
    required this.back,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: back ? '后退 $seconds 秒' : '前进 $seconds 秒',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // 用实线圆弧 + 镜像，不用带虚线的旋转图标：虚线在暗屏上碎成
              // 一串点，远看像加载中。数字落在圆弧中间的空档里。
              Transform.scale(
                scaleX: back ? 1 : -1,
                child: Icon(Icons.replay_rounded, size: 42, color: t.text),
              ),
              Transform.translate(
                offset: const Offset(0, 2),
                child: Text(
                  '$seconds',
                  style: AppType.caption.copyWith(
                    color: t.text,
                    letterSpacing: 0,
                    fontVariations: const <FontVariation>[
                      FontVariation('wght', 500),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptsRow extends StatelessWidget {
  final String speedLabel;
  final bool speedActive;
  final String sleepLabel;
  final bool sleepActive;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;
  final VoidCallback onChapters;
  final VoidCallback onSettings;

  const _OptsRow({
    required this.speedLabel,
    required this.speedActive,
    required this.sleepLabel,
    required this.sleepActive,
    required this.onSpeed,
    required this.onSleep,
    required this.onChapters,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line, width: .5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.xs,
          ),
          child: Row(
            children: <Widget>[
              _opt(
                context,
                speedLabel,
                speedActive,
                onSpeed,
              ),
              _opt(
                context,
                sleepLabel,
                sleepActive,
                onSleep,
              ),
              _opt(context, '设置', false, onSettings),
              _opt(context, '目录', false, onChapters),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opt(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    final t = AppTokens.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 这一行是躺下以后按得最多的四个键（倍速、定时、设置、目录），
                // 原来用 11 的小字，比正文小两倍多，摸黑根本认不出来。
                style: AppType.body.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  fontVariations: <FontVariation>[
                    FontVariation('wght', active ? 600 : 480),
                  ],
                  color: active ? t.text : t.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
