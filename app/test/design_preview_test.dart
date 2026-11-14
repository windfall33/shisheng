// 设计走查：用 390×844 的 golden 渲染固定三张关键页，便于逐轮对比。
// 只在测试里注入假数据，不走 Data / 引擎 / 播放逻辑。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/app_shell.dart';
import 'package:shisheng_reader/boot.dart';
import 'package:shisheng_reader/design.dart';
import 'package:shisheng_reader/main.dart';
import 'package:shisheng_reader/models.dart';
import 'package:shisheng_reader/pipeline.dart';
import 'package:shisheng_reader/playback.dart';
import 'package:shisheng_reader/player.dart';
import 'package:shisheng_reader/screens.dart';
import 'package:shisheng_reader/settings.dart';
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

BookIR _ir(String title, int chapters) {
  const tails = <String>['劳山道士', '画皮', '婴宁', '聂小倩', '促织'];
  final list = <Chapter>[];
  for (var i = 0; i < chapters; i++) {
    list.add(
      Chapter(
        seq: i,
        no: i + 1,
        title: '第 ${i + 1} 章 ${tails[i % tails.length]}',
        file: '',
        line: 0,
        segments: <Segment>[
          Segment(
            seq: i * 3,
            text: '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
            type: 'narration',
            para: 0,
            chapterSeq: i,
          ),
          Segment(
            seq: i * 3 + 1,
            text: '“弟子操作多日，师略授小技。”',
            type: 'dialogue',
            speaker: '王生',
            para: 1,
            chapterSeq: i,
          ),
          Segment(
            seq: i * 3 + 2,
            text: '过月余，手足重茧，不堪其苦，阴有归志。',
            type: 'narration',
            para: 2,
            chapterSeq: i,
          ),
        ],
      ),
    );
  }
  return BookIR(
    title: title,
    chapters: list,
    skips: <int>[],
    watermarkHits: <Map<String, dynamic>>[],
    encodings: <String, String>{},
  );
}

Widget _app(Widget child, Brightness brightness, {double scale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(brightness),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        devicePixelRatio: 1,
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: child,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 120));
}

/// 播放器截图用的三段真实文案：一屏里能看出段落间距、当前句高亮和缩进。
const List<List<String>> _previewParas = <List<String>>[
  <String>[
    '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
    '登一顶，有观宇甚幽。一道士坐蒲团上，素发垂领，而神光爽迈。',
  ],
  <String>[
    '“恐娇情不能作苦。”',
    '答言：“能之。”其门人甚众，薄暮毕集，王俱与稽首，遂留观中。',
  ],
  <String>[
    '凌晨，道士呼王去，授一斧，使随众采樵。',
    '过月余，手足重茧，不堪其苦，阴有归志。',
  ],
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont('ShishengSerif', 'assets/fonts/ShishengSerif.otf');
    await _loadFont('ShishengSans', 'assets/fonts/ShishengSans.otf');
    await _loadFileFont(
      'MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
  });

  final b1 = () {
    final ir = _ir('聊斋志异·卷一', 3);
    return BookItem('preview-1', ir, 3, 540000, lastSeq: 0, lastPosMs: 42000);
  }();
  final b2 = () {
    final ir = _ir('聊斋志异·卷二', 3);
    return BookItem('preview-2', ir, 1, 180000, lastSeq: 1, lastPosMs: 126000);
  }();
  final b3 = () {
    final ir = _ir('聊斋志异·卷三', 3);
    return BookItem('preview-3', ir, 2, 360000, lastSeq: 2, lastPosMs: 63000);
  }();
  // 目录页的三态：第 1 章正在播且已合成、第 2 章一点没动、第 3 章合成到一半。
  // 三个分支同时出现在一张图里，才看得出副行与右列有没有各说各的。
  final detailStates = <int, Map<String, dynamic>>{
    0: <String, dynamic>{
      'pipe': audioPipelineVersion,
      'done': true,
      'total_ms': 492000,
      'blocks': List<Map<String, dynamic>>.filled(18, <String, dynamic>{}),
      'plan_blocks': 18,
    },
    // 第 2 章一点没动过：只有预估时长，右列给「优先合成」。
    // 测试里的章节只有三句话，纯按字数估会得到「16 秒」这种不像真书的值，
    // 所以这里给一个像真章的预估（真机上这个数由 render.dart 按字数算）。
    1: <String, dynamic>{
      'est_ms': 512000,
      'plan_blocks': 20,
    },
    2: <String, dynamic>{
      'pipe': audioPipelineVersion,
      'done': false,
      'total_ms': 0,
      'est_ms': 604000,
      'blocks': List<Map<String, dynamic>>.filled(7, <String, dynamic>{}),
      'plan_blocks': 12,
    },
  };

  testWidgets('startup dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Boot.ready = false;
    Boot.error = null;
    await tester.pumpWidget(_app(const Root(), Brightness.dark));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(Root),
      matchesGoldenFile('goldens/startup_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('library dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        LibraryScreen(
          previewBooks: <BookItem>[b1, b2, b3],
          previewLast: b1,
          previewSeq: 0,
          previewPos: 42000,
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/library_dark.png'),
    );
  });

  testWidgets('library empty dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        const LibraryScreen(previewBooks: <BookItem>[], previewLast: null),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/library_empty_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('onboarding first import', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    // 这一张抓的是整个 MaterialApp（弹层在 Overlay 里，抓子组件会漏掉它），
    // 所以必须把宿主 view 也压到 1x，否则会出 1170×2532，跟其它截图对不上。
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        Scaffold(
          // 真正跑起来时这张弹层盖在书架上，截图也照这个来：底下是书架，不是一块纯黑。
          body: Builder(
            builder: (ctx) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showModalBottomSheet<void>(
                  context: ctx,
                  backgroundColor: AppTokens.of(ctx).surface,
                  builder: (_) => FirstImportSheet(book: b1, ready: true),
                );
              });
              return LibraryScreen(
                previewBooks: <BookItem>[b1],
                previewLast: b1,
                previewSeq: 0,
                previewPos: 42000,
              );
            },
          ),
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/onboarding_import.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('library light', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        LibraryScreen(
          previewBooks: <BookItem>[b1, b2, b3],
          previewLast: b1,
          previewSeq: 0,
          previewPos: 42000,
        ),
        Brightness.light,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/library_light.png'),
    );
  });

  testWidgets('book detail dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        ChaptersScreen(
          book: b1,
          activeSeq: 0,
          preview: true,
          previewStates: detailStates,
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(ChaptersScreen),
      matchesGoldenFile('goldens/detail_dark.png'),
    );
  });

  testWidgets('book detail light', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        ChaptersScreen(
          book: b1,
          activeSeq: 0,
          preview: true,
          previewStates: detailStates,
        ),
        Brightness.light,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(ChaptersScreen),
      matchesGoldenFile('goldens/detail_light.png'),
    );
  });

  testWidgets('player dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        PlayerScreen(
          book: b1,
          startSeq: 0,
          previewOnly: true,
          previewText: '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
          previewNext: '“弟子操作多日，师略授小技。”',
          previewParagraphs: _previewParas,
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(PlayerScreen),
      matchesGoldenFile('goldens/player_dark.png'),
    );
  });

  testWidgets('library large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        LibraryScreen(
          previewBooks: <BookItem>[b1, b2, b3],
          previewLast: b1,
          previewSeq: 0,
          previewPos: 42000,
        ),
        Brightness.dark,
        scale: 2.0,
      ),
    );
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('detail large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        ChaptersScreen(
          book: b1,
          activeSeq: 0,
          preview: true,
          previewStates: detailStates,
        ),
        Brightness.dark,
        scale: 2.0,
      ),
    );
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('player large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        PlayerScreen(
          book: b1,
          startSeq: 0,
          previewOnly: true,
          previewText: '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
          previewNext: '“弟子操作多日，师略授小技。”',
        ),
        Brightness.dark,
        scale: 2.0,
      ),
    );
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<void> pumpAt(WidgetTester tester, Size size, Widget page) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(_app(page, Brightness.dark));
    await _settle(tester);
    // 卸载页面，取消浮动/音浪等 repeat 动画，避免影响后续测试。
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('library tablet', (tester) async {
    await pumpAt(
      tester,
      const Size(800, 1280),
      LibraryScreen(
        previewBooks: <BookItem>[b1, b2, b3],
        previewLast: b1,
        previewSeq: 0,
        previewPos: 42000,
      ),
    );
  });

  testWidgets('detail tablet golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        ChaptersScreen(
          book: b1,
          activeSeq: 0,
          preview: true,
          previewStates: detailStates,
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(ChaptersScreen),
      matchesGoldenFile('goldens/detail_tablet.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('player landscape', (tester) async {
    await pumpAt(
      tester,
      const Size(844, 390),
      PlayerScreen(
        book: b1,
        startSeq: 0,
        previewOnly: true,
        previewText: '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
        previewNext: '“弟子操作多日，师略授小技。”',
        previewParagraphs: _previewParas,
      ),
    );
  });

  testWidgets('player light', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    NowPlaying.instance.clear();
    await tester.pumpWidget(
      _app(
        PlayerScreen(
          book: b1,
          startSeq: 0,
          previewOnly: true,
          previewText: '邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。',
          previewNext: '“弟子操作多日，师略授小技。”',
          previewParagraphs: _previewParas,
        ),
        Brightness.light,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byType(PlayerScreen),
      matchesGoldenFile('goldens/player_light.png'),
    );
  });

  testWidgets('settings dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const SettingsScreen(), Brightness.dark));
    await _settle(tester);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 音色来源选「仅本机」时，页脚那句话要跟着变成「合成不联网」——这是事实陈述，
  // 不能一边写着「断网用本机音色」一边把合成关掉。
  testWidgets('settings local only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    AppSettings.instance.cloudAllowed.value = false;
    addTearDown(() => AppSettings.instance.cloudAllowed.value = true);
    await tester.pumpWidget(_app(const SettingsScreen(), Brightness.dark));
    await _settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await _settle(tester);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_local_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recent dark', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    NowPlaying.instance.clear();
    await tester.pumpWidget(_app(RecentScreen(previewBooks: <BookItem>[b1, b2, b3]), Brightness.dark));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(RecentScreen),
      matchesGoldenFile('goldens/recent_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('library with mini player', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        Scaffold(
          key: const Key('shot'),
          body: LibraryScreen(
            previewBooks: <BookItem>[b1, b2, b3],
            previewLast: b1,
            previewSeq: 0,
            // 和下面迷你条上的 00:42 对齐：同一本书不该出现两个互相矛盾的时间。
            previewPos: 42000,
          ),
          // 线上迷你条上面还有 56 的导航条，截图也要拼出来：
          // 只截迷你条会让 2px 进度线贴在屏幕底边，看着像渲染越界。
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              MiniPlayer(
                title: b1.title,
                chapter: '第 1 章 · 试炼',
                progress: .18,
                playing: true,
                buffering: false,
                sleeping: false,
                timeLabel: '00:42 / 12:30',
                onTap: () {},
                onToggle: () {},
              ),
              AppNavBar(selected: 0, onSelected: (i) {}),
            ],
          ),
        ),
        Brightness.dark,
      ),
    );
    await _settle(tester);
    await expectLater(
      find.byKey(const Key('shot')),
      matchesGoldenFile('goldens/library_mini_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
