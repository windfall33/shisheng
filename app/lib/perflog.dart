// 拾声 · 性能日志：内存环形缓冲，导出才落盘。
// 事件常开记录（首块等待、章节渲染 RTF、云端回退、清理动作），零开关零打扰；
// 设置页「导出性能日志」时才写成 JSONL，走系统分享交给用户。
import 'dart:convert';

/// 单条事件就是一行 JSON（JSONL）：{"ts":..., "event":"...", ...fields}。
/// fields 只放标量（数字/字符串/布尔），不塞嵌套结构，方便逐行 grep。
class PerfLog {
  PerfLog._();

  static final PerfLog instance = PerfLog._();

  /// 环形容量：听一天长书的渲染事件也就几百条，2000 条绰绰有余。
  static const int maxEvents = 2000;

  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  int _dropped = 0;

  void record(
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
      _dropped++;
    }
    _events.add(<String, Object?>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'event': event,
      ...fields,
    });
  }

  int get length => _events.length;

  /// 导出 JSONL 文本。meta 由调用方给（app 版本 / 系统 / 机型），
  /// 作为首行事件写入；被环形挤掉的条数也记一行，防止"看着像没发生"。
  String exportJsonl([Map<String, Object?>? meta]) {
    final buf = StringBuffer();
    if (meta != null && meta.isNotEmpty) {
      buf.writeln(_line(<String, Object?>{'event': 'meta', ...meta}));
    }
    if (_dropped > 0) {
      buf.writeln(_line(<String, Object?>{'event': 'meta', 'dropped': _dropped}));
    }
    for (final e in _events) {
      buf.writeln(_line(e));
    }
    return buf.toString();
  }

  void clear() {
    _events.clear();
    _dropped = 0;
  }
}

String _line(Map<String, Object?> e) => jsonEncode(e);
