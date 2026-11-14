import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
void main(List<String> args) {
  final raw = File(args[0]).readAsBytesSync();
  final ir = loadBookFixed([('novel_b.txt', raw)], '无名手记');
  print('fixed chapters=${ir.chapters.length} source=${ir.chapters.first.source}');
  for (final c in ir.chapters) {
    print('  ${c.title} segs=${c.segments.length}');
  }
}
