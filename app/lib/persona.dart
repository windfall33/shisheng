// 拾声 · 角色画像：从旁白提取年龄/气质线索，用于「年龄+性别+人物类型」配音。
// 只对归因到的主要角色生效；线索不足时返回低分，调用方回退到性别音色。
import 'textfront.dart';


const _ageCues = <String, List<String>>{
  'old': ['老者', '老人', '老头', '老妪', '苍老', '皱纹', '古稀', '花甲',
    '年迈', '老态', '迟暮', '老丈', '老人家', '老道', '老太'],
  'child': ['孩童', '孩子', '小孩', '幼童', '稚嫩', '娃娃', '幼儿', '童子', '小童'],
  'youth': ['少年', '少女', '青年', '年轻', '小伙', '姑娘', '少年郎', '后生'],
  'mid': ['中年', '汉子', '妇人', '壮年'],
};

const _typeCues = <String, List<String>>{
  'rough': ['粗犷', '魁梧', '大汉', '壮汉', '粗声', '沙哑', '豪迈', '粗鲁',
    '五大三粗', '魁伟', '雄壮'],
  'frail': ['文弱', '清瘦', '斯文', '秀气', '瘦弱', '书生', '单薄', '柔弱', '文质彬彬'],
  'sinister': ['阴狠', '阴冷', '阴森', '冷笑', '狠毒', '阴鸷', '阴沉', '毒辣', '邪异'],
  'gentle': ['温柔', '轻声', '柔和', '温润', '和善', '温和'],
  'stern': ['威严', '沉声', '厉声', '冷峻', '不怒自威', '威压'],
};

/// 从全书提取主要角色画像。证据 = 该角色说话所在段落的旁白文本。
Map<String, Persona> extractPersonas(BookIR ir) {
  // 先统计有对白的角色（按句数取前 60，控制扫描成本）
  final counts = <String, int>{};
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type == 'dialogue' && s.speaker != null && s.speaker!.isNotEmpty) {
        counts[s.speaker!] = (counts[s.speaker!] ?? 0) + 1;
      }
    }
  }
  final names = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final speakers = names.take(60).map((e) => e.key).toList();
  if (speakers.isEmpty) return {};

  // 证据：旁白中角色名出现处的前后 24 字窗口（避免整段旁白误伤）
  final evidence = <String, StringBuffer>{};
  for (final c in ir.chapters) {
    for (final s in c.segments) {
      if (s.type != 'narration') continue;
      // 按分句切，取名字附近 ±12 字；避免同段其他角色的描写污染
      final clauses = s.text.split(RegExp(r'[，。！？；：…]'));
      for (final clause in clauses) {
        for (final name in speakers) {
          final p = clause.indexOf(name);
          if (p < 0) continue;
          final lo = (p - 12).clamp(0, clause.length);
          final hi = (p + name.length + 12).clamp(0, clause.length);
          evidence.putIfAbsent(name, () => StringBuffer())
              .write(clause.substring(lo, hi));
          evidence[name]!.write(' ');
        }
      }
    }
  }

  final out = <String, Persona>{};
  for (final name in speakers) {
    final text = evidence[name]?.toString() ?? '';
    var gender = guessGenderName(name);
    // 旁白里明确的性别称谓优先（少女/少年/妇人/汉子…）
    // 只用最强证据：代词"她/他叫X"、"X是女人/男人/少女/少年"
    final femaleCue = RegExp('她叫$name|'
        '$name(?:是|乃)(?:一个|一位|一名)?(?:女人|女子|少女|姑娘|妇人)');
    final maleCue = RegExp('他叫$name|'
        '$name(?:是|乃)(?:一个|一位|一名)?(?:男人|男子|少年|汉子)');
    if (femaleCue.hasMatch(text)) gender = 'female';
    if (maleCue.hasMatch(text)) gender = 'male';
    final p = Persona(name, gender);
    int bestAge = 0, bestType = 0;
    // 年龄：只认"老者X / X是少年 / X这个老头"这类紧邻定语，宁缺毋滥
    for (final e in _ageCues.entries) {
      var score = 0;
      for (final w in e.value) {
        score += RegExp('(?:$w(?:的)?$name)').allMatches(text).length;
        score += RegExp('$name(?:是|乃|身为|作为|这个|那个|一个|一位|一名|，|,)?'
            '(?:一位|一个|一名)?$w').allMatches(text).length;
      }
      if (score >= 1 && score > bestAge) { bestAge = score; p.age = e.key; }
    }
    // 气质：只认"阴冷的X / X声音阴沉"这类紧邻搭配
    for (final e in _typeCues.entries) {
      var score = 0;
      for (final w in e.value) {
        score += RegExp('(?:$w(?:的)?$name)').allMatches(text).length;
        score += RegExp('$name(?:的)?(?:声音|语气|神情|脸色|眼中|脸上)?'
            '(?:很|十分|有些|显得|透着)?$w').allMatches(text).length;
      }
      if (score >= 1 && score > bestType) { bestType = score; p.type = e.key; }
    }
    p.score = bestAge + bestType;
    out[name] = p;
  }

  return out;
}


