// 拾声 v4 · 界面用的书模型与时间格式。
import 'dart:convert';

import 'globals.dart' show prefs;
import 'pipeline.dart';
import 'store.dart';
import 'textfront.dart';

String fmt(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  // 分钟也补零：书库、迷你条、播放页三处读数必须长得一样，否则同一段时间像两个值。
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 字数折算成听书时长。中文 Kokoro 实测约 4.3 字/秒（同 render.dart 的
/// RenderCfg.cps），这里不 import render.dart，免得把引擎依赖拖进模型层。
String fmtListenTime(int hanChars) {
  final sec = (hanChars / 4.3).round();
  if (sec < 60) return '$sec 秒';
  final m = sec ~/ 60;
  final s = sec % 60;
  if (m < 60) return s == 0 ? '$m 分钟' : '$m 分 $s 秒';
  final h = m ~/ 60;
  final mm = m % 60;
  return mm == 0 ? '$h 小时' : '$h 小时 $mm 分';
}

class BookItem {
  final String bid;
  final BookIR ir;
  int rendered;
  int renderedMs;
  int lastSeq;
  int lastPosMs;

  BookItem(
    this.bid,
    this.ir,
    this.rendered,
    this.renderedMs, {
    this.lastSeq = 0,
    this.lastPosMs = 0,
  });

  String get title => ir.title;
  int get chapterCount => ir.chapters.length;
  int get hanChars => ir.hanChars;

  double get renderedRatio =>
      chapterCount == 0 ? 0 : (rendered / chapterCount).clamp(0.0, 1.0);

  Duration get renderedDuration => Duration(milliseconds: renderedMs);

  String get chapterLabel => '$chapterCount 章';

  String get generatedLabel => '已生成 ${(renderedRatio * 100).round()}%';

  String get lastChapterTitle {
    final c = ir.chapter(lastSeq);
    return c?.title ?? '';
  }

  /// 用于封面下方、列表行的一句 meta。
  String get shelfMeta {
    if (lastPosMs > 0) {
      return '第 ${lastSeq + 1} 章，听到 ${fmt(Duration(milliseconds: lastPosMs))}';
    }
    return '$chapterCount 章，$generatedLabel';
  }
}

final Map<String, (DateTime, BookItem)> _bookItemCache =
    <String, (DateTime, BookItem)>{};

void invalidateBookItem(String bid) => _bookItemCache.remove(bid);

void clearBookItemCache() => _bookItemCache.clear();

Future<BookItem> loadBookItem(String bid, BookIR ir) async {
  final hit = _bookItemCache[bid];
  if (hit != null &&
      DateTime.now().difference(hit.$1) < const Duration(seconds: 8)) {
    return hit.$2;
  }
  var rendered = 0;
  var ms = 0;
  final summary = await Data.readSummary(bid);
  if (summary != null &&
      summary['pipe'] == audioPipelineVersion &&
      summary['chapters'] is Map) {
    final chapters = summary['chapters'] as Map;
    for (final c in ir.chapters) {
      final entry = chapters['${c.seq}'];
      if (entry is Map &&
          entry['done'] == true &&
          entry['pipe'] == audioPipelineVersion) {
        rendered++;
        ms += (entry['total_ms'] as num?)?.toInt() ?? 0;
      }
    }
  } else {
    // 旧数据/首次运行：扫一次并落 summary，之后首开只读一个文件。
    final entries = <String, dynamic>{};
    for (final c in ir.chapters) {
      final idx = await Data.readIndex(bid, c.seq);
      if (idx != null && idx['done'] == true) {
        final total = (idx['total_ms'] as num?)?.toInt() ?? 0;
        rendered++;
        ms += total;
        entries['${c.seq}'] = <String, dynamic>{
          'done': true,
          'total_ms': total,
          'pipe': audioPipelineVersion,
        };
      }
    }
    await Data.writeSummary(bid, <String, dynamic>{
      'pipe': audioPipelineVersion,
      'chapters': entries,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
  var lastSeq = 0;
  var lastPos = 0;
  final p = await Data.loadProgress(bid);
  lastSeq = (p['seq'] as num?)?.toInt() ?? 0;
  lastPos = (p['pos_ms'] as num?)?.toInt() ?? 0;
  final item = BookItem(
    bid,
    ir,
    rendered,
    ms,
    lastSeq: lastSeq,
    lastPosMs: lastPos,
  );
  _bookItemCache[bid] = (DateTime.now(), item);
  return item;
}

/// 读取上次播放位置；prefs 未初始化时返回 null（单元测试/启动早期安全）。
Map<String, dynamic>? lastPlayed() {
  try {
    final s = prefs.getString('last');
    if (s == null) return null;
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  } catch (_) {
    return null;
  }
}
