// 拾声 v4 · 本地小说听书（Android，断网可听）。
// 架构：导入 TXT → 手机切章/分声 → sherpa-onnx Kokoro 端侧合成 → 本地虚拟 WAV 流播放。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell.dart';
import 'boot.dart';
import 'design.dart';
import 'globals.dart' as g;
import 'settings.dart';

const String _previewTheme = String.fromEnvironment('SHISHENG_THEME');
const bool _previewPhone = bool.fromEnvironment('SHISHENG_PHONE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.shisheng.reader.audio',
      androidNotificationChannelName: '拾声播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
  } catch (_) {} // 桌面预览模式无此插件
  g.prefs = await SharedPreferences.getInstance();
  AppSettings.instance.load(g.prefs, preferDark: Platform.isWindows);
  // 引擎初始化放后台：模型解压 + 引擎加载不阻塞首帧
  unawaited(Boot.init());
  runApp(const ShishengApp());
}

class ShishengApp extends StatelessWidget {
  const ShishengApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final app = ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (ctx, mode, _) => MaterialApp(
        title: '拾声',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        // 桌面预览默认暗色（书卷主视觉）；手机上跟随用户设置。
        themeMode: _previewTheme == 'light'
            ? ThemeMode.light
            : _previewTheme == 'dark'
            ? ThemeMode.dark
            : (Boot.preview ? ThemeMode.dark : mode),
        home: _previewPhone ? const _PhoneFrame(child: Root()) : const Root(),
      ),
    );
    if (mq == null) return app;
    // 支持大字号，但不超过 2.0，避免极端缩放下布局被压碎。
    return MediaQuery(
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 2.0,
        ),
      ),
      child: app,
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (Boot.ready || Boot.error != null) {
        _timer?.cancel();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (Boot.error != null) {
      return Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.section),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '拾声',
                      style: AppType.brand.copyWith(color: t.text),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    Text(
                      '启动遇到问题',
                      style: AppType.title.copyWith(color: t.text),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      '引擎初始化失败：${Boot.error}\n清后台后重试通常可解；仍不行请告诉我机型。',
                      textAlign: TextAlign.center,
                      style: AppType.body.copyWith(color: t.muted, height: 1.7),
                    ),
                    const SizedBox(height: AppSpace.xxl),
                    InkWell(
                      onTap: () {
                        setState(() {
                          Boot.error = null;
                          Boot.status = '准备引擎…';
                        });
                        unawaited(Boot.init());
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.xxl,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.text,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '重试',
                          style: AppType.button.copyWith(color: t.bg),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      );
    }
    if (!Boot.ready) {
      return Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.section),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '拾声',
                    textAlign: TextAlign.center,
                    style: AppType.brand.copyWith(color: t.text),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    '把一本书，听成一间书房',
                    style: AppType.body.copyWith(
                      color: t.muted,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: 200,
                    // 和书库 hero 同一条进度语言：填充实色、槽用 track（不是 line）。
                    child: LinearProgressIndicator(
                      color: t.text,
                      backgroundColor: t.track,
                      minHeight: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    Boot.status,
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: t.faint),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '端侧合成',
                        style: AppType.caption.copyWith(color: t.faint),
                      ),
                      _StartDivider(t: t),
                      Text(
                        '断网可听',
                        style: AppType.caption.copyWith(color: t.faint),
                      ),
                      _StartDivider(t: t),
                      Text(
                        '无账号',
                        style: AppType.caption.copyWith(color: t.faint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const AppShell();
  }
}

class _StartDivider extends StatelessWidget {
  final AppTokens t;

  const _StartDivider({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: t.line,
    );
  }
}

/// 仅用于设计走查：把 App 放进 390×844 的手机画框，避免桌面 DPI 干扰布局。
/// 通过 --dart-define=SHISHENG_PHONE=true 启用，正式包不会走这里。
class _PhoneFrame extends StatelessWidget {
  final Widget child;

  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final outer = MediaQuery.of(context);
    return ColoredBox(
      color: const Color(0xFF050605),
      child: Center(
        child: Container(
          width: 402,
          height: 856,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: const Color(0xFF2C2C2C), width: 1),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black,
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              width: 390,
              height: 844,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  devicePixelRatio: 1,
                  textScaler: TextScaler.noScaling,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                  platformBrightness: outer.platformBrightness,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
