// 拾声 v4 · 文本前端（textfront.py 的 Dart 移植）。
// 职责：编码嗅探 → 章节切分（三级+去重+伪章归并）→ 水印过滤 → 脏字映射 →
//       引号分段（旁白/对白/拟声三型）→ 说话人归因。
// 与 PC 版 book.json 结构保持一致，规则全部照搬（126 万字真语料验证过的那套）。
import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

const dirtyMapVersion = '2026.11.08.1';

const defaultDirtyMap = <String, String>{
  '什幺': '什么',
  '怎幺': '怎么',
  '那幺': '那么',
  '多幺': '多么',
  '写著': '写着',
  '擡': '抬',
};

const sfxWords = <String>{
  '咔嚓', '砰', '咚', '哐当', '哗啦', '咕噜', '轰', '噗', '嗡', '叮', '哐',
  '锵', '噼啪', '扑通', '吱呀', '嗖', '咻', '嘭', '咣', '啪', '哗', '唰',
  '咔', '滴答', '咯吱', '咯噔', '轰隆', '沙沙', '簌簌', '咕咚', '噗嗤',
};

final aabbRe = RegExp(r'^([一-龥])\1([一-龥])\2[！!。.~～]*$');
final coreRe = RegExp(r'[^一-龥]');
// 引号体系：直角「」与弯引号“”。混排时取先出现的开口、按同体系闭合。
const quotePairs = <List<String>>[['「', '」'], ['“', '”']];

final titleRules = <RegExp>[
  RegExp(r'^第([0-9０-９]+)章\s*(\S.*?)\s*$'),
  RegExp(r'^第([0-9０-９零一二三四五六七八百千万两]+)[章節卷回话]\s*(\S.*?)\s*$'),
];
final pseudoRe = RegExp(r'^(完结感言|番外\S*|尾声|楔子|序章)$');
const cnDigitsMap = <String, String>{
  '０': '0', '１': '1', '２': '2', '３': '3', '４': '4',
  '５': '5', '６': '6', '７': '7', '８': '8', '９': '9',
};

final watermarkRules = <List<dynamic>>[
  ['end_marker', RegExp(r'[（(]\s*本章完\s*[)）]')],
  ['site', RegExp(r'看书网|小说网|文学网|听书网|追书网')],
  ['promo', RegExp(r'记住我们|请记住|记得分享|首发|更新时间|域名|网址|sudugu|www\.|https?://')],
  ['bracket_ad', RegExp(r'【[^】]*】')],
  ['rule_line', RegExp(r'^[—\-=_~–·…]{3,}$')],
  ['book_end', RegExp(r'^[^（）]{1,12}（完）$')],
  ['volume_end', RegExp(r'^第[0-9０-９零一二三四五六七八百千万两]{1,4}卷\s*[（(]?\s*完\s*[)）]?$')],
];

const verbs =
    '说道|说|道|问道|问|喊道|喊|骂道|骂|笑道|冷笑道|大笑道|狂笑道|怒道|吼道|吼|'
    '吩咐道|吩咐|回答道|回答|答道|应道|回道|嘀咕道|嘀咕|喃喃道|喃喃|嘟囔道|嘟囔|'
    '念叨|威胁道|哀求道|求道|感叹道|叹道|追问|追问道|插嘴|接话|开口道|开口|惊呼|'
    '尖叫道|尖叫|高声道|轻声道|低声道|沉声道|厉声道|咕哝道|咕哝|叫道|叫|'
    '轻笑|微笑|苦笑|失笑|干笑|一笑|冷哼道|冷哼|嘟哝道|嘟哝|嗤笑道|嗤道|叹了口气';
final preHeadRe = RegExp('^([\\u4e00-\\u9fa5]{1,4})($verbs)(?=[：:，。！？…\\s「]|\$)');
final verbsSorted =
    (verbs.split('|')..sort((a, b) => b.length.compareTo(a.length)));

const punct = '：:，,。！？!?.；;、 　（）()「」『』“”"\'“”…—';
const prefixes = [
  '只听', '只见', '听到', '听着', '半晌', '许久', '这时', '随后', '接着',
  '然后', '闻言', '顿了顿', '话音落下', '话音刚落', '说完', '想了想'
];
const adverbs = [
  '幽幽', '微微', '轻轻', '缓缓', '淡淡', '静静', '冷冷', '深深', '急急',
  '连忙', '急忙', '立刻', '顿时', '随即', '终于', '沉声', '冷声', '轻声',
  '高声', '大声', '柔声', '厉声', '忙', '才', '就', '便', '也', '又',
  '还', '都', '刚', '已', '正', '只',
  '心中', '心里', '心下', '暗道', '暗想', '暗骂', '心想', '声音', '语气',
  '口气', '话音', '眼中', '目光', '脸上', '忽然', '突然', '继续', '接着',
  '随即', '跟着', '压低', '提高', '放低', '露出', '一丝', '一副', '不由',
  '似乎', '仿佛', '显得', '带着', '一口气', '喃喃', '急道', '暗道一声',
  '再次', '重新', '一边', '一面', '哑然', '低声', '冷眼', '凑过来', '凑上前',
  '压到最低', '最低', '深吸一口气', '吸了口气', '喘了口气', '深吸', '吸了',
  '沉吟', '张了张', '打量', '扫了', '瞥了', '琢磨', '喘', '压',
  '低眉', '抬头', '低头', '侧头', '偏头', '回头', '扭头', '咧了咧',
  '知道', '想到', '料到', '感到', '觉得', '记得', '特意', '嘴上', '有几分'
];
const connectors = '跟和与对向朝冲请让令叫教';
const pronouns = '他她它你我俺咱那这';

const badName = {
  '声音', '口气', '语气', '口中', '话音', '那人', '有人', '众人', '一人', '自己',
  '对方', '两人', '双方', '的话', '心里', '心中', '所有', '脑袋', '脑子',
  '一条', '这句', '一声', '半晌', '突然', '忽然', '上前', '一步', '转身', '回头',
  '上前一步', '转过身', '回过头', '低下头', '抬起头', '点了点', '摇了摇',
  '顿了顿', '沉默', '片刻', '许久', '这时', '此时', '最后', '然后', '接着',
  '只见', '听到', '说完', '闻言', '随即', '顿时'
};
const actionWords = [
  '说', '道', '笑', '问', '喊', '骂', '叫', '吼', '喝', '嚷', '呼', '答', '应',
  '嘀咕', '喃喃', '嘟囔', '嘟哝', '开口', '回头', '转身', '点头', '摇头',
  '掩嘴', '咧嘴', '皱眉', '挑眉', '耸肩', '瞪眼', '抬手', '挥手', '摆手',
  '拍', '推', '拉', '扯', '盯', '瞥', '瞅', '瞧', '想了想', '愣', '沉吟'
];
final stripWords = [...{...actionWords, ...adverbs}]
  ..sort((a, b) => b.length.compareTo(a.length));

// ---------------------------------------------------------------- 数据结构

class Segment {
  int seq;
  String text;
  String type; // narration | dialogue | sfx
  String? speaker;
  String? how;
  bool unclosed;
  int para;
  int chapterSeq;
  Segment({required this.seq, required this.text, required this.type,
      this.speaker, this.how, this.unclosed = false, this.para = 0,
      this.chapterSeq = 0});

  Map<String, dynamic> toJson() => {
        'seq': seq, 'text': text, 'type': type, 'speaker': speaker, 'how': how,
        'unclosed': unclosed, 'para': para, 'chapter_seq': chapterSeq,
      };
  static Segment from(Map<String, dynamic> m) => Segment(
      seq: (m['seq'] as num).toInt(),
      text: (m['text'] ?? '') as String,
      type: (m['type'] ?? 'narration') as String,
      speaker: m['speaker'] as String?,
      how: m['how'] as String?,
      unclosed: m['unclosed'] == true,
      para: (m['para'] as num?)?.toInt() ?? 0,
      chapterSeq: (m['chapter_seq'] as num?)?.toInt() ?? 0);
}

class Chapter {
  int seq;
  int? no;
  String title;
  String file;
  int line;
  List<Segment> segments;
  bool endMarker;
  int rawLines;
  String source;
  int paras;
  Chapter({required this.seq, this.no, required this.title, required this.file,
      required this.line, List<Segment>? segments, this.endMarker = false,
      this.rawLines = 0, this.source = 'parsed'})
      : segments = segments ?? [],
        paras = 0;

  Map<String, dynamic> toJson() => {
        'seq': seq, 'no': no, 'title': title, 'file': file, 'line': line,
        'segments': segments.map((s) => s.toJson()).toList(),
        'end_marker': endMarker, 'raw_lines': rawLines, 'source': source,
      };
}

/// 角色画像（年龄/气质），由 persona.dart 提取
class Persona {
  final String name;
  String gender;
  String? age;   // child | youth | young | mid | old
  String? type;  // rough | frail | sinister | gentle | stern
  int score = 0;
  Persona(this.name, this.gender);
}

class BookIR {
  String title;
  List<Chapter> chapters;
  List<int> skips;
  List<Map<String, dynamic>> watermarkHits;
  Map<String, String> encodings;
  String chapterSource;
  Map<String, Persona> personas = {};
  BookIR({required this.title, required this.chapters, required this.skips,
      required this.watermarkHits, required this.encodings,
      this.chapterSource = 'parsed'});

  int get hanChars {
    var n = 0;
    for (final c in chapters) {
      for (final s in c.segments) {
        for (final ch in s.text.runes) {
          if (ch >= 0x4e00 && ch <= 0x9fff) n++;
        }
      }
    }
    return n;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'skips': skips,
        'watermark_hits': watermarkHits,
        'encodings': encodings,
        'dirty_map_version': dirtyMapVersion,
        'chapter_source': chapterSource,
      };

  Chapter? chapter(int seq) {
    for (final c in chapters) {
      if (c.seq == seq) return c;
    }
    return null;
  }
}

// ---------------------------------------------------------------- 工具

bool hasWord(String text) {
  for (final r in text.runes) {
    if ((r >= 0x4e00 && r <= 0x9fff) ||
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x41 && r <= 0x5a) ||
        (r >= 0x61 && r <= 0x7a)) {
      return true;
    }
  }
  return false;
}

String normTitle(String t) {
  final sb = StringBuffer();
  for (final r in t.runes) {
    final ch = String.fromCharCode(r);
    final lower = ch.toLowerCase();
    if ((r >= 0x30 && r <= 0x39) || (r >= 0x41 && r <= 0x5a) ||
        (r >= 0x61 && r <= 0x7a) || (r >= 0x4e00 && r <= 0x9fff)) {
      sb.write(lower);
    }
  }
  return sb.toString().replaceAll('幺', '么').split('').map((c) => cnDigitsMap[c] ?? c).join();
}

const cnNum = <String, int>{
  '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9
};

int? cnToInt(String s) {
  var total = 0, section = 0, num = 0;
  for (final ch in s.split('')) {
    if (cnNum.containsKey(ch)) {
      num = cnNum[ch]!;
    } else if (ch == '十') {
      section += (num == 0 ? 1 : num) * 10;
      num = 0;
    } else if (ch == '百') {
      section += (num == 0 ? 1 : num) * 100;
      num = 0;
    } else if (ch == '千') {
      section += (num == 0 ? 1 : num) * 1000;
      num = 0;
    } else if (ch == '万') {
      total = (total + section + num) * 10000;
      section = num = 0;
    } else {
      return null;
    }
  }
  final r = total + section + num;
  return (total == 0 && section == 0 && num == 0) ? null : r;
}

(int?, String)? matchTitle(String line) {
  for (final rule in titleRules) {
    final m = rule.firstMatch(line);
    if (m == null) continue;
    final g1 = m.group(1)!;
    final isNum = RegExp(r'^[0-9０-９]+$').hasMatch(g1);
    if (!isNum) {
      if (line.length > 30 ||
          line.split('').any((c) => '，。！？；…'.contains(c))) {
        continue;
      }
      if (RegExp(r'[（(]?\s*完\s*[)）]?$').hasMatch(line)) continue;
    }
    int? no;
    if (isNum) {
      no = int.tryParse(g1.split('').map((c) => cnDigitsMap[c] ?? c).join());
    } else {
      no = cnToInt(g1);
    }
    if (no != null) {
      return (no, m.groupCount >= 2 ? (m.group(2) ?? '') : '');
    }
  }
  return null;
}

String applyDirtyMap(String text, Map<String, String>? userMap) {
  final mapping = <String, String>{...defaultDirtyMap, ...?userMap};
  if (mapping.isEmpty) return text;
  final keys = mapping.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  for (final k in keys) {
    if (out.isEmpty) break;
    out = out.split(k).join(mapping[k]!);
  }
  return out;
}

// 编码嗅探：BOM → UTF-8 严格 → GBK → UTF-16（PC 版顺序的 Dart 适配）
(String, String) sniffDecode(List<int> raw) {
  if (raw.length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf) {
    return (utf8.decode(raw.sublist(3), allowMalformed: true), 'utf-8-sig');
  }
  // UTF-16（BOM 或无 BOM 零字节探测）
  final utf16leBom = raw.length >= 2 && raw[0] == 0xff && raw[1] == 0xfe;
  final utf16beBom = raw.length >= 2 && raw[0] == 0xfe && raw[1] == 0xff;
  var zeros = 0;
  for (var i = 1; i < raw.length && i < 400; i += 2) {
    if (raw[i] == 0) zeros++;
  }
  final looksUtf16 =
      utf16leBom || utf16beBom || (raw.length > 400 && zeros > 100);
  if (looksUtf16) {
    final little = !utf16beBom;
    final start = (utf16leBom || utf16beBom) ? 2 : 0;
    final units = <int>[];
    for (var i = start; i + 1 < raw.length; i += 2) {
      units.add(little ? (raw[i] | (raw[i + 1] << 8)) : ((raw[i] << 8) | raw[i + 1]));
    }
    return (String.fromCharCodes(units), 'utf-16');
  }
  try {
    final strict = utf8.decode(raw); // 非法字节直接抛
    return (strict, 'utf-8');
  } catch (_) {
    try {
      return (gbk.decode(raw), 'gb18030');
    } catch (_) {
      return (utf8.decode(raw, allowMalformed: true), 'utf-8');
    }
  }
}

List<Map<String, dynamic>> segParagraph(String text) {
  final segs = <Map<String, dynamic>>[];
  var i = 0;
  final n = text.length;
  while (i < n) {
    var o = -1;
    var closeCh = '';
    for (final pair in quotePairs) {
      final p = text.indexOf(pair[0], i);
      if (p >= 0 && (o < 0 || p < o)) {
        o = p;
        closeCh = pair[1];
      }
    }
    if (o < 0) {
      if (i < n) {
        segs.add({'type': 'narration', 'text': text.substring(i), 'off': i, 'unclosed': false});
      }
      break;
    }
    if (o > i) {
      segs.add({'type': 'narration', 'text': text.substring(i, o), 'off': i, 'unclosed': false});
    }
    final c = text.indexOf(closeCh, o + 1);
    // 对白保留引号：播放页显示的是书里的原话。「」和 “” 都给引擎时会被跳过，
    // 所以真正合成时用的是 ttsNormalize 之后再交给引擎的那份（见 render.dart 的 _SegJob）。
    if (c < 0) {
      segs.add({'type': 'dialogue', 'text': text.substring(o), 'off': o, 'unclosed': true});
      break;
    }
    segs.add({'type': 'dialogue', 'text': text.substring(o, c + 1), 'off': o, 'unclosed': false});
    i = c + 1;
  }
  return segs;
}

const _badPrefix = '不没怎那这他她我你它别再又还就才只先已正很太更最可能要会能被把让给对向从在到是有无';

const _stopWords = {
  '一个', '什么', '怎么', '这个', '那个', '现在', '然后', '接着', '这时', '此时', '最后', '说完', '闻言', '顿时', '突然', '忽然', '直接', '一旁', '表情', '看向', '开始', '继续', '似乎', '仿佛', '显得', '带着', '心中', '心里', '声音', '语气', '话音', '目光', '脸上', '眼中', '众人', '有人', '两人', '对方', '自己', '一声', '一句', '一步', '一下', '一边', '一面', '只是', '不过', '并不', '没有', '不能', '不会', '知道', '觉得', '感到', '看到', '听到', '发现', '明白', '意识', '起来', '出来', '过来', '上去', '下来', '进去', '出去', '回头', '转身', '点头', '摇头', '所有', '一切', '东西', '事情', '地方', '时候', '身体', '眼睛', '手中', '身上', '但是', '双手', '于是', '如果', '因为', '所以', '虽然', '可是', '然而', '而且', '并且', '甚至', '终于', '果然', '依然', '仍然', '自然', '显然', '当然', '其实', '原来', '本来', '只能', '这样', '那样', '怎样', '如何', '为何', '这里', '那里', '哪里', '这些', '那些', '其中', '其他', '别的', '整个', '半天', '瞬间', '刹那', '片刻', '一时', '用手', '用力', '伸手', '抬手', '挥手', '抬头', '低头', '过去', '和尚', '女人', '男人', '所有人', '人们', '大家', '别人',
};

const _badSuffix = '把被将向对给让使令叫在从到和与跟着了的得是有没不就都也还又才只很太更最一二三四五六七八九十';

bool nameOk(String n) {
  if (n.isEmpty || n.length < 2 || n.length > 4) return false;
  if (_badPrefix.contains(n[0])) return false;
  if (_badSuffix.contains(n[n.length - 1])) return false;
  if (_stopWords.contains(n)) return false;
  if (n.split('').any((c) => '的了着地得呢吧吗啊呀哦'.contains(c))) return false;
  if (n.split('').any((c) => pronouns.contains(c))) return false;
  for (final w in actionWords) {
    if (n.contains(w)) return false;
  }
  for (final w in badName) {
    if (n.contains(w)) return false;
  }
  for (final w in adverbs) {
    if (n.contains(w)) return false;
  }
  return true;
}

String? nameFromTail(String text, {bool splitClause = false}) {
  var s = text.trim();
  while (s.isNotEmpty && punct.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  for (final pfx in prefixes) {
    if (s.startsWith(pfx)) {
      s = s.substring(pfx.length);
      break;
    }
  }
  if (splitClause) {
    for (final sep in ['，', '。', '！', '？', '；', '…', '、']) {
      final idx = s.lastIndexOf(sep);
      if (idx >= 0) s = s.substring(idx + 1);
    }
    while (s.isNotEmpty && punct.contains(s[0])) {
      s = s.substring(1);
    }
  }
  for (final v in verbsSorted) {
    if (s.length > v.length && s.endsWith(v)) {
      var run = s.substring(0, s.length - v.length);
      while (run.isNotEmpty && punct.contains(run[run.length - 1])) {
        run = run.substring(0, run.length - 1);
      }
      var changed = true;
      while (changed && run.isNotEmpty) {
        changed = false;
        for (final w in stripWords) {
          if (run.endsWith(w) && run.length > w.length + 1) {
            run = run.substring(0, run.length - w.length);
            changed = true;
            break;
          }
        }
      }
      if (run.length > 4) {
        final head = run.substring(0, run.length - 4);
        for (final c in head.split('')) {
          if (!(pronouns + connectors).contains(c)) return null;
        }
      }
      var name = run.length > 4 ? run.substring(run.length - 4) : run;
      while (name.isNotEmpty && connectors.contains(name[0])) {
        name = name.substring(1);
      }
      return nameOk(name) ? name : null;
    }
  }
  return null;
}

final _contextVerbRe = RegExp(
    r'(?:听到|只听|听见|看到|只见|望着|看着|对着|冲|向)([一-龥]{2,4})'
    r'(?:说|道|问|喊|叫|回答|开口|笑道|冷哼|嘀咕|喃喃)');
final _soundRe = RegExp(r'([一-龥]{2,4})的声音(?:响起|传来|说道)?');
final _speakRe = RegExp(r'([一-龥]{2,4})(?:说完|说着|问道|答道|开口道)');

String? _nameByPatterns(String text) {
  for (final re in [_contextVerbRe, _soundRe, _speakRe]) {
    final m = re.firstMatch(text);
    if (m != null) {
      final n = m.group(1)!;
      if (nameOk(n)) return n;
    }
  }
  return null;
}

void attribute(String paragraphText, List<Map<String, dynamic>> segs) {
  final dials = segs
      .where((s) => s['type'] == 'dialogue' && (s['text'] as String).trim().isNotEmpty)
      .toList();
  for (final s in dials) {
    final off = s['off'] as int;
    final pre = off > 0 ? paragraphText.substring(0, off - 1) : '';
    var name = nameFromTail(pre);
    if (name != null) {
      s['speaker'] = name;
      s['how'] = 'pre_verb';
      continue;
    }
    final postStart = off + (s['text'] as String).length;
    final post = postStart < paragraphText.length
        ? paragraphText.substring(postStart).substring(0,
            (paragraphText.length - postStart) < 40 ? paragraphText.length - postStart : 40)
        : '';
    name = nameFromTail(post, splitClause: true);
    if (name != null) {
      s['speaker'] = name;
      s['how'] = 'post_verb';
      continue;
    }
    name = _nameByPatterns('$pre$post');
    if (name != null) {
      s['speaker'] = name;
      s['how'] = 'context_verb';
      continue;
    }
    s['speaker'] = null;
    s['how'] = null;
  }
  String? first;
  for (final s in dials) {
    if (s['speaker'] != null) {
      first = s['speaker'] as String?;
      break;
    }
  }
  if (first != null) {
    for (final s in dials) {
      if (s['speaker'] == null) {
        s['speaker'] = first;
        s['how'] = 'inherit';
      }
    }
  }
}

bool isSfx(Map<String, dynamic> seg) {
  final core = seg['text'].replaceAll(coreRe, '');
  return sfxWords.contains(core) ||
      aabbRe.hasMatch(core) ||
      (core.length <= 2 && sfxWords.contains(core));
}

// ---------------------------------------------------------------- 导入主流程

BookIR loadBook(List<(String, List<int>)> files, {String bookTitle = ''}) {
  final chapters = <Chapter>[];
  final hits = <Map<String, dynamic>>[];
  final encodings = <String, String>{};
  Chapter? cur;
  (int, String)? pending;
  List<Segment> prevPending = [];
  var segSeq = 0;
  var inPre = true;

  for (final (fname, raw) in files) {
    final (text, enc) = sniffDecode(raw);
    encodings[fname] = enc;
    final lines = text.split('\n'); // 显式 \n，与 PC 版一致
    for (var ln = 0; ln < lines.length; ln++) {
      final line = lines[ln].trim();
      if (line.isEmpty) continue;
      final mt = matchTitle(line);
      if (mt != null) {
        final no = mt.$1!;
        final title = mt.$2;
        final ntt = normTitle(title);
        if (pending != null && pending == (no, ntt)) {
          cur?.rawLines++;
          pending = null;
          continue;
        }
        cur = Chapter(seq: chapters.length, no: no, title: title,
            file: fname, line: ln + 1);
        chapters.add(cur);
        pending = (no, ntt);
        prevPending = [];
        inPre = false;
        continue;
      }
      final pm = pseudoRe.firstMatch(line);
      if (pm != null) {
        if (cur != null && cur.title == pm.group(1) && cur.segments.isEmpty && cur.rawLines <= 1) {
          cur.rawLines++;
          continue;
        }
        cur = Chapter(seq: chapters.length, no: null, title: pm.group(1)!,
            file: fname, line: ln + 1);
        chapters.add(cur);
        pending = null;
        prevPending = [];
        inPre = false;
        continue;
      }
      final tags = <String>[];
      for (final rule in watermarkRules) {
        if ((rule[1] as RegExp).hasMatch(line)) tags.add(rule[0] as String);
      }
      if (tags.isNotEmpty) {
        hits.add({'file': fname, 'line': ln + 1,
            'chapter': cur?.no, 'tags': tags, 'text': line.substring(0, line.length < 100 ? line.length : 100)});
        if (cur != null) {
          cur.rawLines++;
          if (tags.contains('end_marker')) cur.endMarker = true;
        }
        continue;
      }
      if (inPre || cur == null) continue;
      cur.rawLines++;
      pending = null;
      final cleaned = applyDirtyMap(line, null);
      final segs = segParagraph(cleaned);
      attribute(cleaned, segs);
      cur.paras++;
      final qIdx = cleaned.indexOf('「');
      final head = qIdx >= 0 ? cleaned.substring(0, qIdx) : cleaned;
      final hm = preHeadRe.firstMatch(head);
      if (hm != null && nameOk(hm.group(1)!) && prevPending.isNotEmpty) {
        for (final s in prevPending) {
          s.speaker = hm.group(1);
          s.how = 'next_para';
        }
        prevPending = [];
      }
      for (final s in segs) {
        final stype = s['type'] as String;
        final stext = s['text'] as String;
        if (stype == 'dialogue' && stext.trim().isEmpty) continue;
        if (!hasWord(stext)) continue;
        var type = stype;
        if (type == 'dialogue' && s['speaker'] == null && isSfx(s)) {
          type = 'sfx';
        }
        segSeq++;
        cur.segments.add(Segment(
            seq: segSeq, text: stext, type: type,
            speaker: s['speaker'] as String?, how: s['how'] as String?,
            unclosed: s['unclosed'] == true, para: cur.paras,
            chapterSeq: cur.seq));
      }
      final c = cur;
      prevPending = c.segments
          .where((s) => s.chapterSeq == c.seq && s.type == 'dialogue'
              && s.para == c.paras && s.speaker == null)
          .toList();
    }
  }

  final nums = chapters.where((c) => c.no != null).map((c) => c.no!).toList();
  final skips = <int>[];
  if (nums.isNotEmpty) {
    final mx = nums.reduce((a, b) => a > b ? a : b);
    final set = nums.toSet();
    for (var i = 1; i <= mx; i++) {
      if (!set.contains(i)) skips.add(i);
    }
  }
  return BookIR(
      title: bookTitle.isNotEmpty ? bookTitle : files.first.$1,
      chapters: chapters, skips: skips, watermarkHits: hits, encodings: encodings);
}

// ---------------------------------------------------------------- 固定切分兜底

const fixedChunkChars = 3000;
const fixedMinChapters = 3;

bool _inQuote(String line) =>
    '「'.allMatches(line).length > '」'.allMatches(line).length ||
    '“'.allMatches(line).length > '”'.allMatches(line).length;

/// 无章节标题的书：按段落聚合 ~3000 字一章（bookfront._fixed_split 移植）。
BookIR loadBookFixed(List<(String, List<int>)> files, String title) {
  final chapters = <Chapter>[];
  var segSeq = 0;
  var curLen = 0;
  Chapter newChapter() {
    final c = Chapter(seq: chapters.length, no: null,
        title: '${title.isEmpty ? '正文' : title} ${'${chapters.length + 1}'.padLeft(2, '0')}',
        file: '', line: 0, source: 'fixed');
    chapters.add(c);
    return c;
  }

  var cur = newChapter();
  for (final (_, raw) in files) {
    final (text, _) = sniffDecode(raw);
    for (final rawLine in text.split('\n')) {
      final line = applyDirtyMap(rawLine.trim(), null);
      if (line.isEmpty) continue;
      var hit = false;
      for (final rule in watermarkRules) {
        if ((rule[1] as RegExp).hasMatch(line)) { hit = true; break; }
      }
      if (hit) continue;
      if (curLen >= fixedChunkChars && !_inQuote(line)) {
        cur = newChapter();
        curLen = 0;
        cur.paras = 0;
      }
      final segs = segParagraph(line);
      attribute(line, segs);
      curLen += line.length;
      cur.paras++;
      for (final s in segs) {
        if (s['type'] == 'dialogue' && (s['text'] as String).trim().isEmpty) {
          continue;
        }
        segSeq++;
        cur.segments.add(Segment(
            seq: segSeq, text: s['text'] as String, type: s['type'] as String,
            speaker: s['speaker'] as String?, how: s['how'] as String?,
            unclosed: s['unclosed'] == true, para: cur.paras,
            chapterSeq: cur.seq));
      }
    }
  }
  return BookIR(title: title.isEmpty ? '未命名' : title, chapters: chapters,
      skips: [], watermarkHits: [], encodings: {}, chapterSource: 'fixed');
}

int rawHanChars(List<(String, List<int>)> files) {
  var n = 0;
  for (final (_, raw) in files) {
    final (text, _) = sniffDecode(raw);
    for (final r in text.runes) {
      if (r >= 0x4e00 && r <= 0x9fff) n++;
    }
  }
  return n;
}

/// 章节级说话人传播（解决规则归因覆盖率低导致"全员男声"的问题）：
/// 1) 从全书旁白统计高频人名（名字 + 动作/说话动词）；
/// 2) 段内取离对白最近的旁白人名；
/// 3) 段内无名 → 就近继承已知说话人。
final _nameVerbRe = RegExp(
    r'([一-龥]{2,4})(?:说道|说|道|问道|问|喊道|喊|叫道|叫|回答|答道|开口|'
    r'轻声|低声|沉声|高声|冷笑|笑道|笑|伸手|点头|摇头|皱眉|叹|站|走|看|转|抬|低|望|盯|拉|推)');

const _speechVerb = '说道|问道|答道|笑道|喝道|喊道|叫道|问道|问|说|道|喊|叫|答|开口|轻声|低声|沉声|高声';

/// 从旁白里取说话人：有言语动词取动词前/后最近的人名；否则取最后一个分句的第一个名字。
String? _pickNameFromNarration(String text, List<String> pool, {required bool before}) {
  final verbRe = RegExp('(?:$_speechVerb)');
  final verbs = verbRe.allMatches(text).toList();
  if (verbs.isNotEmpty) {
    final v = before ? verbs.last : verbs.first;
    final lo = before ? (v.start - 24).clamp(0, text.length) : v.end;
    final hi = before ? v.start : (v.end + 24).clamp(0, text.length);
    final win = text.substring(lo, hi);
    String? best;
    var bestD = 1 << 30;
    for (final n in pool) {
      var p = before ? win.lastIndexOf(n) : win.indexOf(n);
      if (p < 0) continue;
      final d = before ? win.length - (p + n.length) : p;
      if (d < bestD) { bestD = d; best = n; }
    }
    if (best != null) return best;
  }
  // 无言语动词：按分句取第一个含人名的分句，再取该分句第一个名字
  final clauses = text.split(RegExp(r'[，。！？；：…]'));
  for (final c in clauses.reversed) {
    String? first;
    var pos = 1 << 30;
    for (final n in pool) {
      final p = c.indexOf(n);
      if (p >= 0 && p < pos) { pos = p; first = n; }
    }
    if (first != null) return first;
  }
  return null;
}

void propagateSpeakers(BookIR ir) {
  // 清理历史导入留下的假人名（一个/瞬间/李火旺把…），再重新归因
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      final sp = s.speaker;
      if (sp != null && sp.isNotEmpty && !nameOk(sp)) {
        s.speaker = null;
        s.how = null;
      }
    }
  }
  // 1) 全书人名池：出现 >=2 次且通过人名校验
  final counts = <String, int>{};
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type != 'narration') continue;
      for (final m in _nameVerbRe.allMatches(s.text)) {
        final n = m.group(1)!;
        if (nameOk(n)) counts[n] = (counts[n] ?? 0) + 1;
      }
      final sp = s.speaker;
      if (sp != null && nameOk(sp)) counts[sp] = (counts[sp] ?? 0) + 3;
    }
  }
  final pool = counts.entries.where((e) => e.value >= 2).map((e) => e.key).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (pool.isEmpty) return;

  for (final c in ir.chapters) {
    final segs = c.segments;
    // 按段落分组（para 相同视为同一段）
    final paras = <int, List<int>>{};
    for (var i = 0; i < segs.length; i++) {
      paras.putIfAbsent(segs[i].para, () => []).add(i);
    }
    for (final idxs in paras.values) {
      for (final i in idxs) {
        final s = segs[i];
        if (s.type != 'dialogue' || (s.speaker != null && s.speaker!.isNotEmpty)) {
          continue;
        }
        String? hint;
        // 优先：同段内紧邻的旁白（前 → 后），按句法取主语
        for (final j in [i - 1, i + 1]) {
          if (j < 0 || j >= segs.length) continue;
          final p = segs[j];
          if (p.type != 'narration' || p.para != s.para) continue;
          hint = _pickNameFromNarration(p.text, pool, before: j < i);
          if (hint != null) break;
        }
        if (hint == null) {
          // 段内无名：就近继承（同章 ±4 段）
          for (var d = 1; d <= 4 && hint == null; d++) {
            for (final j in [i - d, i + d]) {
              if (j < 0 || j >= segs.length) continue;
              final p = segs[j];
              if (p.speaker != null && p.speaker!.isNotEmpty && nameOk(p.speaker!)) {
                hint = p.speaker;
                break;
              }
            }
          }
        }
        if (hint != null) {
          s.speaker = hint;
          s.how = 'propagated';
        }
      }
    }
  }
}

// ---------------------------------------------------------------- 性别启发

const femaleNameChars =
    '娜淼花娟燕芳梅琳雪婷慧颖静丽红霞玲萍芸瑶蕊蕾薇翠兰凤娥妍姝媛滢筠蓉茵莉莎妮婕妤嫣飒琴灵素莲绮';
const femaleNameTitles = [
  '姑娘', '小姐', '夫人', '娘娘', '婆婆', '师妹', '师姐', '少女', '公主', '娘子',
  '婶', '姨', '嫂', '妈妈', '母亲', '奶奶', '外婆', '姥姥', '姐姐', '妹妹',
  '女侠', '女士', '媳妇', '女儿', '孙女', '丫鬟', '宫女', '老妪', '师太', '尼姑',
  '太后', '皇后', '贵妃', '嬷嬷', '姑姑', '婢女', '娘'
];
const maleNameTitles = [
  '师兄', '师弟', '师傅', '老爷', '大爷', '叔', '伯', '皇子', '王爷', '太监',
  '和尚', '道士', '老头', '爸爸', '父亲', '爷爷', '外公', '哥哥', '弟弟',
  '大人', '先生', '公子', '阁下', '前辈', '掌柜', '捕头', '将军'
];

String guessGenderName(String? name) {
  if (name == null || name.isEmpty) return 'male';
  for (final t in femaleNameTitles) {
    if (name.contains(t)) return 'female';
  }
  for (final t in maleNameTitles) {
    if (name.contains(t)) return 'male';
  }
  final hits = name.split('').where((c) => femaleNameChars.contains(c)).length;
  if (hits >= 1 &&
      (femaleNameChars.contains(name[name.length - 1]) || hits * 2 >= name.length)) {
    return 'female';
  }
  return 'male';
}
