import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/design.dart';

Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont('ShishengSerif', 'assets/fonts/ShishengSerif.otf');
    await _loadFont('ShishengSans', 'assets/fonts/ShishengSans.otf');
  });

  testWidgets('font check', (tester) async {
    tester.view.physicalSize = const Size(900, 830);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget row(String label, TextStyle style) => SizedBox(
          height: 200,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9C9C99))),
              ),
              Text('聊斋志异 Aa', style: style.copyWith(color: Colors.white)),
            ],
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF0A0A0A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              row('AppType.display', AppType.display),
              row(
                  'raw serif 500',
                  const TextStyle(
                    fontFamily: 'ShishengSerif',
                    fontSize: 30,
                    height: 1.2,
                    letterSpacing: .2,
                    fontWeight: FontWeight.w500,
                    fontVariations: <FontVariation>[FontVariation('wght', 500)],
                  )),
              row('AppType.book', AppType.book),
              row(
                  'raw serif 600',
                  const TextStyle(
                    fontFamily: 'ShishengSerif',
                    fontSize: 17,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    fontVariations: <FontVariation>[FontVariation('wght', 600)],
                  )),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/font_check.png'));
  });
}
