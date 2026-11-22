import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shisheng_reader/settings.dart';
import 'package:shisheng_reader/voicestudio.dart';

void main() {
  test('VoiceStudio：探测、PCM 合成、音色列表', () async {
    final seen = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((req) async {
      seen.add('${req.method} ${req.uri.path}');
      expect(req.headers.value('authorization'), 'Bearer test-key');
      if (req.uri.path == '/health') {
        req.response.statusCode = 200;
        req.response.write('{"ok":true}');
      } else if (req.uri.path == '/v1/audio/voices') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'voices': [
              {'voice_id': 'narrator', 'name': '旁白'},
              {'id': 'hero', 'name': '主角'},
            ],
          }),
        );
      } else if (req.uri.path == '/v1/audio/speech') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        expect(body['input'], '你好');
        expect(body['voice'], 'narrator');
        expect(body['response_format'], 'pcm');
        expect(body['model'], 'omnivoice');
        req.response.headers.contentType = ContentType.binary;
        // 两个 s16le 采样：0 和 256。
        req.response.add(<int>[0, 0, 0, 1]);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final s = AppSettings.instance;
    s.voiceStudioEnabled.value = true;
    s.voiceStudioUrl.value = 'http://127.0.0.1:${server.port}/';
    s.voiceStudioKey.value = 'test-key';
    s.voiceStudioModel.value = 'omnivoice';
    addTearDown(() {
      s.voiceStudioEnabled.value = false;
      s.voiceStudioUrl.value = '';
      s.voiceStudioKey.value = '';
      VoiceStudioTts.statusLine.value = null;
    });

    expect(await VoiceStudioTts.available(force: true), isTrue);

    final dir = await Directory.systemTemp.createTemp('shisheng_vs_test');
    addTearDown(() => dir.delete(recursive: true));
    final out = '${dir.path}${Platform.pathSeparator}seg.pcm';
    final r = await VoiceStudioTts.synth('你好', 'narrator', outPath: out);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.numSamples, 2);
    expect(await File(out).readAsBytes(), <int>[0, 0, 0, 1]);

    final voices = await VoiceStudioTts.voices();
    expect(voices.length, 2);
    expect(voices.first.id, 'narrator');
    expect(voices.last.name, '主角');

    expect(seen, contains('GET /health'));
    expect(seen, contains('POST /v1/audio/speech'));
    expect(seen, contains('GET /v1/audio/voices'));
  });

  test('VoiceStudio：401 会带回可读错误', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.statusCode = 401;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'error': {'message': 'bad key'},
        }),
      );
      await req.response.close();
    });

    final s = AppSettings.instance;
    s.voiceStudioEnabled.value = true;
    s.voiceStudioUrl.value = 'http://127.0.0.1:${server.port}';
    addTearDown(() {
      s.voiceStudioEnabled.value = false;
      s.voiceStudioUrl.value = '';
    });

    final dir = await Directory.systemTemp.createTemp('shisheng_vs_test_err');
    addTearDown(() => dir.delete(recursive: true));
    final r = await VoiceStudioTts.synth(
      '你好',
      'narrator',
      outPath: '${dir.path}${Platform.pathSeparator}seg.pcm',
    );
    expect(r.ok, isFalse);
    expect(r.error, contains('bad key'));
  });
}
