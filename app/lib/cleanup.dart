// 拾声 · 存储清理：容量上限 + LRU。
// 两层记账（同一份内容存了两份）：
//   章节层 audio/<seq>.pcm        s16，约 2.9MB/分钟，重拼便宜（段缓存命中就不重新合成）
//   段缓存层 cache/<xx>/<key>.pcm f32，约 5.8MB/分钟，重清 = 重新合成，最贵
// 超限先清章节层（连带 blocks/<seq>/index.json，并同步 summary.json），
// 还不够再动段缓存层；两层都按 mtime 从旧到新清。
// 保护：每本书 progress.json 里的播放章 ± 窗口、渲染中/排队中的章，永不碰。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'perflog.dart';
import 'store.dart' show Data;

class StorageAudit {
  final int audioBytes;
  final int cacheBytes;

  const StorageAudit({required this.audioBytes, required this.cacheBytes});

  int get totalBytes => audioBytes + cacheBytes;
}

class CleanupReport {
  final bool ran; // false = 没超限，本来就不用清
  final String reason;
  final int usageBefore;
  final int usageAfter;
  final int chaptersDeleted;
  final int cacheFilesDeleted;

  const CleanupReport({
    required this.ran,
    required this.reason,
    required this.usageBefore,
    required this.usageAfter,
    required this.chaptersDeleted,
    required this.cacheFilesDeleted,
  });

  int get freedBytes => usageBefore - usageAfter;
}

class Cleanup {
  Cleanup._();

  static String? _booksDirOverride;
  static String? _cacheDirOverride;

  /// 测试注入临时目录，Data（path_provider）就不会被碰到。
  /// 生产环境不调这个，直接用 Data 的路径。
  static void setPaths({required String booksDir, required String cacheDir}) {
    _booksDirOverride = booksDir;
    _cacheDirOverride = cacheDir;
  }

  static Future<String> _booksDir() async =>
      _booksDirOverride ?? await Data.booksDir();

  static Future<String> _cacheDir() async =>
      _cacheDirOverride ?? await Data.cacheDir();

  static Future<CleanupReport>? _inflight;

  /// 触发入口。渲染前调用时把渲染中/排队的 seq 从外面传进来
  /// （Renderer 自己有队列视图，清理层不该知道队列）。
  /// capBytes <= 0 表示不限容量，直接什么都不做。
  static Future<CleanupReport> enforce({
    required int capBytes,
    String reason = 'manual',
    Map<String, Set<int>> extraProtected = const <String, Set<int>>{},
    int protectWindow = 3,
  }) {
    // 单飞：启动清理和渲染前检查撞在一起时，等第一次跑完就行。
    final prev = _inflight;
    if (prev != null) return prev;
    final run = _run(capBytes, reason, extraProtected, protectWindow);
    _inflight = run;
    return run.whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
  }

  static Future<CleanupReport> _run(
    int capBytes,
    String reason,
    Map<String, Set<int>> extraProtected,
    int protectWindow,
  ) async {
    final before = await audit();
    if (capBytes <= 0 || before.totalBytes <= capBytes) {
      return CleanupReport(
        ran: false,
        reason: reason,
        usageBefore: before.totalBytes,
        usageAfter: before.totalBytes,
        chaptersDeleted: 0,
        cacheFilesDeleted: 0,
      );
    }
    var over = before.totalBytes - capBytes;

    // ---- 章节层：LRU 从旧到新 ----
    final chapters = <_ChapterFile>[];
    final protectedMap = <String, Set<int>>{};
    final booksRoot = Directory(await _booksDir());
    if (await booksRoot.exists()) {
      await for (final book in booksRoot.list()) {
        if (book is! Directory) continue;
        final bid = book.path.split(Platform.pathSeparator).last;
        final protected = <int>{...?extraProtected[bid]};
        final playing = await _playingSeq(book.path);
        if (playing != null) {
          for (var s = playing - protectWindow;
              s <= playing + protectWindow;
              s++) {
            if (s >= 0) protected.add(s);
          }
        }
        protectedMap[bid] = protected;
        final audioDir = Directory(
          '${book.path}${Platform.pathSeparator}audio',
        );
        if (!await audioDir.exists()) continue;
        await for (final f in audioDir.list()) {
          if (f is! File || !f.path.endsWith('.pcm')) continue;
          final name = f.path.split(Platform.pathSeparator).last;
          final seq = int.tryParse(name.substring(0, name.length - 4));
          if (seq == null) continue;
          final st = await f.stat();
          chapters.add(_ChapterFile(bid, seq, st.size, st.modified));
        }
      }
    }
    chapters.sort((a, b) => a.mtime.compareTo(b.mtime));
    final summaryDirty = <String, Set<int>>{};
    var chaptersDeleted = 0;
    for (final c in chapters) {
      if (over <= 0) break;
      if (protectedMap[c.bid]!.contains(c.seq)) continue;
      over -= await _deleteChapter(c.bid, c.seq);
      chaptersDeleted++;
      summaryDirty.putIfAbsent(c.bid, () => <int>{}).add(c.seq);
    }
    for (final entry in summaryDirty.entries) {
      await _syncSummary(entry.key, entry.value);
    }

    // ---- 段缓存层：还超才动（重清 = 重新合成）----
    var cacheDeleted = 0;
    if (over > 0) {
      final cacheFiles = <_CacheFile>[];
      final cacheRoot = Directory(await _cacheDir());
      if (await cacheRoot.exists()) {
        await for (final sub in cacheRoot.list()) {
          if (sub is! Directory) continue;
          await for (final f in sub.list()) {
            if (f is! File || !f.path.endsWith('.pcm')) continue;
            final st = await f.stat();
            cacheFiles.add(_CacheFile(f.path, st.size, st.modified));
          }
        }
      }
      cacheFiles.sort((a, b) => a.mtime.compareTo(b.mtime));
      for (final f in cacheFiles) {
        if (over <= 0) break;
        try {
          await File(f.path).delete();
          over -= f.size;
          cacheDeleted++;
        } catch (_) {}
      }
    }

    final after = await audit();
    final report = CleanupReport(
      ran: true,
      reason: reason,
      usageBefore: before.totalBytes,
      usageAfter: after.totalBytes,
      chaptersDeleted: chaptersDeleted,
      cacheFilesDeleted: cacheDeleted,
    );
    PerfLog.instance.record('cleanup', <String, Object?>{
      'reason': reason,
      'freed_bytes': report.freedBytes,
      'usage_before': report.usageBefore,
      'usage_after': report.usageAfter,
      'chapters_deleted': chaptersDeleted,
      'cache_deleted': cacheDeleted,
    });
    return report;
  }

  static Future<StorageAudit> audit() async {
    var audio = 0;
    final booksRoot = Directory(await _booksDir());
    if (await booksRoot.exists()) {
      await for (final book in booksRoot.list()) {
        if (book is! Directory) continue;
        final audioDir = Directory(
          '${book.path}${Platform.pathSeparator}audio',
        );
        if (!await audioDir.exists()) continue;
        await for (final f in audioDir.list()) {
          if (f is! File || !f.path.endsWith('.pcm')) continue;
          audio += (await f.stat()).size;
        }
      }
    }
    var cache = 0;
    final cacheRoot = Directory(await _cacheDir());
    if (await cacheRoot.exists()) {
      await for (final sub in cacheRoot.list()) {
        if (sub is! Directory) continue;
        await for (final f in sub.list()) {
          if (f is! File || !f.path.endsWith('.pcm')) continue;
          cache += (await f.stat()).size;
        }
      }
    }
    return StorageAudit(audioBytes: audio, cacheBytes: cache);
  }

  // -------------------------------------------------- 内部

  /// progress.json 是播放器每个位置更新都写的（player.dart _saveProgress），
  /// seq 基本实时；文件缺失或损坏就当没有书签，不保护。
  static Future<int?> _playingSeq(String bookDir) async {
    try {
      final f = File('$bookDir${Platform.pathSeparator}progress.json');
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>?;
      return (map?['seq'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// 删一章的音频 + 时间轴；返回释放的字节数。
  static Future<int> _deleteChapter(String bid, int seq) async {
    final booksDir = await _booksDir();
    final sep = Platform.pathSeparator;
    final name = seq.toString().padLeft(5, '0');
    var freed = 0;
    final audio = File('$booksDir$sep$bid${sep}audio$sep$name.pcm');
    try {
      if (await audio.exists()) {
        freed += (await audio.stat()).size;
        await audio.delete();
      }
    } catch (_) {}
    final blocks = Directory('$booksDir$sep$bid${sep}blocks$sep$seq');
    try {
      if (await blocks.exists()) await blocks.delete(recursive: true);
    } catch (_) {}
    return freed;
  }

  /// summary.json 里的 done 记录同步抹掉，
  /// 书架/目录才不会显示「已完成」却没有声音。
  static Future<void> _syncSummary(String bid, Set<int> seqs) async {
    try {
      final booksDir = await _booksDir();
      final sep = Platform.pathSeparator;
      final f = File('$booksDir$sep$bid${sep}summary.json');
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>?;
      final chapters = (map?['chapters'] as Map?)?.cast<String, dynamic>();
      if (chapters == null) return;
      var changed = false;
      for (final seq in seqs) {
        if (chapters.remove('$seq') != null) changed = true;
      }
      if (!changed) return;
      map!['chapters'] = chapters;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(map), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

class _ChapterFile {
  final String bid;
  final int seq;
  final int size;
  final DateTime mtime;
  const _ChapterFile(this.bid, this.seq, this.size, this.mtime);
}

class _CacheFile {
  final String path;
  final int size;
  final DateTime mtime;
  const _CacheFile(this.path, this.size, this.mtime);
}
