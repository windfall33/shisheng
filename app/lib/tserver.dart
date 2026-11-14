// 拾声 v4 · 本地音频服务：章级 WAV 虚拟流（边渲边播 + Range 跳转）。
// 虚拟文件 = 44 字节 WAV 头 + 章级 s16le PCM；渲完给真实长度，渲染中给无界流。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'render.dart';
import 'store.dart';

class LocalServer {
  HttpServer? _server;
  int port = 0;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = _server!.port;
    _server!.listen(_handle, onError: (_) {});
  }

  String audioUrl(String bid, int seq) =>
      'http://127.0.0.1:$port/audio/$bid/$seq.wav';

  Future<void> _handle(HttpRequest req) async {
    try {
      // 用 pathSegments：它已经做过百分号解码（uri.path 不会，中文书名会查不到）
      final segs = req.uri.pathSegments;
      if (segs.length != 3 || segs[0] != 'audio' || !segs[2].endsWith('.wav')) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final bid = segs[1];
      final seq = int.parse(segs[2].substring(0, segs[2].length - 4));
      await _serveAudio(req, bid, seq);
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveAudio(HttpRequest req, String bid, int seq) async {
    // 正在听 → NOW 优先
    // ignore: unawaited_futures
    Renderer.instance.touch(bid, seq, Renderer.priNow);
    // 等首块
    Map<String, dynamic>? idx;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      idx = await Data.readIndex(bid, seq);
      if (idx != null &&
          (((idx['blocks'] as List?)?.isNotEmpty ?? false) || idx['done'] == true)) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (idx == null || ((idx['blocks'] as List?)?.isEmpty ?? true)) {
      req.response.statusCode = 503;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"error":"render not started"}');
      await req.response.close();
      return;
    }
    final done = idx['done'] == true;
    final totalBytes = (idx['total_bytes'] as num?)?.toInt() ?? 0;
    // 未渲染完：按预估值给总长，避免进度条出现 1491 分钟这种荒谬时长
    final estMs = (idx['est_ms'] as num?)?.toInt() ?? 0;
    final plannedBytes = done
        ? totalBytes
        : (estMs > 0 ? estMs * RenderCfg.bytesPerMs : totalBytes);
    final total = 44 + plannedBytes;

    final (start, endLimit) = _parseRange(req.headers.value('range'), done, total);
    final res = req.response;
    res.statusCode = req.headers.value('range') != null ? 206 : 200;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (req.headers.value('range') != null) {
      res.headers.set(HttpHeaders.contentRangeHeader,
          done ? 'bytes $start-${(endLimit ?? total) - 1}/$total' : 'bytes $start-/*');
    }
    if (done && endLimit != null) {
      res.headers.set(HttpHeaders.contentLengthHeader, '${endLimit - start}');
    }

    // WAV 头（前 44 字节）；start>44 时直接从数据区给
    Uint8List header() => _wavHeader(plannedBytes, RenderCfg.sampleRate);
    var delivered = start;
    var idleDeadline = DateTime.now().add(const Duration(seconds: 300));
    if (delivered < 44) {
      final h = header();
      final take = h.length < (44 - delivered) ? h.length : (44 - delivered);
      res.add(Uint8List.sublistView(h, delivered, delivered + take));
      delivered = 44;
      await res.flush();
    }
    final audio = await Data.audioPcm(bid, seq);
    while (endLimit == null || delivered < endLimit) {
      final dataPos = delivered - 44;
      idx = await Data.readIndex(bid, seq);
      final avail = (idx?['total_bytes'] as num?)?.toInt() ?? 0;
      final chapterDone = idx?['done'] == true;
      if (dataPos >= avail) {
        if (chapterDone || (endLimit != null && delivered >= endLimit)) break;
        if (DateTime.now().isAfter(idleDeadline)) break;
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }
      idleDeadline = DateTime.now().add(const Duration(seconds: 900));
      var want = 1 << 16;
      if (endLimit != null) {
        want = want < (endLimit - delivered) ? want : (endLimit - delivered);
      }
      if (want > avail - dataPos) want = avail - dataPos;
      if (want <= 0) continue;
      final raf = await File(audio).open();
      try {
        await raf.setPosition(dataPos);
        final chunk = await raf.read(want);
        res.add(chunk);
        delivered += chunk.length;
        await res.flush();
      } finally {
        await raf.close();
      }
    }
    await res.close();
  }

  (int, int?) _parseRange(String? rangeH, bool done, int total) {
    var start = 0;
    int? endLimit;
    if (rangeH != null && rangeH.startsWith('bytes=')) {
      final spec = rangeH.substring(6).split(',')[0];
      final parts = spec.split('-');
      start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        endLimit = (int.tryParse(parts[1]) ?? 0) + 1;
      }
    }
    if (done && endLimit == null) endLimit = total;
    if (done && endLimit != null && endLimit > total) endLimit = total;
    return (start, endLimit);
  }
}

Uint8List _wavHeader(int? dataBytes, int sampleRate) {
  final b = ByteData(44);
  final bytes = b.buffer.asUint8List();
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[off + i] = s.codeUnitAt(i);
    }
  }

  final dataSize = dataBytes ?? 0xFFFFFFFF;
  final riffSize = dataBytes == null ? 0xFFFFFFFF : 36 + dataBytes;
  str(0, 'RIFF');
  b.setUint32(4, riffSize, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits
  str(36, 'data');
  b.setUint32(40, dataSize, Endian.little);
  return bytes;
}
