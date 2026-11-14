// 角色画像审计：看书里主要角色提取到的年龄/气质与最终音色。
import 'dart:convert';
import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
import 'package:shisheng_reader/voices.dart';
import 'package:shisheng_reader/persona.dart';

void main(List<String> a) {
  final raw = jsonDecode(File(a[0]).readAsStringSync()) as Map<String, dynamic>;
  final chapters = <Chapter>[];
  for (final c in raw['chapters'] as List) {
    final m = c as Map<String, dynamic>;
    chapters.add(Chapter(seq: (m['seq'] as num).toInt(), no: null,
      title: m['title'] as String, file: '', line: 0,
      segments: (m['segments'] as List)
          .map((e) => Segment.from(e as Map<String, dynamic>)).toList()));
  }
  final ir = BookIR(title: raw['title'] as String, chapters: chapters,
      skips: [], watermarkHits: [], encodings: {});
  propagateSpeakers(ir);
  final personas = extractPersonas(ir);
  final counts = <String, int>{};
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type == 'dialogue' && s.speaker != null) {
        counts[s.speaker!] = (counts[s.speaker!] ?? 0) + 1;
      }
    }
  }
  final top = counts.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  for (final e in top.take(15)) {
    final p = personas[e.key] ?? Persona(e.key, guessGenderName(e.key));
    final sid = matchPersonaVoice(p);
    final sid2 = sid ?? BookVoices.defaults().resolve('dialogue', e.key);
    print('${e.key} x${e.value} ${p.gender} age=${p.age} type=${p.type} '
        'score=${p.score} -> $sid2 ${VoicePool.sidName(sid2)} '
        '${sid != null ? "(persona)" : "(gender)"}');
  }
}
