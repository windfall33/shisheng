@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/app_shell.dart';
import 'package:shisheng_reader/club_screens.dart';
import 'package:shisheng_reader/design.dart';
import 'package:shisheng_reader/models.dart';
import 'package:shisheng_reader/pipeline.dart';
import 'package:shisheng_reader/playback.dart';
import 'package:shisheng_reader/player.dart';
import 'package:shisheng_reader/textfront.dart';
import 'package:shisheng_reader/ui_kit.dart';

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

BookIR _sampleIr(
  String title, {
  List<String> scenes = const <String>[
    '第一场 夜上芳山',
    '第二场 三清观',
    '第三场 灯下问道',
  ],
}) {
  var seq = 0;
  final chapters = <Chapter>[];
  for (var c = 0; c < scenes.length; c++) {
    final rows = <(String, String?, String)>[
      ('narration', null, '山路在半夜里发白，松针上全是去年落下的月光。'),
      ('dialogue', '琼白', '“这山上本没有灯，今夜怎么一路亮到观门？”'),
      ('dialogue', '王生', '“别回头看。灯是给赶路的人壮胆，不是给活人照路。”'),
      ('narration', null, '风从山谷里翻上来，吹得三人的衣角一齐向后退。'),
      ('dialogue', '道人', '“贫道等了三十年，只等一个敢在夜里上山的。”'),
      ('dialogue', '琼白', '“那就开门吧。我走了这么远，不是为了在门口听故事。”'),
    ];
    final segments = <Segment>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      segments.add(
        Segment(
          seq: seq++,
          text: row.$3,
          type: row.$1,
          speaker: row.$2,
          para: r,
          chapterSeq: c,
        ),
      );
    }
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

Widget _app(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        devicePixelRatio: 1,
        textScaler: TextScaler.noScaling,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: child,
    ),
  );
}

Future<void> _pumpShot(
  WidgetTester tester,
  Widget child,
  String name,
) async {
  // 只改 DPR；尺寸走 setSurfaceSize，连续截图时不要反复重置 view 的物理尺寸。
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  NowPlaying.instance.clear();
  await tester.pumpWidget(_app(child));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(seconds: 2));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('club_shots/$name.png'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont(
      'ZCOOLKuaiLe',
      'assets/fonts/ZCOOLKuaiLe-Regular.ttf',
    );
    await _loadFont('ShishengSans', 'assets/fonts/ShishengSans.otf');
    await _loadFileFont(
      'MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT'] ?? 'D:/DevTools/flutter'}'
          '/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
  });

  final b1 = BookItem(
    'club-1',
    _sampleIr('芳山道士'),
    1,
    492000,
    lastSeq: 0,
    lastPosMs: 42000,
  );
  final b2 = BookItem(
    'club-2',
    _sampleIr('夜航船'),
    2,
    640000,
    lastSeq: 1,
    lastPosMs: 84000,
  );
  final b3 = BookItem(
    'club-3',
    _sampleIr('山鬼来信'),
    0,
    0,
  );
  final states = <int, Map<String, dynamic>>{
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
  };

  testWidgets('cast club', (tester) async {
    await _pumpShot(
      tester,
      CastClubScreen(
        previewBooks: <BookItem>[b1, b2, b3],
        previewLast: b1,
        previewSeq: 0,
        previewPos: 42000,
      ),
      '01-cast',
    );
  });

  testWidgets('script board', (tester) async {
    await _pumpShot(
      tester,
      ScriptBoardScreen(previewBooks: <BookItem>[b1, b2, b3]),
      '02-scripts',
    );
  });

  testWidgets('script detail', (tester) async {
    await _pumpShot(
      tester,
      ScriptScreen(
        book: b1,
        activeSeq: 0,
        preview: true,
        previewStates: states,
      ),
      '03-script-detail',
    );
  });

  testWidgets('dialogue', (tester) async {
    final timeline = <Map<String, dynamic>>[
      <String, dynamic>{
        'text': '山路在半夜里发白，松针上全是去年落下的月光。',
        'start_ms': 0,
        'end_ms': 3000,
        'type': 'narration',
      },
      <String, dynamic>{
        'text': '“这山上本没有灯，今夜怎么一路亮到观门？”',
        'start_ms': 3000,
        'end_ms': 9000,
        'type': 'dialogue',
        'speaker': '琼白',
      },
      <String, dynamic>{
        'text': '“别回头看。灯是给赶路的人壮胆。”',
        'start_ms': 9000,
        'end_ms': 14000,
        'type': 'dialogue',
        'speaker': '王生',
      },
    ];
    await _pumpShot(
      tester,
      PlayerScreen(
        book: b1,
        startSeq: 0,
        previewOnly: true,
        previewTimeline: timeline,
        previewAtMs: 5200,
        previewRenderStat: '正在合成 7 / 12',
      ),
      '04-dialogue',
    );
  });

  testWidgets('audition', (tester) async {
    await _pumpShot(
      tester,
      AuditionScreen(previewBook: b1),
      '05-audition',
    );
  });

  testWidgets('club shell with mini player', (tester) async {
    await _pumpShot(
      tester,
      Scaffold(
        body: CastClubScreen(
          previewBooks: <BookItem>[b1, b2, b3],
          previewLast: b1,
          previewSeq: 0,
          previewPos: 42000,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MiniPlayer(
              title: b1.title,
              chapter: '第 1 幕 · 第一场 夜上芳山',
              timeLabel: '00:42 / 08:12',
              progress: .18,
              playing: true,
              buffering: false,
              sleeping: false,
              onTap: () {},
              onToggle: () {},
            ),
            AppNavBar(selected: 0, onSelected: (_) {}),
          ],
        ),
      ),
      '06-shell',
    );
  });
}
