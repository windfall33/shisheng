// 性能日志：环形溢出丢最旧、导出 JSONL、meta 首行。
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/perflog.dart';

void main() {
  setUp(() {
    PerfLog.instance.clear();
  });

  test('环形缓冲：超过容量丢最旧', () {
    final log = PerfLog.instance;
    for (var i = 0; i < PerfLog.maxEvents + 5; i++) {
      log.record('e', <String, Object?>{'i': i});
    }
    expect(log.length, PerfLog.maxEvents);
    final lines = log.exportJsonl().trim().split('\n');
    // 2000 条事件之外，dropped>0 时还有一行 meta。
    expect(lines.length, PerfLog.maxEvents + 1);
    // 最旧的 5 条被挤掉，第一条是 i=5
    expect(lines.first.contains('"dropped":5'), isTrue);
    expect(lines[1].contains('"i":5'), isTrue);
  });

  test('导出 JSONL：meta 首行 + dropped 记录', () {
    final log = PerfLog.instance;
    for (var i = 0; i < PerfLog.maxEvents + 1; i++) {
      log.record('e', <String, Object?>{'i': i});
    }
    final out = log.exportJsonl(<String, Object?>{'app': '1.0.1'});
    final lines = out.trim().split('\n');
    expect(lines.first.contains('"event":"meta"'), isTrue);
    expect(lines.first.contains('"app":"1.0.1"'), isTrue);
    expect(lines[1].contains('"dropped":1'), isTrue);
  });

  test('事件字段：ts 与 event 必在', () {
    final log = PerfLog.instance;
    log.record('chapter_done', <String, Object?>{'seq': 7});
    final line = log.exportJsonl().trim();
    expect(line.contains('"event":"chapter_done"'), isTrue);
    expect(line.contains('"seq":7'), isTrue);
    expect(line.contains('"ts":'), isTrue);
  });
}
