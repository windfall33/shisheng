// 拾声 v4 · TXT 导入：选文件 → 编码嗅探 → 切章分声 → 落库 → 入队渲染。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

import 'boot.dart';
import 'store.dart';
import 'textfront.dart';
import 'voices.dart';

String newBookId(String title) {
  final h = sha1
      .convert(utf8.encode('$title${DateTime.now().microsecondsSinceEpoch}'))
      .toString()
      .substring(0, 8);
  final slug = title.replaceAll(RegExp(r'[^\w一-鿿]+'), '');
  final s = slug.length > 20 ? slug.substring(0, 20) : slug;
  return '${s.isEmpty ? 'book' : s}-$h';
}

Future<(String, BookIR)?> importTxt() async {
  // ignore: avoid_print
  print('import: opening picker');
  // file_picker 13：静态入口，取消返回 null。
  final picked = await FilePicker.pickFile(type: FileType.any);
  // ignore: avoid_print
  print('import: picked=${picked?.name}');
  final path = picked?.path;
  // ignore: avoid_print
  print('import: path=$path');
  if (path == null) return null;
  final name = picked!.name;
  final raw = await _readPicked(path);
  // ignore: avoid_print
  print('import: read ${raw.length} bytes');
  final (text, enc) = sniffDecode(raw);
  // ignore: avoid_print
  print('import: decoded $enc ${text.length} chars');
  final title = name.replaceAll(RegExp(r'\.txt$', caseSensitive: false), '').trim();
  var ir = loadBook([(name, utf8.encode(text))], bookTitle: title);
  final rawHan = rawHanChars([(name, raw)]);
  if (ir.chapters.length < fixedMinChapters && rawHan > fixedChunkChars) {
    ir = loadBookFixed([(name, raw)], title);
  }
  // ignore: avoid_print
  print('import: parsed chapters=${ir.chapters.length}');
  if (ir.chapters.isEmpty) {
    throw FormatException('没切出任何章节：换一个 txt 试试（编码 $enc）');
  }
  final bid = newBookId(ir.title);
  await Data.saveBook(bid, ir);
  await Data.saveVoices(bid, BookVoices.defaults(bookTitle: ir.title));
  // ignore: avoid_print
  print('import: saved book $bid');
  await Boot.enqueueAll(bid, ir);
  // ignore: avoid_print
  print('import: enqueued');
  return (bid, ir);
}

Future<List<int>> _readPicked(String path) async {
  final f = File(path);
  if (await f.exists()) return f.readAsBytes();
  throw StateError('选中的文件读不到：$path');
}
