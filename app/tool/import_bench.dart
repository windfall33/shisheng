import 'dart:io';
import 'package:shisheng_reader/textfront.dart';
void main(List<String> a) {
  final raw = File(a[0]).readAsBytesSync();
  final sw = Stopwatch()..start();
  final (text, enc) = sniffDecode(raw);
  print('sniff ${sw.elapsedMilliseconds}ms enc=$enc chars=${text.length}');
  sw.reset();
  final ir = loadBook([('x.txt', raw)]);
  print('loadBook ${sw.elapsedMilliseconds}ms chapters=${ir.chapters.length} segs=${ir.chapters.fold<int>(0,(s,c)=>s+c.segments.length)}');
}
