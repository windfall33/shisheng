// 拾声 · VoiceStudio 外接音色（可选，局域网/本机 HTTP）。
//
// VoiceStudio 是另一个独立应用（https://github.com/debpalash/VoiceStudio，
// AGPL-3.0）。这里只调用它公开文档里的 OpenAI 兼容 HTTP 接口，不包含、
// 不复制它的任何代码。用户需要先在自己的电脑或手机上运行 VoiceStudio。
//
// 接口：POST /v1/audio/speech
//   {"model":"omnivoice","input":"...","voice":"...","response_format":"pcm"}
// 返回 24kHz / 16-bit / mono little-endian PCM，正好是拾声渲染层的格式。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

class VoiceStudioReply {
  final bool ok;
  final int numSamples;
  final String? error;

  const VoiceStudioReply(this.ok, {this.numSamples = 0, this.error});
}

class VoiceStudioTts {
  static bool _online = false;
  static DateTime? _checkedAt;
  static String _lastConfig = '';
  static const Duration _ttl = Duration(seconds: 30);

  /// 最近一次探测 / 回退的结果，给设置页显示。
  static final ValueNotifier<String?> statusLine = ValueNotifier<String?>(null);

  static String get _rawBase =>
      AppSettings.instance.voiceStudioUrl.value.trim();

  static bool get configured =>
      AppSettings.instance.voiceStudioEnabled.value && _rawBase.isNotEmpty;

  /// 缓存命名用：不同 VoiceStudio 实例的同名 profile 不应互相命中。
  static String get endpointKey => _base();

  /// 接受 `http://host:3900`、`http://host:3900/`、`http://host:3900/v1`
  /// 三种写法；内部统一按根地址拼。
  static String _base() {
    var b = _rawBase;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/v1')) b = b.substring(0, b.length - 3);
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static Uri _uri(String path) => Uri.parse('${_base()}$path');

  static Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json, audio/*'};
    if (json) h['Content-Type'] = 'application/json';
    final key = AppSettings.instance.voiceStudioKey.value.trim();
    if (key.isNotEmpty) h['Authorization'] = 'Bearer $key';
    return h;
  }

  static String _hhmm() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  static void _status(String? s) => statusLine.value = s;

  static void noteFallback() {
    // 同一章后面不要再逐段等 60 秒；下一章也会先看到「离线」。
    _online = false;
    _checkedAt = DateTime.now();
    _status('VoiceStudio 合成失败，已回退本机（${_hhmm()}）');
  }

  /// 设置页「测试连接」和渲染前都会走这里。30 秒缓存，改地址/密钥立刻失效。
  static Future<bool> available({bool force = false}) async {
    if (!configured) {
      _status(null);
      return false;
    }
    final cfg = '${_base()}|${AppSettings.instance.voiceStudioKey.value}|'
        '${AppSettings.instance.voiceStudioModel.value}';
    if (force || cfg != _lastConfig) {
      _checkedAt = null;
      _lastConfig = cfg;
    }
    final now = DateTime.now();
    if (_checkedAt != null && now.difference(_checkedAt!) < _ttl) {
      return _online;
    }
    try {
      final r = await http
          .get(_uri('/health'), headers: _headers())
          .timeout(const Duration(seconds: 3));
      _online = r.statusCode >= 200 && r.statusCode < 300;
      _status(
        _online
            ? 'VoiceStudio 已连接（${_hhmm()} 探测）'
            : 'VoiceStudio 返回 ${r.statusCode}，暂时用本机合成',
      );
    } catch (_) {
      _online = false;
      _status('VoiceStudio 连不上，暂时用本机合成（${_hhmm()}）');
    }
    _checkedAt = now;
    return _online;
  }

  /// 合成一段，直接写 s16le PCM。失败时调用方回退本机音色。
  static Future<VoiceStudioReply> synth(
    String text,
    String voice, {
    required String outPath,
  }) async {
    try {
      final model = AppSettings.instance.voiceStudioModel.value.trim();
      final body = <String, dynamic>{
        'model': model.isEmpty ? 'omnivoice' : model,
        'input': text,
        'voice': voice.trim().isEmpty ? 'default' : voice.trim(),
        'response_format': 'pcm',
        // 语速在播放端变调不变，合成统一 1.0，缓存不随倍速失效。
        'speed': 1.0,
      };
      final r = await http
          .post(
            _uri('/v1/audio/speech'),
            headers: _headers(json: true),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        var msg = 'HTTP ${r.statusCode}';
        try {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          if (j is Map && j['error'] is Map) {
            final m = (j['error'] as Map)['message'];
            if (m != null) msg = m.toString();
          }
        } catch (_) {}
        return VoiceStudioReply(false, error: msg);
      }
      final bytes = r.bodyBytes;
      if (bytes.isEmpty) {
        return const VoiceStudioReply(false, error: '返回空音频');
      }
      await File(outPath).writeAsBytes(bytes, flush: true);
      return VoiceStudioReply(true, numSamples: bytes.length ~/ 2);
    } catch (e) {
      return VoiceStudioReply(false, error: e.toString());
    }
  }

  /// 给设置页拉音色列表；失败返回空表，不阻塞任何播放。
  static Future<List<({String id, String name})>> voices() async {
    if (!configured) return const <({String id, String name})>[];
    try {
      final r = await http
          .get(_uri('/v1/audio/voices'), headers: _headers())
          .timeout(const Duration(seconds: 5));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return const <({String id, String name})>[];
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final list = (j is Map ? j['voices'] : null) as List?;
      if (list == null) return const <({String id, String name})>[];
      return <({String id, String name})>[
        for (final e in list)
          if (e is Map)
            (
              id: (e['voice_id'] ?? e['id'] ?? '').toString(),
              name: (e['name'] ?? e['voice_id'] ?? '').toString(),
            ),
      ].where((v) => v.id.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const <({String id, String name})>[];
    }
  }
}
