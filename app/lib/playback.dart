// 拾声 v4 · 全局“正在播放”状态：迷你播放器与播放器页共享。
import 'dart:async';

import 'package:flutter/foundation.dart';

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
