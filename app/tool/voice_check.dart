import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
import 'package:shisheng_reader/voices.dart';

void main(List<String> a) {
  final raw = File(a[0]).readAsBytesSync();
  final ir = loadBook([('x.txt', raw)], bookTitle: 'x');
  propagateSpeakers(ir);
  final cfg = BookVoices.defaults();
  var shown = 0, fem = 0, total = 0;
  for (final c in ir.chapters) {
    final byPara = <int, List<Segment>>{};
    for (final s in c.segments) byPara.putIfAbsent(s.para, () => []).add(s);
    for (final segs in byPara.values) {
      final hasBai = segs.any((s) => s.type == 'narration' && s.text.contains('白灵淼'));
      if (!hasBai) continue;
      for (final s in segs) {
        if (s.type != 'dialogue') continue;
        total++;
        final sid = cfg.resolve(s.type, s.speaker);
        if (VoicePool.isFemale(sid)) fem++;
        if (shown < 8) {
          print('para ${s.para}: ${s.text.substring(0, s.text.length.clamp(0, 24))} '
              '-> ${s.speaker} sid=$sid ${VoicePool.sidName(sid)}');
          shown++;
        }
      }
    }
  }
  print('白灵淼段内对白 $total 句，女性音色 $fem 句');
}
