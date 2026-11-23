// 试镜页单独成文件：Windows flutter_tester 连续渲染多个 2 倍字号重页面后
// 可能提前退出，拆开可让每个场景独立验证。
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/club_screens.dart';

import 'support/club_test_fixture.dart';

void main() {
  setUpAll(loadClubFonts);

  final fixture = ClubFixture.sample();

  testWidgets('audition at 2x text', (tester) async {
    await pumpClubPage(tester, AuditionScreen(previewBook: fixture.active));
  });
}
