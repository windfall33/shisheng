// 拾声 v4 · 引导：模型资产落盘 → 引擎启动 → 本地音频服务 → 渲染器就绪。
// 桌面（Windows）跑"预览模式"：跳过引擎，灌入演示书数据，仅用于界面截图/设计走查。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'globals.dart' show prefs;
import 'render.dart';
import 'store.dart';
import 'textfront.dart';
import 'tserver.dart';
import 'voices.dart';

class Boot {
  static TtsEngine? _engine;
  static final LocalServer server = LocalServer();
  static bool ready = false;
  static bool preview = false;
  static final ValueNotifier<bool> readyN = ValueNotifier<bool>(false);
  static String status = '准备引擎…';
  static String? error;

  static const _assetFiles = <String>[
    'model.int8.onnx',
    'voices.bin',
    'tokens.txt',
    'lexicon-zh.txt',
    'lexicon-us-en.txt',
    'lexicon-gb-en.txt',
    'date-zh.fst',
    'number-zh.fst',
    'phone-zh.fst',
  ];
  static TtsEngine get tts => _engine!;

  static Future<void> init() async {
    try {
      if (Platform.isWindows) {
        await _seedPreview();
        preview = true;
        status = '就绪（桌面预览：合成与播放在手机上）';
        ready = true;
        readyN.value = true;
        return;
      }
      final dir = await Data.modelDir();
      final marker = File('$dir${Platform.pathSeparator}.ready');
      if (!await marker.exists()) {
        status = '首次安装：解压离线语音模型（约 170MB，几十秒）…';
        final channel = const MethodChannel('shisheng/assets');
        try {
          for (final f in _assetFiles) {
            final dest =
                '$dir${Platform.pathSeparator}${f.replaceAll('/', Platform.pathSeparator)}';
            try {
              await channel.invokeMethod('copyAsset', {
                'asset': 'assets/tts/$f',
                'dest': dest,
              });
            } on MissingPluginException {
              // 桌面调试兜底：rootBundle 整体读入
              final data = await rootBundle.load('assets/tts/$f');
              final file = File(dest);
              await file.parent.create(recursive: true);
              await file.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
                flush: true,
              );
            }
          }
        } catch (e) {
          // 模型文件体积超过 GitHub 单文件限制，不入库：克隆后必须先跑下载脚本。
          status = '缺少离线语音模型';
          error = 'assets/tts/ 里没有语音模型。先在项目根目录运行 '
              'tool/fetch_model.sh（Windows 用 tool\\fetch_model.ps1）下载，再重新打包。\n$e';
          return;
        }
        await marker.writeAsString('ok');
      }
      status = '加载语音引擎…';
      final e = TtsEngine(dir, numThreads: 1, workers: 4);
      await e.start();
      _engine = e;
      status = '启动本地音频服务…';
      await server.start();
      await Renderer.ensure(() => tts);
      status = '就绪';
      ready = true;
      readyN.value = true;
    } catch (e) {
      error = e.toString();
      status = '初始化失败';
    }
  }

  static Future<void> enqueueAll(String bid, BookIR ir) async {
    if (preview) return;
    final r = await Renderer.ensure(() => tts);
    // 端侧不做全书预渲（手机存储/算力有限）：只预渲前几章，其余随听随渲/手动"转"
    for (final c in ir.chapters.take(3)) {
      // ignore: unawaited_futures
      r.touch(bid, c.seq, Renderer.priAuto);
    }
  }

  // ---------------------------------------------------------------- 桌面预览数据

  // 桌面预览用的公版书：《聊斋志异》劳山道士、画皮、婴宁（清·蒲松龄，公有领域）。
  // 开源仓库里不放任何在版权期内的书——包括测试夹具。
  static const _demoText = '''聊斋志异

第1章 劳山道士

邑有王生，行七，故家子。少慕道，闻劳山多仙人，负笈往游。登一顶，有观宇甚幽。一道士坐蒲团上，素发垂领，而神光爽迈。叩而与语，理甚玄妙。请师之，道士曰：“恐娇情不能作苦。”答言：“能之。”其门人甚众，薄暮毕集，王俱与稽首，遂留观中。

凌晨，道士呼王去，授一斧，使随众采樵。王谨受教。过月余，手足重茧，不堪其苦，阴有归志。一夕归，见二人与师共酌，日已暮，尚无灯烛。

第2章 画皮

太原王生早行，遇一女郎，抱襆独奔，甚艰于步，急走趁之，乃二八姝丽。心相爱乐，问：“何夙夜踽踽独行？”女曰：“行道之人，不能解愁忧，何劳相问。”

生代擕襆物，导与同归。女顾室无人，问：“君何无家口？”答云：“斋耳。”女曰：“此所良佳。如怜妾而活之，须秘密勿泄。”

第3章 婴宁

王子服，莒之罗店人。早孤，绝慧，十四入泮。母最爱之，寻常不令游郊野。聘萧氏，未嫁而夭，故求凰未就也。

会上元，有舅氏子吴生，邀同眺瞩。方至村外，舅家有仆来，招吴去。生见游女如云，乘兴独游。
''';

  static Future<void> _seedPreview() async {
    // 幂等：两本演示书始终补齐（书架预览需要多本书看效果）
    Future<void> ensure(String bid, String title) async {
      if (await Data.loadBook(bid) != null) return;
      final ir = loadBook([
        ('$title.txt', utf8.encode(_demoText)),
      ], bookTitle: title);
      await Data.saveBook(bid, ir);
      await Data.saveVoices(bid, BookVoices.defaults(bookTitle: title));
      await _fakeRender(bid, ir);
    }

    await ensure('preview-liaozhai-1', '聊斋志异·卷一');
    await ensure('preview-liaozhai-2', '聊斋志异·卷二');
    final books = await Data.listBooks();
    for (final (bid, ir) in books) {
      await _fakeRender(bid, ir);
    }
    if (prefs.getString('last') == null) {
      final (bid, ir) = books.first;
      await prefs.setString(
        'last',
        '{"bid":"$bid","title":"${ir.title}","seq":0,"pos":42000,"t":0}',
      );
    }
  }

  /// 伪造渲染产物：按 CPS 估时长 + 停顿表，落 index.json 和等长静音 PCM。
  static Future<void> _fakeRender(String bid, BookIR ir) async {
    final voices = await Data.loadVoices(bid);
    for (final c in ir.chapters) {
      final idx = <String, dynamic>{
        'seq': c.seq,
        'blocks': <dynamic>[],
        'done': false,
        'plan_blocks': 0,
        'total_bytes': 0,
        'total_ms': 0,
        'pipe': audioPipelineVersion,
      };
      final blocks = makeBlocks(c);
      idx['plan_blocks'] = blocks.length;
      var posMs = 0;
      for (var bidx = 0; bidx < blocks.length; bidx++) {
        final block = blocks[bidx];
        final blockStartMs = posMs;
        final segs = <Map<String, dynamic>>[];
        posMs += 100; // lead
        for (var i = 0; i < block.length; i++) {
          final seg = block[i];
          if (!hasWord(seg.text)) continue;
          final sid = voices.resolve(seg.type, seg.speaker);
          final durMs = (seg.text.length / RenderCfg.cps * 1000).round();
          segs.add({
            'seq': seg.seq,
            'start_ms': posMs,
            'end_ms': posMs + durMs,
            'voice': sid,
            'type': seg.type,
            'speaker': seg.speaker,
            'text': seg.text,
          });
          posMs += durMs;
          final nxt = i + 1 < block.length ? block[i + 1] : null;
          final pause = nxt == null || nxt.para != seg.para
              ? RenderCfg.pausePara
              : (nxt.type != seg.type || nxt.speaker != seg.speaker
                    ? RenderCfg.pauseVoice
                    : RenderCfg.pauseSent);
          posMs += (pause * 1000).round();
        }
        (idx['blocks'] as List).add({
          'bidx': bidx,
          'start_byte': blockStartMs * RenderCfg.bytesPerMs,
          'bytes': (posMs - blockStartMs) * RenderCfg.bytesPerMs,
          'segs': segs,
        });
        idx['total_ms'] = posMs;
        idx['total_bytes'] = posMs * RenderCfg.bytesPerMs;
      }
      idx['done'] = true;
      await Data.writeIndex(bid, c.seq, idx);
      final audio = await Data.audioPcm(bid, c.seq);
      final f = File(audio);
      await f.parent.create(recursive: true);
      if (!await f.exists()) {
        await f.writeAsBytes(
          Uint8List((idx['total_ms'] as int) * RenderCfg.bytesPerMs),
        );
      }
      await Data.saveProgress(bid, {'seq': 0, 'pos_ms': 42000});
    }
  }
}
