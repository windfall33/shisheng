// 拾声 v4 · 用户偏好：主题、音色来源、快跳秒数、默认语速、睡眠与自动回退。
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  SharedPreferences? _p;

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );
  final ValueNotifier<int> skipSeconds = ValueNotifier<int>(15);
  final ValueNotifier<double> defaultSpeed = ValueNotifier<double>(1.0);
  final ValueNotifier<int> sleepDefault = ValueNotifier<int>(30);
  final ValueNotifier<bool> autoRewind = ValueNotifier<bool>(true);
  /// 合成音频的存储上限（MB），0 = 不限。超限时自动清最久没听的内容。
  /// 档位和设置页保持一致：512 / 1024 / 2048 / 4096 / 0。
  final ValueNotifier<int> storageCapMb = ValueNotifier<int>(1024);
  /// 音色来源：true = 自动（联网用云端、断网回退本机），false = 仅本机。
  /// 关掉它就是关掉所有出站合成请求，不是只关一路音色。
  ///
  /// 默认 false：装上就只在本机合成，一个字节都不出网。云端那一路是
  /// 对第三方朗读接口的逆向调用，随时可能失效，不该是默认行为。
  final ValueNotifier<bool> cloudAllowed = ValueNotifier<bool>(false);

  /// 外接 VoiceStudio（可选）。关闭时一个请求都不发。
  final ValueNotifier<bool> voiceStudioEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> voiceStudioUrl = ValueNotifier<String>('');
  final ValueNotifier<String> voiceStudioKey = ValueNotifier<String>('');
  final ValueNotifier<String> voiceStudioModel = ValueNotifier<String>(
    'omnivoice',
  );
  final ValueNotifier<String> voiceStudioNarrationVoice =
      ValueNotifier<String>('default');
  final ValueNotifier<String> voiceStudioDialogueVoice =
      ValueNotifier<String>('default');

  bool get ready => _p != null;

  /// 首次导入成功后只提示一次；测试/未初始化时视为已完成，避免打扰。
  bool get firstImportDone => _p?.getBool('onboard_import_v1') ?? true;

  Future<void> markFirstImportDone() async {
    await _p?.setBool('onboard_import_v1', true);
  }

  void load(SharedPreferences p, {bool preferDark = false}) {
    _p = p;
    themeMode.value =
        _themeMode(p.getString('themeMode')) ??
        (preferDark ? ThemeMode.dark : ThemeMode.system);
    skipSeconds.value = p.getInt('skipSeconds') ?? 15;
    defaultSpeed.value =
        p.getDouble('defaultSpeed') ?? p.getDouble('speed') ?? 1.0;
    sleepDefault.value = p.getInt('sleepDefault') ?? 30;
    autoRewind.value = p.getBool('autoRewind') ?? true;
    cloudAllowed.value = p.getBool('cloudAllowed') ?? false;
    voiceStudioEnabled.value = p.getBool('vsEnabled') ?? false;
    voiceStudioUrl.value = p.getString('vsUrl') ?? '';
    voiceStudioKey.value = p.getString('vsKey') ?? '';
    voiceStudioModel.value = p.getString('vsModel') ?? 'omnivoice';
    voiceStudioNarrationVoice.value =
        p.getString('vsNarrationVoice') ?? 'default';
    voiceStudioDialogueVoice.value =
        p.getString('vsDialogueVoice') ?? 'default';
    storageCapMb.value = p.getInt('storageCapMb') ?? 1024;
  }

  static ThemeMode? _themeMode(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _p?.setString('themeMode', mode.name);
  }

  Future<void> setSkipSeconds(int seconds) async {
    skipSeconds.value = seconds;
    await _p?.setInt('skipSeconds', seconds);
  }

  Future<void> setDefaultSpeed(double speed) async {
    defaultSpeed.value = speed;
    await _p?.setDouble('defaultSpeed', speed);
  }

  Future<void> setSleepDefault(int minutes) async {
    sleepDefault.value = minutes;
    await _p?.setInt('sleepDefault', minutes);
  }

  Future<void> setAutoRewind(bool value) async {
    autoRewind.value = value;
    await _p?.setBool('autoRewind', value);
  }

  Future<void> setCloudAllowed(bool value) async {
    cloudAllowed.value = value;
    await _p?.setBool('cloudAllowed', value);
  }

  Future<void> setVoiceStudioEnabled(bool value) async {
    voiceStudioEnabled.value = value;
    await _p?.setBool('vsEnabled', value);
  }

  Future<void> setVoiceStudioUrl(String value) async {
    voiceStudioUrl.value = value;
    await _p?.setString('vsUrl', value);
  }

  Future<void> setVoiceStudioKey(String value) async {
    voiceStudioKey.value = value;
    await _p?.setString('vsKey', value);
  }

  Future<void> setVoiceStudioModel(String value) async {
    voiceStudioModel.value = value;
    await _p?.setString('vsModel', value);
  }

  Future<void> setVoiceStudioNarrationVoice(String value) async {
    voiceStudioNarrationVoice.value = value;
    await _p?.setString('vsNarrationVoice', value);
  }

  Future<void> setVoiceStudioDialogueVoice(String value) async {
    voiceStudioDialogueVoice.value = value;
    await _p?.setString('vsDialogueVoice', value);
  }

  Future<void> setStorageCapMb(int mb) async {
    storageCapMb.value = mb;
    await _p?.setInt('storageCapMb', mb);
  }
}
