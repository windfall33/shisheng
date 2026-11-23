// 拾声 · CAST CLUB 设计系统：token、主题、字体与动效规格。
// 浅紫舞台、四色角色、粗描边硬阴影；深色主题是一种可选演出场，不是默认款。
import 'package:flutter/material.dart';

const String kFun = 'ZCOOLKuaiLe';
const String kSans = 'ShishengSans';
const List<String> kFunFallback = <String>[
  'sans-serif',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'PingFang SC',
];
const List<String> kSansFallback = <String>[
  'sans-serif',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'PingFang SC',
];

const List<FontFeature> tabularNums = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// 颜色 token：浅色“舞台”，深色“夜场”。所有界面必须走这里，禁止裸色值。
class AppTokens extends ThemeExtension<AppTokens> {
  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surfaceAlt;
  final Color text;

  /// 二级文字：正文以外的读数、说明、时间。
  final Color muted;

  /// 三级文字：编号、结构标签、内容细节这类「在场但不抢」的字。
  final Color faint;

  /// 四级文字：法律与隐私脚注。只在页脚出现，不承担任何操作，也不该被读到。
  final Color whisper;
  final Color line;

  /// 进度轨道/未填充段：和 line 分开，肉眼能看出「总长还有多少」（≥3:1）。
  final Color track;
  final Color gold;
  final Color goldBright;
  final Color goldDeep;
  final Color goldSoft;
  final Color seal;
  final Color paper;
  final Color danger;
  final Color success;

  /// 角色俱乐部四色：只负责气氛和角色分区，不替代语义色。
  final Color lilac;
  final Color coral;
  final Color lemon;
  final Color mint;

  /// 高频描边和硬阴影。浅色主题为深墨色，深色主题为浅奶白。
  final Color outline;

  /// 落在珊瑚红、柠檬黄、薄荷绿上的字色。
  final Color onAccent;
  final bool isDark;

  const AppTokens({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.muted,
    required this.faint,
    required this.whisper,
    required this.line,
    required this.track,
    required this.gold,
    required this.goldBright,
    required this.goldDeep,
    required this.goldSoft,
    required this.seal,
    required this.paper,
    required this.danger,
    required this.success,
    required this.lilac,
    required this.coral,
    required this.lemon,
    required this.mint,
    required this.outline,
    required this.onAccent,
    required this.isDark,
  });

  /// 小字/激活文字用的金色：浅色下必须比装饰金更深，才能过 4.5:1。
  Color get goldText => isDark ? goldBright : goldDeep;

  static const AppTokens dark = AppTokens(
    bg: Color(0xFF20172F),
    bg2: Color(0xFF281D3B),
    surface: Color(0xFF302346),
    surfaceAlt: Color(0xFF3B2C54),
    text: Color(0xFFFFF7F1),
    muted: Color(0xFFD8CBEB),
    faint: Color(0xFFC0B2DA),
    whisper: Color(0xFFAE9FCA),
    // 结构线原来 #343434 只有 1.59:1，暗底上等于不存在，三行书目和四章目录
    // 之间没有任何分隔。提到 #4C4C4C（2.31:1）：看得见，但不该抢内容。
    line: Color(0xFF65517F),
    track: Color(0xFF806BA0),
    gold: Color(0xFFFF7B66),
    goldBright: Color(0xFFFF9A89),
    goldDeep: Color(0xFFE35C48),
    goldSoft: Color(0x33FF7B66),
    seal: Color(0xFFFF7B66),
    paper: Color(0xFFFFF7F1),
    danger: Color(0xFFFF8A80),
    success: Color(0xFF8CEFD7),
    lilac: Color(0xFFB9A0FF),
    coral: Color(0xFFFF7B66),
    lemon: Color(0xFFFFE66D),
    mint: Color(0xFF8CEFD7),
    outline: Color(0xFFF4E7FF),
    onAccent: Color(0xFF1C132A),
    isDark: true,
  );

  static const AppTokens light = AppTokens(
    bg: Color(0xFFFBF7FF),
    bg2: Color(0xFFF3ECFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0E7FF),
    text: Color(0xFF302A3A),
    // 浅色 muted 原为 #5F5F58（6.11:1），与 faint #6A6A63（5.17:1）只差 0.9，
    // 实际渲染出来像同一级。提到 #4F4F49（7.83:1），两级才拉开。
    muted: Color(0xFF5B5268),
    faint: Color(0xFF6E647D),
    whisper: Color(0xFF7C738C),
    line: Color(0xFFD6C9EC),
    track: Color(0xFFB9A8D2),
    gold: Color(0xFFFF6752),
    goldBright: Color(0xFFFF806E),
    goldDeep: Color(0xFFC24332),
    goldSoft: Color(0x26FF6752),
    seal: Color(0xFFFF6752),
    paper: Color(0xFFFFFFFF),
    danger: Color(0xFFC83A3A),
    success: Color(0xFF2D8168),
    lilac: Color(0xFFC9B7FF),
    coral: Color(0xFFFF6752),
    lemon: Color(0xFFFFE347),
    mint: Color(0xFF78EBCE),
    outline: Color(0xFF302A3A),
    onAccent: Color(0xFF302A3A),
    isDark: false,
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? dark;

  @override
  AppTokens copyWith({
    Color? bg,
    Color? bg2,
    Color? surface,
    Color? surfaceAlt,
    Color? text,
    Color? muted,
    Color? faint,
    Color? whisper,
    Color? line,
    Color? track,
    Color? gold,
    Color? goldBright,
    Color? goldDeep,
    Color? goldSoft,
    Color? seal,
    Color? paper,
    Color? danger,
    Color? success,
    Color? lilac,
    Color? coral,
    Color? lemon,
    Color? mint,
    Color? outline,
    Color? onAccent,
    bool? isDark,
  }) => AppTokens(
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    whisper: whisper ?? this.whisper,
    line: line ?? this.line,
    track: track ?? this.track,
    gold: gold ?? this.gold,
    goldBright: goldBright ?? this.goldBright,
    goldDeep: goldDeep ?? this.goldDeep,
    goldSoft: goldSoft ?? this.goldSoft,
    seal: seal ?? this.seal,
    paper: paper ?? this.paper,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    lilac: lilac ?? this.lilac,
    coral: coral ?? this.coral,
    lemon: lemon ?? this.lemon,
    mint: mint ?? this.mint,
    outline: outline ?? this.outline,
    onAccent: onAccent ?? this.onAccent,
    isDark: isDark ?? this.isDark,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      whisper: Color.lerp(whisper, other.whisper, t)!,
      line: Color.lerp(line, other.line, t)!,
      track: Color.lerp(track, other.track, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldBright: Color.lerp(goldBright, other.goldBright, t)!,
      goldDeep: Color.lerp(goldDeep, other.goldDeep, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      seal: Color.lerp(seal, other.seal, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      lilac: Color.lerp(lilac, other.lilac, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      lemon: Color.lerp(lemon, other.lemon, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      isDark: t < .5 ? isDark : other.isDark,
    );
  }
}

/// 字体 token：两族严格分工——标题字负责角色和场景，无衬线负责正文与读数。
class AppType {
  static const TextStyle _fun = TextStyle(
    fontFamily: kFun,
    fontFamilyFallback: kFunFallback,
  );
  static const TextStyle _sans = TextStyle(
    fontFamily: kSans,
    fontFamilyFallback: kSansFallback,
  );

  /// 变量字体：显式把 wght 轴推到 600，避免只靠 fontWeight 被当成 400。
  static const List<FontVariation> bold = <FontVariation>[
    FontVariation('wght', 600),
  ];

  static TextStyle _w(TextStyle base, double wght) => base.copyWith(
        // 变量字体只给 fontVariations 在部分渲染路径下不生效，两个都给才稳。
        fontWeight: FontWeight
            .values[((wght / 100).round()).clamp(1, 9).toInt() - 1],
        fontVariations: <FontVariation>[FontVariation('wght', wght)],
      );

  /// 变量字体默认实例只有 ExtraLight / Thin，必须显式给 wght，否则整屏发虚。
  static final TextStyle display = _fun.copyWith(
    fontSize: 30,
    height: 1.18,
    letterSpacing: .2,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle title = _fun.copyWith(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle book = _fun.copyWith(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );
  static final TextStyle reading = _w(
    _sans.copyWith(fontSize: 20, height: 1.78, letterSpacing: .1),
    480,
  );
  static final TextStyle body = _w(
    _sans.copyWith(fontSize: 15, height: 1.55),
    480,
  );
  static final TextStyle bodyStrong = _w(
    _sans.copyWith(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500),
    600,
  );
  static final TextStyle meta = _w(
    _sans.copyWith(fontSize: 12, height: 1.45),
    480,
  );
  static final TextStyle caption = _w(
    _sans.copyWith(
      fontSize: 12,
      height: 1.3,
      letterSpacing: .8,
      fontWeight: FontWeight.w500,
    ),
    560,
  );
  static final TextStyle button = _w(
    _sans.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w500),
    600,
  );
  static final TextStyle time = _w(
    _sans.copyWith(fontSize: 12, height: 1.4, fontFeatures: tabularNums),
    500,
  );

  /// 读数放大档：同一族（等宽数字）的 17 档，只给"正在被调整的那个值"
  /// 用——语速弹层里的大数字。它和 [time] 是一族，不是新开一个字号。
  static final TextStyle readout = _w(
    _sans.copyWith(fontSize: 17, height: 1.4, fontFeatures: tabularNums),
    500,
  );

  /// 品牌字：只出现在启动页和启动失败页。它不是界面文字，
  /// 所以不占下面那 6 档字阶的位置——但也不该两处各写一个 42 / 44。
  static final TextStyle brand = _fun.copyWith(
    fontSize: 42,
    height: 1.1,
    letterSpacing: 4,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle hero = _fun.copyWith(
    fontSize: 40,
    height: 1.06,
    letterSpacing: .2,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle line = _fun.copyWith(
    fontSize: 23,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  static final TextStyle bubble = _w(
    _sans.copyWith(fontSize: 16, height: 1.72),
    480,
  );

  static final TextStyle label = _w(
    _sans.copyWith(
      fontSize: 11,
      height: 1.3,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
    ),
    600,
  );
}

/// 间距 token：4/8 网格。
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double huge = 40;
}

/// 圆角 token：封面 4 / 卡片 12 / 弹层 24 / 胶囊全圆。
class AppRadius {
  static const double cover = 14;
  static const double card = 18;
  static const double sheet = 28;
  static const double pill = 999;
}

/// 动效 token：只做状态反馈，不做装饰动画。
class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration hero = Duration(milliseconds: 420);
  static const Duration sleepFade = Duration(seconds: 20);
}

/// 等厚轨道。Flutter 自带的 [RoundedRectSliderTrackShape] 在画已播段时把上下各撑
/// 1px（`additionalActiveTrackHeight` 默认 2），trackHeight 3 时就变成已播 5px、
/// 未播 3px——同一条线在两段之间粗细突变。这里把它按 0 传下去。
class _EvenSliderTrackShape extends RoundedRectSliderTrackShape {
  const _EvenSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: 0,
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;
  final scheme = ColorScheme.fromSeed(seedColor: t.coral, brightness: brightness)
      .copyWith(
        primary: t.coral,
        onPrimary: t.onAccent,
        secondary: t.lilac,
        onSecondary: t.onAccent,
        surface: t.surface,
        onSurface: t.text,
        surfaceContainerLow: t.surface,
        surfaceContainer: t.surfaceAlt,
        surfaceContainerHigh: t.surfaceAlt,
        outline: t.outline,
        outlineVariant: t.line,
        error: t.danger,
        onError: t.onAccent,
      );

  final base = ThemeData(useMaterial3: true, brightness: brightness);
  final textTheme = base.textTheme
      .apply(
        fontFamily: kSans,
        fontFamilyFallback: kSansFallback,
        bodyColor: t.text,
        displayColor: t.text,
      )
      .copyWith(
        titleLarge: AppType.title.copyWith(color: t.text),
        titleMedium: AppType.book.copyWith(color: t.text),
        bodyLarge: AppType.body.copyWith(color: t.text),
        bodyMedium: AppType.body.copyWith(color: t.text),
        bodySmall: AppType.meta.copyWith(color: t.muted),
        labelLarge: AppType.button.copyWith(color: t.text),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleTextStyle: AppType.book.copyWith(color: t.text),
      iconTheme: IconThemeData(color: t.text, size: 22),
      actionsIconTheme: IconThemeData(color: t.text, size: 22),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: t.outline, width: 1.8),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1.2, space: 1.2),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: t.gold,
      inactiveTrackColor: t.track,
      thumbColor: t.gold,
      overlayColor: t.gold.withValues(alpha: .12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      trackShape: const _EvenSliderTrackShape(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.lemon,
      contentTextStyle: AppType.body.copyWith(color: t.text),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: t.outline, width: 1.8),
      ),
      insetPadding: const EdgeInsets.all(AppSpace.lg),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.goldSoft,
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(
        AppType.caption.copyWith(color: t.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? t.gold : t.muted,
          size: 22,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.outline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        side: BorderSide(color: t.outline, width: 1.8),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.outline, width: 1.8),
      ),
      titleTextStyle: AppType.book.copyWith(color: t.text),
      contentTextStyle: AppType.body.copyWith(color: t.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.coral,
        foregroundColor: t.onAccent,
        side: BorderSide(color: t.outline, width: 1.6),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
        ),
        textStyle: AppType.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.text,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        textStyle: AppType.button,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.text,
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.text,
      titleTextStyle: AppType.body.copyWith(color: t.text),
      subtitleTextStyle: AppType.meta.copyWith(color: t.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      minVerticalPadding: AppSpace.md,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.gold,
      linearTrackColor: t.track,
      circularTrackColor: t.track,
    ),
    extensions: <ThemeExtension<dynamic>>[t],
  );
}
