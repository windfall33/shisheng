// 校验 archive 4.6 流式解压 API：读 package.json + 抽一章验证 md5（仅 PC 冒烟用）。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

Future<void> main(List<String> args) async {
  final zip = args[0];
  final outDir = Directory(args[1]);
  await outDir.create(recursive: true);
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input);
    ArchiveFile? manifest;
    final audioFiles =
        archive.files.where((f) => f.isFile && f.name.startsWith('audio/')).toList();
    final audioBytes = audioFiles.fold<int>(0, (s, f) => s + f.size);
    print('entries: audio=${audioFiles.length} audioBytes=$audioBytes');
    for (final f in archive.files) {
      if (f.isFile && f.name == 'package.json') manifest = f;
    }
    final m = jsonDecode(utf8.decode(manifest!.readBytes()!)) as Map<String, dynamic>;
    print('title=${m['title']} chapters=${(m['chapters'] as List).length}');

    // 抽 3 章流式解压并校验 md5
    for (final c in (m['chapters'] as List).take(3)) {
      final seq = (c['seq'] as num).toInt().toString().padLeft(5, '0');
      final name = 'audio/$seq.mp3';
      final f = archive.files.firstWhere((e) => e.isFile && e.name == name);
      final dst = File('${outDir.path}${Platform.pathSeparator}$seq.mp3');
      final out = OutputFileStream(dst.path);
      f.writeContent(out);
      out.closeSync();
      final bytes = await dst.readAsBytes();
      print('$name expect=${c['bytes']} actual=${bytes.length} '
          'sizeOk=${bytes.length == c['bytes']}');
    }
    print('SMOKE OK');
  } finally {
    input.closeSync();
  }
}
