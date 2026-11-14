// 拾声 v4 · 全局单例：播放器 + 偏好存储。
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

final AudioPlayer audioPlayer = AudioPlayer();
late SharedPreferences prefs;
