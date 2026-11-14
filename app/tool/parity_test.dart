// textfront Dart 移植与 PC 版 book.json 的对齐校验（PC 冒烟用）。
// 用法: dart run tool/parity_test.dart <txt路径> <pc版book.json路径> <书名>
import 'dart:convert';
import 'dart:io';

import 'package:shisheng_reader/textfront.dart';

Future<void> main(List<String> args) async {
  final txt = File(args[0]).readAsBytesSync();
  final pcJson =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final ir = loadBook([(args[0].split(Platform.pathSeparator).last, txt)],
      bookTitle: args.length > 2 ? args[2] : '');

  final pcChapters = (pcJson['chapters'] as List);
  print('chapters: dart=${ir.chapters.length} pc=${pcChapters.length}');
  var segDiff = 0;
  var fieldDiff = 0;
  var shown = 0;
  for (var i = 0; i < ir.chapters.length && i < pcChapters.length; i++) {
    final dc = ir.chapters[i];
    final pcm = pcChapters[i] as Map<String, dynamic>;
    final pcSegs = (pcm['segments'] as List).cast<Map<String, dynamic>>();
    if (dc.segments.length != pcSegs.length) {
      segDiff++;
      if (shown < 5) {
        print('ch$i segCount dart=${dc.segments.length} pc=${pcSegs.length}');
        shown++;
      }
      continue;
    }
    for (var j = 0; j < pcSegs.length; j++) {
      final d = dc.segments[j];
      final p = pcSegs[j];
      final sameType = d.type == p['type'];
      final sameSpk = (d.speaker ?? '') == (p['speaker'] ?? '');
      final sameText = d.text == p['text'];
      if (!sameType || !sameSpk || !sameText) {
        fieldDiff++;
        if (shown < 8) {
          print('ch$i seg$j: type ${d.type}/${p['type']} spk ${d.speaker}/${p['speaker']}'
              '${sameText ? '' : ' text:「${d.text}」vs「${p['text']}」'}');
          shown++;
        }
      }
    }
  }
  print('segCountDiffChapters=$segDiff fieldDiff=$fieldDiff');
  print(fieldDiff == 0 && segDiff == 0 && ir.chapters.length == pcChapters.length
      ? 'PARITY OK'
      : 'PARITY FAIL');
}
