// 归因/分声审计：本地 book.json → 传播说话人 → 统计男女音色覆盖率。
import 'dart:convert';
import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
import 'package:shisheng_reader/voices.dart';

void main(List<String> a) {
  final raw = jsonDecode(File(a[0]).readAsStringSync()) as Map<String, dynamic>;
  final chapters = <Chapter>[];
  for (final c in raw['chapters'] as List) {
    final m = c as Map<String, dynamic>;
    chapters.add(Chapter(
      seq: (m['seq'] as num).toInt(), no: m['no'] as int?,
      title: m['title'] as String, file: '', line: 0,
      segments: (m['segments'] as List)
          .map((e) => Segment.from(e as Map<String, dynamic>)).toList(),
    ));
  }
  final ir = BookIR(title: raw['title'] as String, chapters: chapters,
      skips: [], watermarkHits: [], encodings: {});
  final cfg = BookVoices.defaults(bookTitle: ir.title);
  var dial = 0, attr = 0, fem = 0, male = 0;
  final sids = <int, int>{};
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type != 'dialogue') continue;
      dial++;
      if (s.speaker != null && s.speaker!.isNotEmpty) attr++;
    }
  }
  propagateSpeakers(ir);
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type != 'dialogue') continue;
      final sid = cfg.resolve(s.type, s.speaker);
      sids[sid] = (sids[sid] ?? 0) + 1;
      if (VoicePool.isFemale(sid)) fem++; else male++;
    }
  }
  print('dialogues=$dial attributed=$attr -> propagated=${attr}');
  print('after propagation: attr=${ir.chapters.expand((c)=>c.segments).where((s)=>s.type=="dialogue"&&s.speaker!=null).length}');
  print('voice genders: female=$fem male=$male (${(fem/(fem+male)*100).toStringAsFixed(1)}% female)');
  final top = sids.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
  print('top sids: ${top.take(8).map((e)=>"${e.key}(${VoicePool.sidName(e.key)}):${e.value}").join(", ")}');
}
