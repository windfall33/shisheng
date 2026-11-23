@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/boot.dart';
import 'package:shisheng_reader/design.dart';
import 'package:shisheng_reader/main.dart';

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

  testWidgets('startup', (tester) async {
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Boot.ready = false;
    Boot.error = null;
    Boot.status = '正在准备声音模型…';
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            devicePixelRatio: 1,
            textScaler: TextScaler.noScaling,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: Root(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 260));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('club_shots/00-start.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
