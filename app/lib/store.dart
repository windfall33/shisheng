// 拾声 v4 · 本地数据存储：书库目录 / book.json / voices.json / progress.json / 段级缓存。
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'persona.dart';
import 'textfront.dart';
import 'voices.dart';

class Data {
  static String? _root;
  static String? _modelDir;

  static Future<String> root() async {
    if (_root != null) return _root!;
    final sup = await getApplicationSupportDirectory();
    _root = '${sup.path}${Platform.pathSeparator}shisheng_data';
    await Directory(_root!).create(recursive: true);
    return _root!;
  }

  static Future<String> modelDir() async {
    if (_modelDir != null) return _modelDir!;
    final sup = await getApplicationSupportDirectory();
    _modelDir = '${sup.path}${Platform.pathSeparator}shisheng_tts';
    await Directory(_modelDir!).create(recursive: true);
    return _modelDir!;
  }

  static Future<String> booksDir() async {
    final d = '${await root()}${Platform.pathSeparator}books';
    await Directory(d).create(recursive: true);
    return d;
  }

  static Future<String> cacheDir() async {
    final d = '${await root()}${Platform.pathSeparator}cache';
    await Directory(d).create(recursive: true);
    return d;
  }

  static Future<String> bookDir(String bid) async =>
      '${await booksDir()}${Platform.pathSeparator}$bid';

  // ---------------------------------------------------------------- 书

  static Future<List<(String, BookIR)>> listBooks() async {
    final dir = Directory(await booksDir());
    final out = <(String, BookIR)>[];
    await for (final e in dir.list()) {
      if (e is! Directory) continue;
      final ir = await loadBook(e.path.split(Platform.pathSeparator).last);
      if (ir != null) out.add((e.path.split(Platform.pathSeparator).last, ir));
    }
    return out;
  }

  static final _bookCache = <String, BookIR>{};

  static Future<BookIR?> loadBook(String bid) async {
    final cached = _bookCache[bid];
    if (cached != null) return cached;
    try {
      final f = File('${await bookDir(bid)}${Platform.pathSeparator}book.json');
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final chapters = <Chapter>[];
      for (final c in (raw['chapters'] as List)) {
        final m = c as Map<String, dynamic>;
        chapters.add(
          Chapter(
            seq: (m['seq'] as num).toInt(),
            no: m['no'] == null ? null : (m['no'] as num).toInt(),
            title: (m['title'] ?? '') as String,
            file: (m['file'] ?? '') as String,
            line: (m['line'] as num?)?.toInt() ?? 0,
            segments: ((m['segments'] ?? []) as List)
                .map((s) => Segment.from(s as Map<String, dynamic>))
                .toList(),
            endMarker: m['end_marker'] == true,
            rawLines: (m['raw_lines'] as num?)?.toInt() ?? 0,
            source: (m['source'] ?? 'parsed') as String,
          ),
        );
      }
      final ir = BookIR(
        title: (raw['title'] ?? bid) as String,
        chapters: chapters,
        skips: ((raw['skips'] ?? []) as List)
            .map((e) => (e as num).toInt())
            .toList(),
        watermarkHits: ((raw['watermark_hits'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        encodings: {},
        chapterSource: (raw['chapter_source'] ?? 'parsed') as String,
      );
      propagateSpeakers(ir);
      ir.personas = extractPersonas(ir);
      _bookCache[bid] = ir;
      return ir;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveBook(String bid, BookIR ir) async {
    _bookCache.remove(bid);
    final d = await bookDir(bid);
    await Directory(d).create(recursive: true);
    await File('$d${Platform.pathSeparator}book.json')
        .writeAsString(jsonEncode(ir.toJson()), flush: true);
  }

  static Future<void> deleteBook(String bid) async {
    _bookCache.remove(bid);
    final d = Directory(await bookDir(bid));
    if (await d.exists()) await d.delete(recursive: true);
  }

  // ---------------------------------------------------------------- 音色配置

  static Future<BookVoices> loadVoices(String bid) async {
    try {
      final f = File(
        '${await bookDir(bid)}${Platform.pathSeparator}voices.json',
      );
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return BookVoices(raw);
    } catch (_) {
      return BookVoices.defaults();
    }
  }

  static Future<void> saveVoices(String bid, BookVoices v) async {
    final d = await bookDir(bid);
    await Directory(d).create(recursive: true);
    await File('$d${Platform.pathSeparator}voices.json')
        .writeAsString(jsonEncode(v.toJson()), flush: true);
  }

  // ---------------------------------------------------------------- 渲染产物

  static Future<String> blocksDir(String bid) async =>
      '${await bookDir(bid)}${Platform.pathSeparator}blocks';

  static Future<Map<String, dynamic>?> readIndex(String bid, int seq) async {
    try {
      final f = File(
        '${await blocksDir(bid)}'
        '${Platform.pathSeparator}$seq${Platform.pathSeparator}index.json',
      );
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeIndex(
    String bid,
    int seq,
    Map<String, dynamic> idx,
  ) async {
    final d = '${await blocksDir(bid)}${Platform.pathSeparator}$seq';
    await Directory(d).create(recursive: true);
    final f = File('$d${Platform.pathSeparator}index.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(idx), flush: true);
    await tmp.rename(f.path);
    await updateSummaryForIndex(bid, seq, idx);
  }

  // ---------------------------------------------------------------- 章节摘要
  // summary.json 只记录“已完成”的章：书架首开不再逐章读 index.json。
  static Future<Map<String, dynamic>?> readSummary(String bid) async {
    try {
      final f = File(
        '${await bookDir(bid)}${Platform.pathSeparator}summary.json',
      );
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeSummary(
    String bid,
    Map<String, dynamic> summary,
  ) async {
    try {
      final d = await bookDir(bid);
      await Directory(d).create(recursive: true);
      final f = File('$d${Platform.pathSeparator}summary.json');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(summary), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// 渲染器写 index 时顺手维护 summary；只在“完成 / 重渲开始 / 失败”时落盘。
  static Future<void> updateSummaryForIndex(
    String bid,
    int seq,
    Map<String, dynamic> idx,
  ) async {
    try {
      final done = idx['done'] == true;
      final emptyStart = (idx['blocks'] as List?)?.isEmpty ?? true;
      final error = idx['error'] != null;
      final firstWrite =
          emptyStart && ((idx['total_ms'] as num?)?.toInt() ?? 0) == 0;
      if (!done && !error && !firstWrite) return;

      final existing = await readSummary(bid);
      if (!done && !error && existing == null) return;
      final summary =
          existing ??
          <String, dynamic>{
            'pipe': idx['pipe'],
            'chapters': <String, dynamic>{},
          };
      final chapters = Map<String, dynamic>.from(
        (summary['chapters'] as Map?) ?? <String, dynamic>{},
      );
      if (done) {
        chapters['$seq'] = <String, dynamic>{
          'done': true,
          'total_ms': (idx['total_ms'] as num?)?.toInt() ?? 0,
          'pipe': idx['pipe'],
        };
      } else {
        chapters.remove('$seq');
      }
      summary['chapters'] = chapters;
      summary['pipe'] = idx['pipe'] ?? summary['pipe'];
      summary['updated_at'] = DateTime.now().millisecondsSinceEpoch;
      await writeSummary(bid, summary);
    } catch (_) {}
  }

  static Future<String> audioPcm(String bid, int seq) async =>
      '${await bookDir(bid)}${Platform.pathSeparator}audio'
      '${Platform.pathSeparator}${seq.toString().padLeft(5, '0')}.pcm';

  // ---------------------------------------------------------------- 进度

  static Future<Map<String, dynamic>> loadProgress(String bid) async {
    try {
      final f = File(
        '${await bookDir(bid)}${Platform.pathSeparator}progress.json',
      );
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveProgress(String bid, Map<String, dynamic> p) async {
    try {
      final f = File(
        '${await bookDir(bid)}${Platform.pathSeparator}progress.json',
      );
      await f.writeAsString(jsonEncode(p), flush: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- 段级缓存

  static Future<String> cachePath(String key) async {
    final d = await cacheDir();
    final sub = '$d${Platform.pathSeparator}${key.substring(0, 2)}';
    await Directory(sub).create(recursive: true);
    return '$sub${Platform.pathSeparator}$key.pcm';
  }
}
