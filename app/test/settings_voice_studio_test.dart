import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/design.dart';
import 'package:shisheng_reader/screens.dart';
import 'package:shisheng_reader/settings.dart';

void main() {
  testWidgets('音色三选一：外接 VoiceStudio 展开表单且不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      final s = AppSettings.instance;
      s.voiceStudioEnabled.value = false;
      s.cloudAllowed.value = false;
      s.voiceStudioUrl.value = '';
      s.voiceStudioKey.value = '';
      s.voiceStudioModel.value = 'omnivoice';
      s.voiceStudioNarrationVoice.value = 'default';
      s.voiceStudioDialogueVoice.value = 'default';
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const SettingsScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(
      find.text('音色来源'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('仅本机'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    expect(find.text('外接 VoiceStudio'), findsOneWidget);

    await tester.ensureVisible(find.text('外接 VoiceStudio'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('外接 VoiceStudio'));
    // 表单里有 TextField，光标闪烁是常驻动画，pumpAndSettle 会等不到头。
    await tester.pump(const Duration(milliseconds: 400));
    expect(AppSettings.instance.voiceStudioEnabled.value, isTrue);
    expect(AppSettings.instance.cloudAllowed.value, isFalse);

    await tester.scrollUntilVisible(
      find.text('VoiceStudio 地址'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('VoiceStudio 地址'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
