// 清理服务：LRU 顺序、两层上限、保护窗口、summary 同步。
// 全部走临时目录，不碰 Data / path_provider。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/cleanup.dart';

void main() {
  late Directory tmp;
  late String books;
  late String cache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shisheng_cleanup_test');
    books = '${tmp.path}${Platform.pathSeparator}books';
    cache = '${tmp.path}${Platform.pathSeparator}cache';
    await Directory(books).create(recursive: true);
    await Directory(cache).create(recursive: true);
    Cleanup.setPaths(booksDir: books, cacheDir: cache);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<File> makeChapter(
    String bid,
    int seq,
    int bytes,
    DateTime mtime,
  ) async {
    final sep = Platform.pathSeparator;
    final f = File(
      '$books$sep$bid${sep}audio$sep${seq.toString().padLeft(5, '0')}.pcm',
    );
    await f.create(recursive: true);
    await f.writeAsBytes(List.filled(bytes, 0));
    await f.setLastModified(mtime);
    return f;
  }

  Future<void> makeIndex(String bid, int seq) async {
    final sep = Platform.pathSeparator;
    final d = Directory('$books$sep$bid${sep}blocks$sep$seq');
    await d.create(recursive: true);
    await File('${d.path}${Platform.pathSeparator}index.json')
        .writeAsString('{"done":true}');
  }

  Future<void> makeProgress(String bid, int seq) async {
    final sep = Platform.pathSeparator;
    await Directory('$books$sep$bid').create(recursive: true);
    await File(
      '$books$sep$bid${Platform.pathSeparator}progress.json',
    ).writeAsString(jsonEncode(<String, dynamic>{'seq': seq, 'pos_ms': 0}));
  }

  Future<void> makeSummary(String bid, Iterable<int> done) async {
    final sep = Platform.pathSeparator;
    await Directory('$books$sep$bid').create(recursive: true);
    await File(
      '$books$sep$bid${Platform.pathSeparator}summary.json',
    ).writeAsString(jsonEncode(<String, dynamic>{
      'chapters': <String, dynamic>{
        for (final s in done)
          '$s': <String, dynamic>{'done': true, 'total_ms': 60000},
      },
    }));
  }

  Future<Map<String, dynamic>?> readSummary(String bid) async {
    final sep = Platform.pathSeparator;
    final f = File(
      '$books$sep$bid${Platform.pathSeparator}summary.json',
    );
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  test('没超限：什么都不删', () async {
    final t0 = DateTime(2026, 1, 1, 10);
    final f = await makeChapter('b1', 0, 100, t0);
    final r = await Cleanup.enforce(capBytes: 1024 * 1024);
    expect(r.ran, isFalse);
    expect(await f.exists(), isTrue);
  });

  test('不限容量（cap=0）：什么都不删', () async {
    final f = await makeChapter('b1', 0, 100, DateTime(2026, 1, 1, 10));
    final r = await Cleanup.enforce(capBytes: 0);
    expect(r.ran, isFalse);
    expect(await f.exists(), isTrue);
  });

  test('超限：按 mtime 从旧到新清章节', () async {
    final t0 = DateTime(2026, 1, 1, 10);
    final a = await makeChapter('b1', 0, 100, t0);
    final b = await makeChapter('b1', 1, 100, t0.add(const Duration(hours: 1)));
    final c = await makeChapter('b1', 2, 100, t0.add(const Duration(hours: 2)));
    // cap=150 → 超 150：删两个旧章，最新一章留下。
    final r = await Cleanup.enforce(capBytes: 150);
    expect(r.ran, isTrue);
    expect(r.chaptersDeleted, 2);
    expect(await a.exists(), isFalse);
    expect(await b.exists(), isFalse);
    expect(await c.exists(), isTrue);
    expect(r.usageAfter, 100);
  });

  test('正在播放章 ± 窗口受保护：清不动就整章不删', () async {
    final t0 = DateTime(2026, 1, 1, 10);
    await makeChapter('b1', 0, 100, t0);
    await makeChapter('b1', 1, 100, t0.add(const Duration(hours: 1)));
    await makeProgress('b1', 0); // 保护 0..3
    final r = await Cleanup.enforce(capBytes: 50);
    expect(r.ran, isTrue);
    expect(r.chaptersDeleted, 0);
    expect(r.freedBytes, 0);
  });

  test('章节层清完还不够才动段缓存', () async {
    final t0 = DateTime(2026, 1, 1, 10);
    // 唯一章在保护窗口内：章节层清不动，只能清段缓存。
    await makeChapter('b1', 0, 100, t0);
    await makeProgress('b1', 0);
    final sep = Platform.pathSeparator;
    final old = File('$cache$sep' 'ab${sep}old.pcm');
    await old.create(recursive: true);
    await old.writeAsBytes(List.filled(100, 0));
    await old.setLastModified(t0);
    final fresh = File('$cache$sep' 'cd${sep}fresh.pcm');
    await fresh.create(recursive: true);
    await fresh.writeAsBytes(List.filled(100, 0));
    await fresh.setLastModified(t0.add(const Duration(hours: 5)));

    // cap=200 → 超 100：只够清掉最旧的段缓存，新的必须留下。
    final r = await Cleanup.enforce(capBytes: 200);
    expect(r.ran, isTrue);
    expect(r.chaptersDeleted, 0);
    expect(r.cacheFilesDeleted, 1);
    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
  });

  test('summary.json 的 done 记录随章节一起抹掉', () async {
    final t0 = DateTime(2026, 1, 1, 10);
    await makeChapter('b1', 0, 100, t0);
    await makeChapter('b1', 1, 100, t0.add(const Duration(hours: 1)));
    await makeIndex('b1', 0);
    await makeSummary('b1', [0, 1]);
    await Cleanup.enforce(capBytes: 150);
    final s = await readSummary('b1');
    expect((s?['chapters'] as Map).keys, ['1']);
    final sep = Platform.pathSeparator;
    expect(
      await Directory('$books$sep' 'b1${sep}blocks${sep}0').exists(),
      isFalse,
    );
  });
}
