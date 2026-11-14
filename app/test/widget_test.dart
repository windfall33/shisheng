// 主题冒烟：不启动引擎/播放器，避免原生插件与全局 Timer 干扰 golden 测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shisheng_reader/design.dart';

void main() {
  test('dark and light themes build', () {
    final dark = buildAppTheme(Brightness.dark);
    final light = buildAppTheme(Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.extension<AppTokens>()?.gold, AppTokens.dark.gold);
    expect(light.extension<AppTokens>()?.paper, AppTokens.light.paper);
  });
}
