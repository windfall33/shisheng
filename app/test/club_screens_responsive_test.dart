// 俱乐部页面的响应式冒烟测试：2 倍字号下不溢出。
// 单独成文件，避免 Windows flutter_tester 在连续渲染多个重页面后提前退出。
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/club_screens.dart';
import 'package:shisheng_reader/models.dart';

import 'support/club_test_fixture.dart';

void main() {
  setUpAll(loadClubFonts);

  final fixture = ClubFixture.sample();

  testWidgets('cast club at 2x text', (tester) async {
    await pumpClubPage(
      tester,
      CastClubScreen(
        previewBooks: <BookItem>[
          fixture.active,
          fixture.second,
          fixture.third,
        ],
        previewLast: fixture.active,
        previewSeq: 0,
        previewPos: 42000,
      ),
    );
  });

  testWidgets('script board at 2x text', (tester) async {
    await pumpClubPage(
      tester,
      ScriptBoardScreen(
        previewBooks: <BookItem>[
          fixture.active,
          fixture.second,
          fixture.third,
        ],
      ),
    );
  });

  testWidgets('script detail at 2x text', (tester) async {
    await pumpClubPage(
      tester,
      ScriptScreen(
        book: fixture.active,
        activeSeq: 0,
        preview: true,
        previewStates: fixture.states,
      ),
    );
  });

}
