// 拾声 v4 · 本地小说听书（Android，断网可听）。
// 架构：导入 TXT → 手机切章/分声 → sherpa-onnx Kokoro 端侧合成 → 本地虚拟 WAV 流播放。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell.dart';
import 'boot.dart';
import 'club_ui.dart';
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
  AppSettings.instance.load(g.prefs);
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
        // 首次启动进入浅色舞台；用户可在设置里切换跟随系统或暗场。
        themeMode: _previewTheme == 'light'
            ? ThemeMode.light
            : _previewTheme == 'dark'
            ? ThemeMode.dark
            : mode,
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
        body: ClubBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const ClubAvatar(
                        label: '拾',
                        tone: CastTone.coral,
                        size: 58,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '拾声',
                        style: AppType.brand.copyWith(
                          color: t.text,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ClubCard(
                        color: t.coral,
                        shadow: 6,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ClubTag(
                              'OFF AIR / 舞台故障',
                              color: t.lemon,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '舞台没搭起来',
                              style: AppType.title.copyWith(color: t.onAccent),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '引擎初始化失败：${Boot.error}\n'
                              '清后台后重试通常可解；仍不行请告诉我机型。',
                              style: AppType.body.copyWith(
                                color: t.onAccent,
                                height: 1.65,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ClubButton(
                                label: '再试一次',
                                icon: Icons.refresh_rounded,
                                color: t.lemon,
                                onTap: () {
                                  setState(() {
                                    Boot.error = null;
                                    Boot.status = '准备引擎…';
                                  });
                                  unawaited(Boot.init());
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!Boot.ready) {
      return Scaffold(
        backgroundColor: t.bg,
        body: ClubBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const ClubAvatar(
                        label: '拾',
                        tone: CastTone.coral,
                        size: 66,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '拾声',
                        textAlign: TextAlign.center,
                        style: AppType.brand.copyWith(
                          color: t.text,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '先认识角色，再开始听。',
                        textAlign: TextAlign.center,
                        style: AppType.title.copyWith(
                          color: t.text,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 34),
                      ClubCard(
                        color: t.surface,
                        shadow: 6,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                ClubTag('ON STAGE', color: t.lemon),
                                const Spacer(),
                                Text(
                                  '本机舞台',
                                  style: AppType.caption.copyWith(
                                    color: t.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '正在布置舞台',
                              style: AppType.title.copyWith(color: t.text),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                color: t.coral,
                                backgroundColor: t.surfaceAlt,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              Boot.status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                color: t.faint,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: <Widget>[
                          ClubTag('角色', color: t.mint),
                          ClubTag('剧本', color: t.lemon),
                          ClubTag('试听', color: t.lilac),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const AppShell();
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
