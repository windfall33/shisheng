// 引擎池消息接线回归：假 worker（不依赖 sherpa）验证 ready/init/result 路由。
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// 与 _ttsWorker 相同的消息拓扑：ready 走 spawn 端口，init 回执与结果走自己的 recv
Future<void> fakeWorker(SendPort port) async {
  final recv = ReceivePort();
  port.send({'ready': recv.sendPort});
  await for (final m in recv) {
    final map = m as Map;
    if (map['cmd'] == 'init') {
      port.send({'initialized': true});
    } else if (map['cmd'] == 'synth') {
      File(map['out'] as String).writeAsBytesSync([1, 2, 3, 4]);
      port.send({'id': map['id'], 'ok': true, 'sampleRate': 24000, 'numSamples': 1});
    }
  }
}

Future<void> main() async {
  var failed = false;
  final lp = ReceivePort();
  final res = ReceivePort();
  final iso = await Isolate.spawn(fakeWorker, lp.sendPort);
  SendPort? workerSend;
  final ready = Completer<void>();
  final done = Completer<void>();
  lp.listen((m) {
    final map = m as Map;
    if (map['ready'] != null) {
      workerSend = map['ready'] as SendPort;
      workerSend!.send({'cmd': 'init', 'modelDir': 'x', 'threads': 1});
      return;
    }
    if (map['initialized'] == true && !ready.isCompleted) {
      ready.complete();
      return;
    }
    if (map.containsKey('id')) {
      final ok = map['ok'] == true;
      final bytes = File('${Directory.systemTemp.path}/poolwire.pcm').lengthSync();
      if (!ok || bytes != 4) failed = true;
      done.complete();
    }
  });
  await ready.future.timeout(const Duration(seconds: 5));
  workerSend!.send({'cmd': 'synth', 'id': 1, 'text': 'x', 'sid': 0,
      'speed': 1.0, 'out': '${Directory.systemTemp.path}/poolwire.pcm'});
  await done.future.timeout(const Duration(seconds: 5));
  print(failed ? 'POOL WIRE FAIL' : 'POOL WIRE OK');
  iso.kill();
  exit(failed ? 1 : 0);
}
