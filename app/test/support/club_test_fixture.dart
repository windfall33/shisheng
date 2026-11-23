import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/design.dart';
import 'package:shisheng_reader/models.dart';
import 'package:shisheng_reader/pipeline.dart';
import 'package:shisheng_reader/playback.dart';
import 'package:shisheng_reader/textfront.dart';

class ClubFixture {
  final BookItem active;
  final BookItem second;
  final BookItem third;
  final Map<int, Map<String, dynamic>> states;

  const ClubFixture({
    required this.active,
    required this.second,
    required this.third,
    required this.states,
  });

  factory ClubFixture.sample() {
    final active = BookItem(
      'responsive-1',
      _sampleIr('芳山道士'),
      1,
      492000,
      lastSeq: 0,
      lastPosMs: 42000,
    );
    final second = BookItem(
      'responsive-2',
      _sampleIr('夜航船'),
      2,
      640000,
      lastSeq: 1,
      lastPosMs: 84000,
    );
    final third = BookItem('responsive-3', _sampleIr('山鬼来信'), 0, 0);
    return ClubFixture(
      active: active,
      second: second,
      third: third,
      states: <int, Map<String, dynamic>>{
        0: <String, dynamic>{
          'pipe': audioPipelineVersion,
          'done': true,
          'total_ms': 492000,
          'blocks': List<Map<String, dynamic>>.filled(
            18,
            <String, dynamic>{},
          ),
          'plan_blocks': 18,
        },
        1: <String, dynamic>{
          'est_ms': 512000,
          'plan_blocks': 20,
        },
        2: <String, dynamic>{
          'pipe': audioPipelineVersion,
          'done': false,
          'total_ms': 0,
          'est_ms': 604000,
          'blocks': List<Map<String, dynamic>>.filled(
            7,
            <String, dynamic>{},
          ),
          'plan_blocks': 12,
        },
      },
    );
  }
}

BookIR _sampleIr(String title) {
  const rows = <(String, String?, String)>[
    ('narration', null, '山路在半夜里发白，松针上全是去年落下的月光。'),
    ('dialogue', '琼白', '“这山上本没有灯，今夜怎么一路亮到观门？”'),
    ('dialogue', '王生', '“别回头看。灯是给赶路的人壮胆，不是给活人照路。”'),
    ('narration', null, '风从山谷里翻上来，吹得三人的衣角一齐向后退。'),
    ('dialogue', '道人', '“贫道等了三十年，只等一个敢在夜里上山的。”'),
  ];
  const scenes = <String>['第一场 夜上芳山', '第二场 三清观', '第三场 灯下问道'];
  var seq = 0;
  final chapters = <Chapter>[];
  for (var c = 0; c < scenes.length; c++) {
    final segments = <Segment>[
      for (var r = 0; r < rows.length; r++)
        Segment(
          seq: seq++,
          text: rows[r].$3,
          type: rows[r].$1,
          speaker: rows[r].$2,
          para: r,
          chapterSeq: c,
        ),
    ];
    chapters.add(
      Chapter(
        seq: c,
        no: c + 1,
        title: scenes[c],
        file: '',
        line: 0,
        segments: segments,
      ),
    );
  }
  return BookIR(
    title: title,
    chapters: chapters,
    skips: <int>[],
    watermarkHits: <Map<String, dynamic>>[],
    encodings: <String, String>{},
  );
}

Future<void> loadClubFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFont('ZCOOLKuaiLe', 'assets/fonts/ZCOOLKuaiLe-Regular.ttf');
  await _loadFont('ShishengSans', 'assets/fonts/ShishengSans.otf');
  await _loadFileFont(
    'MaterialIcons',
    '${Platform.environment['FLUTTER_ROOT'] ?? 'D:/DevTools/flutter'}'
        '/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
}

Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

Future<void> _loadFileFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> pumpClubPage(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 2,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  NowPlaying.instance.clear();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          disableAnimations: true,
        ),
        child: child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 260));
  expect(tester.takeException(), isNull);
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
}
