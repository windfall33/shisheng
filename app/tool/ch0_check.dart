import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
import 'package:shisheng_reader/voices.dart';
void main(List<String> a) {
  final ir = loadBook([('x.txt', File(a[0]).readAsBytesSync())], bookTitle: 'x');
  propagateSpeakers(ir);
  final cfg = BookVoices.defaults();
  final c = ir.chapters.first;
  var i = 0;
  for (final s in c.segments) {
    if (s.type != 'dialogue') continue;
    final sid = cfg.resolve(s.type, s.speaker);
    print('${s.seq} ${s.text.substring(0, s.text.length.clamp(0, 18))} -> ${s.speaker} $sid');
    if (++i >= 15) break;
  }
}
