// 播放页的响应式冒烟测试：2 倍字号和横屏都只验证布局，不比较像素。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/player.dart';

import 'support/club_test_fixture.dart';

void main() {
  setUpAll(loadClubFonts);

  final fixture = ClubFixture.sample();

  testWidgets('player narration at 2x text', (tester) async {
    await pumpClubPage(
      tester,
      PlayerScreen(
        book: fixture.active,
        startSeq: 0,
        previewOnly: true,
        previewText: '山路在半夜里发白，松针上全是去年落下的月光。',
        previewNext: '“这山上本没有灯，今夜怎么一路亮到观门？”',
      ),
    );
  });

  testWidgets('player dialogue at 2x text', (tester) async {
    final timeline = <Map<String, dynamic>>[
      <String, dynamic>{
        'text': '“这山上本没有灯，今夜怎么一路亮到观门？”',
        'start_ms': 0,
        'end_ms': 6000,
        'type': 'dialogue',
        'speaker': '琼白',
      },
      <String, dynamic>{
        'text': '“别回头看。灯是给赶路的人壮胆，不是给活人照路。”',
        'start_ms': 6000,
        'end_ms': 12000,
        'type': 'dialogue',
        'speaker': '王生',
      },
    ];
    await pumpClubPage(
      tester,
      PlayerScreen(
        book: fixture.active,
        startSeq: 0,
        previewOnly: true,
        previewTimeline: timeline,
        previewAtMs: 1200,
        previewRenderStat: '正在合成 7 / 12',
      ),
    );
  });

  testWidgets('player in landscape', (tester) async {
    await pumpClubPage(
      tester,
      PlayerScreen(
        book: fixture.active,
        startSeq: 0,
        previewOnly: true,
        previewText: '山路在半夜里发白，松针上全是去年落下的月光。',
        previewNext: '“这山上本没有灯，今夜怎么一路亮到观门？”',
      ),
      size: const Size(844, 390),
      scale: 1,
    );
  });
}
