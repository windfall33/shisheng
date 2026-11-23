// 拾声 · CAST CLUB 应用壳：阵容 / 剧本 / 试镜 + 常驻迷你播放器。
import 'dart:async';

import 'package:flutter/material.dart';

import 'club_screens.dart';
import 'design.dart';
import 'globals.dart' show audioPlayer;
import 'models.dart';
import 'playback.dart';
import 'player.dart';
import 'store.dart';
import 'ui_kit.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateMiniPlayer());
  }

  Future<void> _hydrateMiniPlayer() async {
    if (NowPlaying.instance.active) return;
    final last = lastPlayed();
    if (last == null) return;
    final bid = last['bid'] as String?;
    if (bid == null) return;
    final ir = await Data.loadBook(bid);
    if (ir == null) return;
    final item = await loadBookItem(bid, ir);
    final seq = (last['seq'] as num?)?.toInt() ?? 0;
    final pos = (last['pos'] as num?)?.toInt() ?? 0;
    NowPlaying.instance.setBook(item, seq, ir.chapter(seq)?.title ?? '');
    NowPlaying.instance.setPosition(Duration(milliseconds: pos));
    final idx = await Data.readIndex(bid, seq);
    final total = (idx?['total_ms'] as num?)?.toInt() ?? 0;
    if (total > 0) {
      NowPlaying.instance.setDuration(Duration(milliseconds: total));
    }
  }

  void _openPlayer() {
    final np = NowPlaying.instance;
    if (!np.active) return;
    Navigator.of(context).push(
      playerRoute(
        PlayerScreen(
          book: np.book!,
          startSeq: np.seq,
          startMs: np.position.inMilliseconds,
          attach: true,
        ),
      ),
    );
  }

  Widget _miniPlayer(BuildContext context) {
    final np = NowPlaying.instance;
    return AnimatedBuilder(
      animation: np,
      builder: (ctx, _) {
        if (!np.active) return const SizedBox.shrink();
        final total = np.duration.inMilliseconds;
        final progress = total > 0
            ? (np.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        return MiniPlayer(
          title: np.book!.title,
          chapter: '第 ${np.seq + 1} 章 · ${np.chapterTitle}',
          timeLabel: np.duration.inMilliseconds > 0
              ? '${fmt(np.position)} / ${fmt(np.duration)}'
              : fmt(np.position),
          progress: progress,
          playing: np.playing,
          buffering: np.buffering,
          sleeping: np.sleepAt != null || np.sleepEndOfChapter,
          onTap: _openPlayer,
          onToggle: () {
            if (np.playing) {
              unawaited(audioPlayer.pause());
            } else if (audioPlayer.audioSource != null) {
              unawaited(audioPlayer.play());
            } else {
              _openPlayer();
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final pages = <Widget>[
      const CastClubScreen(),
      ScriptBoardScreen(
        onGoCast: () => setState(() => _index = 0),
      ),
      const AuditionScreen(),
    ];
    return Scaffold(
      backgroundColor: t.bg,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _miniPlayer(context),
          AppNavBar(
            selected: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
        ],
      ),
    );
  }
}

/// 底部三段导航。公开是为了让 golden 能拼出真实底栏（迷你条 + 导航条），
/// 只截迷你条会让截图里的进度线贴在屏幕底边，和线上不一样。
class AppNavBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const AppNavBar({super.key, required this.selected, required this.onSelected});

  static const List<(IconData, String)> _items = <(IconData, String)>[
    (Icons.groups_2_outlined, '阵容'),
    (Icons.menu_book_outlined, '剧本'),
    (Icons.graphic_eq_rounded, '试镜'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.outline, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: _items[i].$1,
                      label: _items[i].$2,
                      active: i == selected,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final fg = active ? t.onAccent : t.faint;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: active ? t.lemon : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: active
                ? Border.all(color: t.outline, width: 1.8)
                : null,
            boxShadow: active
                ? <BoxShadow>[
                    BoxShadow(
                      color: t.outline,
                      offset: const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
            Icon(icon, size: 20, color: fg),
            const SizedBox(height: 3),
            Text(
              label,
              // 字号只取 token 的档位（12/15/17/21/28），不再单开一个 10.5。
              style: AppType.caption.copyWith(color: fg, letterSpacing: .4),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
