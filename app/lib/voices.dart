// 拾声 v4 · 音色池与分声（Kokoro v1.1-zh 版）。
// 100 个中文说话人：zf_003..zf_099（sid 3-57，女 55）+ zm_009..zm_100（sid 58-102，男 45）。
// 分声三级：旁白/对白（引号，必达）→ 角色映射 → 性别启发 + 姓名哈希自动分声。
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'textfront.dart';
import 'voice_profiles.dart';

class VoicePool {
  static const engineId = 'kokoro-v1.1-zh';
  static const engineModelId = 'kokoro-int8-multi-lang-v1_1';

  // 默认音色（sid）。后续可由试听页/每本书配置覆盖。
  static const defaultNarrator = 102; // zm_100
  static const defaultDialogueM = 70; // zm_031
  static const defaultDialogueF = 30; // zf_047

  static const femaleSids = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54,
    55, 56, 57];
  static const maleSids = [58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
    71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
    90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102];

  // 试听页展示用的精选音色（好听候选，用户可点选）
  static const featured = <int, String>{
    102: 'zm_100', 100: 'zm_097', 90: 'zm_069', 70: 'zm_031', 58: 'zm_009',
    3: 'zf_001', 10: 'zf_008', 30: 'zf_047', 45: 'zf_078', 57: 'zf_099',
  };

  static String sidName(int sid) {
    if (sid <= 2) return sid == 0 ? 'af_maple' : (sid == 1 ? 'af_sol' : 'bf_vale');
    if (sid <= 57) return 'zf_${_zfName(sid)}';
    return 'zm_${_zmName(sid)}';
  }

  // zf/zm 编号映射（来自 sherpa-onnx 官方 sid→name 表）
  static const _zfNames = {3: '001', 4: '002', 5: '003', 6: '004', 7: '005',
    8: '006', 9: '007', 10: '008', 11: '017', 12: '018', 13: '019', 14: '021',
    15: '022', 16: '023', 17: '024', 18: '026', 19: '027', 20: '028', 21: '032',
    22: '036', 23: '038', 24: '039', 25: '040', 26: '042', 27: '043', 28: '044',
    29: '046', 30: '047', 31: '048', 32: '049', 33: '051', 34: '059', 35: '060',
    36: '067', 37: '070', 38: '071', 39: '072', 40: '073', 41: '074', 42: '075',
    43: '076', 44: '077', 45: '078', 46: '079', 47: '083', 48: '084', 49: '085',
    50: '086', 51: '087', 52: '088', 53: '090', 54: '092', 55: '093', 56: '094',
    57: '099'};
  static const _zmNames = {58: '009', 59: '010', 60: '011', 61: '012', 62: '013',
    63: '014', 64: '015', 65: '016', 66: '020', 67: '025', 68: '029', 69: '030',
    70: '031', 71: '033', 72: '034', 73: '035', 74: '037', 75: '041', 76: '045',
    77: '050', 78: '052', 79: '053', 80: '054', 81: '055', 82: '056', 83: '057',
    84: '058', 85: '061', 86: '062', 87: '063', 88: '064', 89: '065', 90: '066',
    91: '068', 92: '069', 93: '080', 94: '081', 95: '082', 96: '089', 97: '091',
    98: '095', 99: '096', 100: '097', 101: '098', 102: '100'};
  static String _zfName(int sid) => _zfNames[sid] ?? '$sid';
  static String _zmName(int sid) => _zmNames[sid] ?? '$sid';

  static int? sidFromName(String name) {
    if (name.startsWith('zf_')) {
      for (final e in _zfNames.entries) {
        if (e.value == name.substring(3)) return e.key;
      }
    }
    if (name.startsWith('zm_')) {
      for (final e in _zmNames.entries) {
        if (e.value == name.substring(3)) return e.key;
      }
    }
    return null;
  }

  static bool isFemale(int sid) => femaleSids.contains(sid);
}

// ---------------------------------------------------------------- 性别启发

const femaleChars =
    '娜淼花娟燕芳梅琳雪婷慧颖静丽红霞玲萍芸瑶蕊蕾薇翠兰凤娥妍姝媛滢筠蓉茵莉莎妮婕妤嫣飒琴灵素莲绮';
const femaleTitles = [
  '姑娘', '小姐', '夫人', '娘娘', '婆婆', '师妹', '师姐', '少女', '公主', '娘子',
  '婶', '姨', '嫂', '妈妈', '母亲', '奶奶', '外婆', '姥姥', '姐姐', '妹妹',
  '女侠', '女士', '媳妇', '女儿', '孙女', '丫鬟', '宫女', '老妪', '师太', '尼姑',
  '太后', '皇后', '贵妃', '嬷嬷', '姑姑', '婢女', '娘'
];
const maleTitles = [
  '师兄', '师弟', '师傅', '老爷', '大爷', '叔', '伯', '皇子', '王爷', '太监',
  '和尚', '道士', '老头', '爸爸', '父亲', '爷爷', '外公', '哥哥', '弟弟',
  '大人', '先生', '公子', '阁下', '前辈', '掌柜', '捕头', '将军'
];

String guessGender(String? name) => guessGenderName(name);

// ---------------------------------------------------------------- 每本书音色配置

class BookVoices {
  final Map<String, dynamic> cfg; // {defaults:{narrator,dialogue_m,dialogue_f}, characters:{name:sid}, auto_distinct}
  BookVoices(this.cfg);

  int narrator() =>
      (cfg['defaults']?['narrator'] as num?)?.toInt() ?? VoicePool.defaultNarrator;
  int dialogueM() =>
      (cfg['defaults']?['dialogue_m'] as num?)?.toInt() ?? VoicePool.defaultDialogueM;
  int dialogueF() =>
      (cfg['defaults']?['dialogue_f'] as num?)?.toInt() ?? VoicePool.defaultDialogueF;

  int _distinct(String gender, String name) {
    final pool = gender == 'female' ? VoicePool.femaleSids : VoicePool.maleSids;
    final candidates = pool
        .where((s) => s != VoicePool.defaultNarrator &&
            s != (gender == 'female' ? VoicePool.defaultDialogueF : VoicePool.defaultDialogueM))
        .toList()
      ..sort();
    if (candidates.isEmpty) {
      return gender == 'female' ? VoicePool.defaultDialogueF : VoicePool.defaultDialogueM;
    }
    final h = sha1.convert(utf8.encode(name)).bytes;
    final v = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
    return candidates[v.abs() % candidates.length];
  }

  int resolve(String segType, String? speaker, {Persona? persona}) {
    if (segType == 'narration') return narrator();
    if (speaker != null && speaker.isNotEmpty) {
      final mapped = cfg['characters']?[speaker];
      if (mapped is num) return mapped.toInt();
      // 年龄+气质匹配（仅主要角色、线索足够时）
      if (persona != null) {
        final pid = matchPersonaVoice(persona);
        if (pid != null) return pid;
      }
      if (cfg['auto_distinct'] != false) {
        return _distinct(guessGender(speaker), speaker);
      }
    }
    return guessGender(speaker) == 'female' ? dialogueF() : dialogueM();
  }

  Map<String, dynamic> toJson() => cfg;

  static BookVoices defaults({String bookTitle = ''}) => BookVoices({
        'defaults': {
          'narrator': VoicePool.defaultNarrator,
          'dialogue_m': VoicePool.defaultDialogueM,
          'dialogue_f': VoicePool.defaultDialogueF,
        },
        'characters': <String, dynamic>{},
        'auto_distinct': true,
        'version': 1,
      });
}

// 段 → 音色 sid 的便捷封装（供渲染层/时间轴显示）
int resolveSid(BookVoices v, Segment s) => v.resolve(s.type, s.speaker);

/// 按「年龄 + 性别 + 人物类型」在音色档案里找最接近的一个。
/// 归一化只用同性别候选，避免男女基频尺度差异干扰。
int? matchPersonaVoice(Persona p) {
  if (p.score < 1 || (p.age == null && p.type == null)) return null;
  final pool = voiceProfiles.where((v) =>
      v.gender == p.gender &&
      v.sid != VoicePool.defaultNarrator &&
      v.sid != VoicePool.defaultDialogueM &&
      v.sid != VoicePool.defaultDialogueF).toList();
  if (pool.isEmpty) return null;
  var fMin = double.infinity, fMax = -double.infinity;
  var cMin = double.infinity, cMax = -double.infinity;
  for (final v in pool) {
    if (v.f0 < fMin) fMin = v.f0;
    if (v.f0 > fMax) fMax = v.f0;
    if (v.centroid < cMin) cMin = v.centroid;
    if (v.centroid > cMax) cMax = v.centroid;
  }
  final fSpan = (fMax - fMin) < 1e-6 ? 1.0 : (fMax - fMin);
  final cSpan = (cMax - cMin) < 1e-6 ? 1.0 : (cMax - cMin);

  var tf = 0.5, tc = 0.5;
  switch (p.age) {
    case 'old': tf = 0.08; break;
    case 'child': tf = 0.95; break;
    case 'youth': tf = 0.70; break;
    case 'young': tf = 0.55; break;
    case 'mid': tf = 0.42; break;
  }
  switch (p.type) {
    case 'rough': tc = 0.75; tf -= 0.05; break;
    case 'frail': tc = 0.30; tf += 0.03; break;
    case 'sinister': tc = 0.20; tf -= 0.04; break;
    case 'gentle': tc = 0.45; tf += 0.02; break;
    case 'stern': tc = 0.55; tf -= 0.06; break;
  }
  int? best;
  var bestD = double.infinity;
  for (final v in pool) {
    final fn = (v.f0 - fMin) / fSpan;
    final cn = (v.centroid - cMin) / cSpan;
    final d = (fn - tf) * (fn - tf) * 2 + (cn - tc) * (cn - tc);
    if (d < bestD) {
      bestD = d;
      best = v.sid;
    }
  }
  return best;
}
