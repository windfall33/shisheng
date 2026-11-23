import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';
import 'textfront.dart';
import 'voices.dart';

/// 角色俱乐部的四块颜色。语义色仍由 AppTokens 管，这里只做阵容分区。
enum CastTone { narrator, mint, lemon, coral, lilac }

Color castToneColor(AppTokens t, CastTone tone) {
  return switch (tone) {
    CastTone.narrator => t.surfaceAlt,
    CastTone.mint => t.mint,
    CastTone.lemon => t.lemon,
    CastTone.coral => t.coral,
    CastTone.lilac => t.lilac,
  };
}

class CastMember {
  final String name;
  final CastTone tone;
  final int sid;
  final int lines;
  final bool narrator;

  const CastMember({
    required this.name,
    required this.tone,
    required this.sid,
    required this.lines,
    this.narrator = false,
  });

  String get initial {
    if (narrator) return '声';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first);
  }

  String get voiceCode => VoicePool.sidName(sid);

  String get roleLabel {
    if (narrator) return '旁白声轨';
    if (lines <= 0) return '等待对白';
    return '$lines 句对白';
  }
}

/// 从书稿里按真实出场次数取角色。没有对白的书只显示旁白，不硬编角色名。
List<CastMember> castForBook(
  BookIR ir, {
  BookVoices? voices,
  int limit = 4,
  bool includeNarrator = true,
}) {
  final v = voices ?? BookVoices.defaults(bookTitle: ir.title);
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  var order = 0;
  for (final chapter in ir.chapters) {
    for (final segment in chapter.segments) {
      if (segment.type == 'narration') continue;
      final raw = segment.speaker?.trim() ?? '';
      if (raw.isEmpty || raw == '旁白') continue;
      firstSeen.putIfAbsent(raw, () => order++);
      counts[raw] = (counts[raw] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  const tones = <CastTone>[
    CastTone.mint,
    CastTone.lemon,
    CastTone.coral,
    CastTone.lilac,
  ];
  final out = <CastMember>[];
  if (includeNarrator) {
    out.add(
      CastMember(
        name: '旁白',
        tone: CastTone.narrator,
        sid: v.narrator(),
        lines: 0,
        narrator: true,
      ),
    );
  }
  for (var i = 0; i < names.length && i < limit; i++) {
    final name = names[i];
    out.add(
      CastMember(
        name: name,
        tone: tones[i % tones.length],
        sid: v.resolve('dialogue', name),
        lines: counts[name]!,
      ),
    );
  }
  return out;
}

Color chapterToneColor(AppTokens t, int index) {
  return switch (index % 4) {
    0 => t.lemon,
    1 => t.surface,
    2 => t.mint,
    _ => t.lilac,
  };
}

class ClubBackdrop extends StatelessWidget {
  final Widget child;
  final Color? color;
  final bool player;

  const ClubBackdrop({
    super.key,
    required this.child,
    this.color,
    this.player = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: color ?? t.bg),
        IgnorePointer(
          child: Stack(
            children: <Widget>[
              Positioned(
                top: player ? -70 : 74,
                right: -44,
                child: _SoftShape(
                  size: player ? 210 : 138,
                  color: t.lemon.withValues(alpha: t.isDark ? .10 : .52),
                ),
              ),
              Positioned(
                top: player ? 260 : 360,
                left: -52,
                child: _SoftShape(
                  size: player ? 170 : 112,
                  color: t.lilac.withValues(alpha: t.isDark ? .12 : .44),
                ),
              ),
              Positioned(
                top: player ? 500 : 720,
                right: -34,
                child: _SoftShape(
                  size: player ? 120 : 92,
                  color: t.mint.withValues(alpha: t.isDark ? .08 : .48),
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _SoftShape extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftShape({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * .34),
      ),
    );
  }
}

class ClubCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double shadow;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ClubCard({
    super.key,
    required this.child,
    this.color,
    this.radius = AppRadius.card,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.shadow = 4,
    this.borderColor,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final r = BorderRadius.circular(radius);
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null || onLongPress != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: r,
          splashColor: t.outline.withValues(alpha: .08),
          child: body,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: r,
        border: Border.all(color: borderColor ?? t.outline, width: 2),
        boxShadow: shadow <= 0
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: t.outline,
                  offset: Offset(shadow, shadow),
                  blurRadius: 0,
                ),
              ],
      ),
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}

class ClubAvatar extends StatelessWidget {
  final CastMember? member;
  final String? label;
  final CastTone tone;
  final double size;
  final bool outlined;

  const ClubAvatar({
    super.key,
    this.member,
    this.label,
    this.tone = CastTone.mint,
    this.size = 48,
    this.outlined = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final m = member;
    final text = label ?? m?.initial ?? '?';
    final color = m == null ? castToneColor(t, tone) : castToneColor(t, m.tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: outlined ? Border.all(color: t.outline, width: 2) : null,
        boxShadow: outlined
            ? <BoxShadow>[
                BoxShadow(
                  color: t.outline,
                  offset: Offset(math.max(1, size * .045), math.max(1, size * .045)),
                  blurRadius: 0,
                ),
              ]
            : const <BoxShadow>[],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        style: AppType.title.copyWith(
          color: t.onAccent,
          fontSize: size * .4,
          height: 1,
        ),
      ),
    );
  }
}

class ClubTag extends StatelessWidget {
  final String text;
  final Color? color;
  final bool outlined;

  const ClubTag(
    this.text, {
    super.key,
    this.color,
    this.outlined = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: outlined ? Border.all(color: t.outline, width: 1.4) : null,
      ),
      child: Text(
        text,
        maxLines: 1,
        style: AppType.label.copyWith(
          color: t.onAccent,
          fontSize: 10,
          letterSpacing: .9,
        ),
      ),
    );
  }
}

class ClubSectionTitle extends StatelessWidget {
  final String kicker;
  final String title;
  final Widget? trailing;
  final Color? accent;

  const ClubSectionTitle({
    super.key,
    required this.kicker,
    required this.title,
    this.trailing,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: AppSpace.sm, bottom: 4),
          decoration: BoxDecoration(
            color: accent ?? t.lemon,
            border: Border.all(color: t.outline, width: 1.4),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                kicker,
                style: AppType.label.copyWith(color: t.muted),
              ),
              const SizedBox(height: 1),
              Text(title, style: AppType.title.copyWith(color: t.text)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class ClubButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool expand;

  const ClubButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final child = ClubCard(
      color: color ?? t.coral,
      radius: AppRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shadow: 3,
      onTap: onTap,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: t.onAccent),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.button.copyWith(color: t.onAccent),
            ),
          ),
        ],
      ),
    );
    if (!expand) return child;
    return SizedBox(width: double.infinity, child: child);
  }
}

class ClubSpeechBubble extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final bool tailLeft;
  final EdgeInsetsGeometry padding;

  const ClubSpeechBubble({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.tailLeft = true,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 26),
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return CustomPaint(
      painter: _SpeechBubblePainter(
        fill: color ?? t.surface,
        stroke: borderColor ?? t.outline,
        shadow: t.outline,
        tailLeft: tailLeft,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  final Color shadow;
  final bool tailLeft;

  _SpeechBubblePainter({
    required this.fill,
    required this.stroke,
    required this.shadow,
    required this.tailLeft,
  });

  Path _path(Size size) {
    const tail = 12.0;
    final body = Rect.fromLTWH(0, 0, size.width, math.max(0, size.height - tail));
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(AppRadius.card)),
      );
    final tailPath = Path();
    if (tailLeft) {
      tailPath
        ..moveTo(26, body.bottom - 1)
        ..lineTo(17, size.height)
        ..lineTo(50, body.bottom - 1);
    } else {
      tailPath
        ..moveTo(size.width - 42, body.bottom - 1)
        ..lineTo(size.width - 17, size.height)
        ..lineTo(size.width - 18, body.bottom - 1);
    }
    tailPath.close();
    return Path.combine(PathOperation.union, path, tailPath);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.save();
    canvas.translate(4, 4);
    canvas.drawPath(path, Paint()..color = shadow);
    canvas.restore();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.shadow != shadow ||
        oldDelegate.tailLeft != tailLeft;
  }
}

class ClubWaveform extends StatelessWidget {
  final Color? color;
  final int bars;
  final double height;

  const ClubWaveform({
    super.key,
    this.color,
    this.bars = 14,
    this.height = 24,
  });

  static const List<double> _levels = <double>[
    .28,
    .52,
    .86,
    .44,
    .70,
    .96,
    .38,
    .66,
    .84,
    .48,
    .74,
    .34,
    .58,
    .80,
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < bars; i++)
            Container(
              width: 2.4,
              height: math.max(4, height * _levels[i % _levels.length]),
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: color ?? t.onAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
