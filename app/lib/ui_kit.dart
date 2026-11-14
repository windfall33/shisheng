// 拾声 v5 · 界面组件：分区标题、进度线、胶囊、音浪、空态、迷你播放器。
// 规则：不用阴影、不用渐变；进度用 1–2px 实色；金色只标“正在播”。

import 'package:flutter/material.dart';

import 'design.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? note;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.note,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.xxl,
      AppSpace.section,
      AppSpace.xxl,
      AppSpace.xs,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            title,
            style: AppType.caption.copyWith(color: t.faint, letterSpacing: 2),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(width: AppSpace.sm),
            Text(note!, style: AppType.caption.copyWith(color: t.faint)),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 细进度线。默认金色——它只出现在“正在播”的对象上。
class ProgressLine extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Color? background;

  const ProgressLine({
    super.key,
    required this.value,
    this.height = 2,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final v = value.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 槽用 track 不用 line：line 只是分隔线，槽得让人看出总长还剩多少。
          ColoredBox(color: background ?? t.track),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              // heightFactor 必须给 1：ColoredBox 没有子节点时高度会塌成 0，
              // 这条进度就只剩槽、看不见已经播了多少（曾经的 bug）。
              heightFactor: 1,
              child: ColoredBox(color: color ?? t.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class AppPill extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const AppPill(
    this.text, {
    super.key,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final fg = selected ? t.text : t.muted;
    final visual = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected ? t.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // 未选中的框用 track 不用 line：line 是分隔线（2.3:1），
        // 而这里要让人看出「这是一排可点的选项」，得够 3:1。
        border: Border.all(
          color: selected ? t.text : t.track,
          width: .8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(text, style: AppType.meta.copyWith(color: fg)),
        ],
      ),
    );
    final child = SizedBox(
      height: 44,
      child: Center(widthFactor: 1, child: visual),
    );
    if (onTap == null) return child;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: child,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String body;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.section,
          vertical: AppSpace.huge,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppType.display.copyWith(color: t.text),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.muted, height: 1.7),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: AppSpace.xxl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你播放器：只负责显示，具体播放动作由外层传入。
class MiniPlayer extends StatelessWidget {
  /// 触摸目标与图标：44 是能点准的下限，图标 26 在 44 里看起来才不憋。
  static const double _tap = 44;
  static const double _icon = 26;

  final String title;
  final String chapter;
  final String? timeLabel;
  final double progress;
  final bool playing;
  final bool buffering;
  final bool sleeping;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const MiniPlayer({
    super.key,
    required this.title,
    required this.chapter,
    required this.progress,
    required this.playing,
    required this.buffering,
    required this.sleeping,
    required this.onTap,
    required this.onToggle,
    this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: '打开播放器，$title，$chapter',
      child: Material(
        color: t.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line, width: .5)),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpace.xxl),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // 和书库、目录里的书名同一档：同一类东西（一行书名）
                                // 在任何地方都该一样大。
                                style: AppType.book.copyWith(color: t.text),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      chapter,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.meta.copyWith(
                                        color: t.faint,
                                      ),
                                    ),
                                  ),
                                  if (timeLabel != null) ...<Widget>[
                                    Text(
                                      ' · ',
                                      style: AppType.meta.copyWith(
                                        color: t.faint,
                                      ),
                                    ),
                                    Text(
                                      timeLabel!,
                                      style: AppType.time.copyWith(
                                        color: t.faint,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (sleeping)
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpace.sm),
                            child: Icon(
                              Icons.nightlight_round,
                              size: 15,
                              color: t.faint,
                            ),
                          ),
                        // 图标的右缘落在页面 24 栏上：横条左右两端收在同一条栅格里，
                        // 才不会看起来是自己往外飘的。
                        Padding(
                          padding: EdgeInsets.only(
                            right: AppSpace.xxl - (_tap - _icon) / 2,
                          ),
                          child: SizedBox(
                            width: _tap,
                            height: _tap,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: onToggle,
                              tooltip: playing ? '暂停' : '继续播放',
                              icon: buffering && !playing
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: t.text,
                                      ),
                                    )
                                  : Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: _icon,
                                      color: t.text,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 进度只剩这一条：它已经说明播到哪，左边不需要再来一根橙条。
                ProgressLine(value: progress, height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
