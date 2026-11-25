// 拾声 v4 · 全局“正在播放”状态：迷你播放器与播放器页共享。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'globals.dart' show audioPlayer;
import 'models.dart';

class NowPlaying extends ChangeNotifier {
  NowPlaying._();

  static final NowPlaying instance = NowPlaying._();

  BookItem? book;
  int seq = 0;
  String chapterTitle = '';
  bool playing = false;
  bool buffering = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double speed = 1.0;
  DateTime? sleepAt;
  int sleepMinutes = 0;
  bool sleepEndOfChapter = false;
  String status = '';

  bool get active => book != null;
  bool get preparing =>
      status.startsWith('正在准备') ||
      status.startsWith('正在缓冲') ||
      status.startsWith('正在合成');

  void setBook(BookItem value, int s, String title) {
    book = value;
    seq = s;
    chapterTitle = title;
    notifyListeners();
  }

  void setPlaying(bool value) {
    if (playing == value) return;
    playing = value;
    notifyListeners();
  }

  void setBuffering(bool value) {
    if (buffering == value) return;
    buffering = value;
    notifyListeners();
  }

  void setPosition(Duration value) {
    position = value;
    notifyListeners();
  }

  void setDuration(Duration value) {
    if (duration == value) return;
    duration = value;
    notifyListeners();
  }

  void setSpeed(double value) {
    if (speed == value) return;
    speed = value;
    notifyListeners();
  }

  void setSleep(DateTime? at, int minutes, {bool endOfChapter = false}) {
    sleepAt = at;
    sleepMinutes = minutes;
    sleepEndOfChapter = endOfChapter;
    notifyListeners();
  }

  void setStatus(String value) {
    if (status == value) return;
    status = value;
    notifyListeners();
  }

  void clear() {
    book = null;
    seq = 0;
    chapterTitle = '';
    playing = false;
    buffering = false;
    position = Duration.zero;
    duration = Duration.zero;
    sleepAt = null;
    sleepMinutes = 0;
    sleepEndOfChapter = false;
    status = '';
    notifyListeners();
  }
}

/// 全局播放所有权。
///
/// 播放器页可以被叠多层：从书架进播放器，再从播放器进目录，再从目录点另一章，
/// 旧页仍然挂在路由栈里。旧页的 `audioPlayer.playerStateStream` 不会自己消失，
/// 一旦上一章播完，它也会收到 `completed` 并把全局播放器切回自己那一章——
/// 这就是「明明在等第一集，过一会却响起第三集」的根因。
///
/// 这里用一个小栈记录还活着的播放器页：只有栈顶那页可以改音源、写进度、
/// 自动续章。新页压上来时旧页自动让位；新页退出后旧页重新拿回所有权。
class PlaybackSession {
  PlaybackSession._();

  static final PlaybackSession instance = PlaybackSession._();

  final List<Object> _owners = <Object>[];

  Object? get owner => _owners.isEmpty ? null : _owners.last;
  bool get hasOwner => _owners.isNotEmpty;

  void claim(Object owner) {
    _owners.removeWhere((o) => identical(o, owner));
    _owners.add(owner);
  }

  void release(Object owner) {
    _owners.removeWhere((o) => identical(o, owner));
  }

  bool owns(Object owner) =>
      _owners.isNotEmpty && identical(_owners.last, owner);
}

/// 当前 audioPlayer 里装的是不是「这本书这一章」。
///
/// 只看 `audioSource != null` 是不够的：切到还没合成的第四章时，旧音源
/// 仍然是第一章；用户点播放就会「明明在第四集，却响起第一集」。
bool audioTagMatchesChapter(Object? tag, String bid, int seq) =>
    tag is MediaItem && tag.id == '$bid:$seq';

bool audioSourceMatchesChapter(String bid, int seq) {
  final src = audioPlayer.audioSource;
  return src is UriAudioSource && audioTagMatchesChapter(src.tag, bid, seq);
}

/// 停掉并清空音源。切到未合成章后，旧章不能再被播放键唤醒。
Future<void> clearAudioSource() async {
  try {
    await audioPlayer.stop();
  } catch (_) {}
  try {
    await audioPlayer.setAudioSources(const <AudioSource>[], preload: false);
  } catch (_) {}
}

enum PlaybackTapAction { pause, resume, prepare }

/// 播放键按下去应该做什么：暂停 / 继续当前音源 / 重新准备这一章。
PlaybackTapAction playbackTapAction({
  required bool playing,
  required bool sourceMatches,
}) {
  if (playing) return PlaybackTapAction.pause;
  if (sourceMatches) return PlaybackTapAction.resume;
  return PlaybackTapAction.prepare;
}

/// 睡眠定时器独立于播放器页：收起播放器后仍然生效。
class PlaybackSleep {
  PlaybackSleep._();

  static final PlaybackSleep instance = PlaybackSleep._();

  Timer? _timer;
  DateTime? _at;
  int _minutes = 0;
  bool _endOfChapter = false;

  bool get active =>
      _at != null || _endOfChapter || NowPlaying.instance.sleepEndOfChapter;
  bool get endOfChapter => _endOfChapter;

  void startMinutes(int minutes) {
    _minutes = minutes.clamp(1, 240);
    _at = DateTime.now().add(Duration(minutes: _minutes));
    _endOfChapter = false;
    _ensureTimer();
    _publish();
  }

  void startEndOfChapter() {
    _at = null;
    _minutes = 0;
    _endOfChapter = true;
    _ensureTimer();
    _publish();
  }

  void addMinutes(int minutes) {
    if (_at != null) {
      final left = _at!.difference(DateTime.now()).inMinutes;
      startMinutes(left + minutes);
    } else {
      startMinutes(minutes);
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _at = null;
    _minutes = 0;
    _endOfChapter = false;
    NowPlaying.instance.setSleep(null, 0);
    unawaited(audioPlayer.setVolume(1));
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _publish() {
    NowPlaying.instance.setSleep(
      _at,
      _minutes,
      endOfChapter: _endOfChapter,
    );
  }

  void _tick() {
    if (_endOfChapter) {
      // 章末暂停由播放器在 completed 时处理。
      return;
    }
    final at = _at;
    if (at == null) return;
    final left = at.difference(DateTime.now());
    if (left <= Duration.zero) {
      unawaited(audioPlayer.pause());
      cancel();
      return;
    }
    if (left.inSeconds < 20) {
      unawaited(audioPlayer.setVolume(
        (left.inMilliseconds / 20000).clamp(0.0, 1.0),
      ));
    } else {
      unawaited(audioPlayer.setVolume(1));
    }
    _publish();
  }
}
