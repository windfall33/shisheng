// 拾声 v4 · 书架、最近、设置、书籍详情/章节目录。
import 'dart:async';

import 'package:flutter/material.dart';

import 'boot.dart';
import 'design.dart';
import 'globals.dart' show audioPlayer, prefs;
import 'importer.dart';
import 'models.dart';
import 'playback.dart';
import 'player.dart';
import 'render.dart';
import 'settings.dart';
import 'store.dart';
import 'textfront.dart';
import 'ui_kit.dart';
import 'version.dart';

Future<List<BookItem>> loadLibrary() async {
  final pairs = await Data.listBooks();
  final out = <BookItem>[];
  for (final (bid, ir) in pairs) {
    out.add(await loadBookItem(bid, ir));
  }
  out.sort((a, b) {
    final aHas = a.lastPosMs > 0 ? 0 : 1;
    final bHas = b.lastPosMs > 0 ? 0 : 1;
    if (aHas != bHas) return aHas - bHas;
    return a.title.compareTo(b.title);
  });
  return out;
}

class LibraryScreen extends StatefulWidget {
  final List<BookItem>? previewBooks;
  final BookItem? previewLast;
  final int previewSeq;
  final int previewPos;

  const LibraryScreen({
    super.key,
    this.previewBooks,
    this.previewLast,
    this.previewSeq = 0,
    this.previewPos = 0,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<BookItem> books = <BookItem>[];
  bool loading = true;
  bool importing = false;
  Map<String, dynamic>? last;

  @override
  void initState() {
    super.initState();
    if (widget.previewBooks != null) {
      books = widget.previewBooks!;
      last = widget.previewLast == null
          ? null
          : <String, dynamic>{
              'bid': widget.previewLast!.bid,
              'seq': widget.previewSeq,
              'pos': widget.previewPos,
            };
      loading = false;
    } else {
      last = lastPlayed();
      _load();
    }
  }

  Future<void> _load() async {
    final out = await loadLibrary();
    if (!mounted) return;
    setState(() {
      books = out;
      loading = false;
      last = lastPlayed();
    });
  }

  BookItem? get _lastBook {
    final bid = last?['bid'] as String?;
    if (bid == null) return null;
    for (final b in books) {
      if (b.bid == bid) return b;
    }
    return null;
  }

  int get _lastSeq {
    final s = (last?['seq'] as num?)?.toInt() ?? 0;
    return s > 0 ? s : (_lastBook?.lastSeq ?? 0);
  }

  int get _lastPos {
    final p = (last?['pos'] as num?)?.toInt() ?? 0;
    return p > 0 ? p : (_lastBook?.lastPosMs ?? 0);
  }

  Future<void> _import() async {
    if (importing) return;
    setState(() => importing = true);
    final status = ValueNotifier<String>('正在切章与分声，大文件稍久…');
    final nav = Navigator.of(context, rootNavigator: true);
    var sheetOpen = true;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isDismissible: true,
        enableDrag: true,
        isScrollControlled: true,
        backgroundColor: AppTokens.of(context).surface,
        builder: (_) => _ImportSheet(status: status),
      ).then((_) => sheetOpen = false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    BookItem? newBook;
    try {
      final r = await importTxt();
      if (r != null && mounted) {
        invalidateBookItem(r.$1);
        newBook = BookItem(r.$1, r.$2, 0, 0);
        status.value = '已导入《${r.$2.title}》';
        if (sheetOpen && nav.canPop()) nav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('《${r.$2.title}》：${r.$2.chapters.length} 章，已开始后台合成'),
          ),
        );
      } else {
        if (sheetOpen && nav.canPop()) nav.pop();
      }
    } catch (e) {
      status.value = '导入失败：$e';
      if (mounted) {
        if (sheetOpen && nav.canPop()) nav.pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e。换一个 TXT 再试')));
      }
    } finally {
      status.dispose();
      if (mounted) setState(() => importing = false);
      await _load();
    }
    if (newBook != null && mounted && !AppSettings.instance.firstImportDone) {
      await AppSettings.instance.markFirstImportDone();
      final idx = await Data.readIndex(newBook.bid, 0);
      if (mounted) {
        await _showFirstImportSheet(newBook, ready: idx?['done'] == true);
      }
    }
  }

  Future<void> _showFirstImportSheet(
    BookItem book, {
    required bool ready,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTokens.of(context).surface,
      builder: (_) => FirstImportSheet(book: book, ready: ready),
    );
    if (!mounted || action != 'listen') return;
    Navigator.of(context)
        .push(playerRoute(PlayerScreen(book: book, startSeq: 0, startMs: 0)));
  }

  Future<void> _confirmDelete(BookItem b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final t = AppTokens.of(c);
        return AlertDialog(
          title: Text('删除《${b.title}》？'),
          content: const Text('文本与已生成的音频都会从本机删除，无法恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(
                '取消',
                style: AppType.button.copyWith(color: t.muted),
              ),
            ),
            // 删除不可恢复：用 danger 的文字链，不用实心金按钮——
            // 实心金会让「删掉一本书」看起来像这个应用最想让人点的动作。
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                '删除',
                style: AppType.button.copyWith(color: t.danger),
              ),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await Data.deleteBook(b.bid);
    invalidateBookItem(b.bid);
    if (NowPlaying.instance.book?.bid == b.bid) {
      NowPlaying.instance.clear();
    }
    if (last?['bid'] == b.bid) {
      await prefs.remove('last');
    }
    await _load();
  }

  void _openBook(BookItem b) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ChaptersScreen(book: b)));
  }

  void _resume(BookItem b, {int? seq, int? pos}) {
    Navigator.of(context).push(
      playerRoute(
        PlayerScreen(
          book: b,
          startSeq: seq ?? _lastSeq,
          startMs: pos ?? _lastPos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final lastBook = _lastBook;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _load,
              color: t.gold,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _Masthead(count: books.length, importing: importing),
                  ),
                  if (loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.gold,
                          ),
                        ),
                      ),
                    )
                  else if (books.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _FirstRunEmptyState(
                        onImport: importing ? null : _import,
                        onHowTo: () => showHowToSheet(
                          context,
                          onImport: importing ? null : _import,
                        ),
                      ),
                    )
                  else ...<Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xxl,
                          AppSpace.lg,
                          AppSpace.xxl,
                          0,
                        ),
                        child: lastBook == null
                            ? _StartHero(onTap: importing ? null : _import)
                            : _ContinueHero(
                                book: lastBook,
                                seq: _lastSeq,
                                positionMs: _lastPos,
                                onTap: () => _resume(lastBook),
                              ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xxl,
                          AppSpace.section,
                          AppSpace.xxl,
                          AppSpace.xs,
                        ),
                        child: _Label('全部'),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.xxl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((ctx, i) {
                          final b = books[i];
                          return _BookRow(
                            book: b,
                            active: b.bid == lastBook?.bid,
                            onTap: () => _openBook(b),
                            onLongPress: () => _confirmDelete(b),
                          );
                        }, childCount: books.length),
                      ),
                    ),
                    // 导入钉在栏底：书只有三本时它压住屏幕下缘，书多时排在
                    // 列表末尾。跟着最后一行浮在半空会让整屏像没写完。
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xxl,
                          AppSpace.section,
                          AppSpace.xxl,
                          AppSpace.huge,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _Label('导入'),
                            _ImportRow(
                              onTap: importing ? null : _import,
                              busy: importing,
                            ),
                            const SizedBox(height: AppSpace.md),
                            Text(
                              '书留在本机 · 断网也能听',
                              style: AppType.caption.copyWith(color: t.whisper),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Text(
      text,
      style: AppType.caption.copyWith(color: t.faint, letterSpacing: 2),
    );
  }
}

/// 主按钮：1px 描边，不填色。整屏只有一个，别的地方都用文字链。
///
/// 不用实心块是有原因的：这块屏幕多半在夜里、在关灯的房间里被人看着，
/// 一块 300×49 的浅色实心矩形在暗屏上是个光源，不是按钮。描边一样点得到，
/// 但不刺眼——按钮靠字形和边框成立，不靠面积。
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: t.text, width: 1),
            ),
            child: Text(label, style: AppType.button.copyWith(color: t.text)),
          ),
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  final int count;
  final bool importing;
  const _Masthead({required this.count, required this.importing});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xxl,
        AppSpace.lg,
        AppSpace.xxl,
        AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          // 报头不是主角：它用 title 档，屏幕最大的那行字留给正在读的那本书。
          Text('拾声', style: AppType.title.copyWith(color: t.text)),
          const Spacer(),
          Text(
            importing ? '正在导入' : '$count 本书',
            style: AppType.caption.copyWith(color: t.faint),
          ),
        ],
      ),
    );
  }
}

/// 继续播放：1.5px 描边圆 + 实心字形。
///
/// 实心圆盘在暗屏上是一块手电筒（52px 直径约 2000 个白像素，是书名的两倍多）。
/// 描边圆一样指得清「这里能按」，但只花掉一条线的亮度。
class _PlayCircle extends StatelessWidget {
  final VoidCallback? onTap;
  const _PlayCircle({this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      button: true,
      label: '继续播放',
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.text, width: 1.5),
          ),
          child: Icon(Icons.play_arrow_rounded, size: 23, color: t.text),
        ),
      ),
    );
  }
}

class _ContinueHero extends StatelessWidget {
  final BookItem book;
  final int seq;
  final int positionMs;
  final VoidCallback? onTap;
  const _ContinueHero({
    required this.book,
    required this.seq,
    required this.positionMs,
    this.onTap,
  });

  double get _progress {
    final total = book.renderedMs;
    if (total <= 0 || book.chapterCount <= 0) return 0;
    final avg = total / book.chapterCount;
    return ((seq * avg + positionMs) / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final chapter =
        seq >= 0 && seq < book.ir.chapters.length ? book.ir.chapters[seq].title : '';
    final head = chapter.isEmpty
        ? '第 ${seq + 1} 章'
        : (chapter.startsWith('第') ? chapter : '第 ${seq + 1} 章 · $chapter');
    final line =
        '$head · 听到 ${fmt(Duration(milliseconds: positionMs))}';
    return InkWell(
      onTap: onTap,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Label('继续'),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.display.copyWith(color: t.text, height: 1.22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta.copyWith(color: t.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            _PlayCircle(onTap: onTap),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        // 进度条带读数，才不会被当成一条分隔线。
        Row(
          children: <Widget>[
            Expanded(
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 3,
                backgroundColor: t.track,
                valueColor: AlwaysStoppedAnimation<Color>(t.gold),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Text(
              '${(_progress * 100).round()}%',
              style: AppType.time.copyWith(color: t.faint),
            ),
          ],
        ),
      ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final BookItem book;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _BookRow({
    required this.book,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  String get _meta {
    final total = book.renderedMs;
    if (book.lastPosMs > 0 && total > 0 && book.chapterCount > 0) {
      final avg = total / book.chapterCount;
      final p = ((book.lastSeq * avg + book.lastPosMs) / total).clamp(0.0, 1.0);
      return '${(p * 100).round()}% · ${book.chapterCount} 章';
    }
    return '${book.chapterCount} 章 · 未开始';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: t.line, width: .5),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.book.copyWith(
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Text(_meta, style: AppType.meta.copyWith(color: t.faint)),
          ],
        ),
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  const _ImportRow({this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line, width: .5)),
        ),
        child: Row(
          children: <Widget>[
            Text(
              busy ? '正在导入…' : '选择 TXT 文件',
              style: AppType.body.copyWith(color: t.text),
            ),
            const Spacer(),
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: t.muted,
                ),
              )
            else
              Icon(Icons.add_rounded, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class _StartHero extends StatelessWidget {
  final VoidCallback? onTap;

  const _StartHero({this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Label('开始'),
        const SizedBox(height: AppSpace.sm),
        Text(
          '从一本 TXT 开始',
          style: AppType.title.copyWith(color: t.text),
        ),
        const SizedBox(height: 6),
        Text(
          '不注册，不要会员。断网也能听。',
          style: AppType.body.copyWith(color: t.muted, height: 1.6),
        ),
        const SizedBox(height: AppSpace.lg),
        _PrimaryButton(label: '导入 TXT', onTap: onTap),
      ],
    );
  }
}

class _ImportSheet extends StatelessWidget {
  final ValueNotifier<String> status;

  const _ImportSheet({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.lg,
          AppSpace.xxl,
          AppSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.gold),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              '正在导入',
              style: AppType.title.copyWith(color: t.text),
            ),
            const SizedBox(height: AppSpace.sm),
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (ctx, value, _) => Text(
                value,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.muted, height: 1.6),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '切章、分声会占用几秒钟。下滑可先回书架，导入会在后台继续。',
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(color: t.faint),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showHowToSheet(
  BuildContext context, {
  VoidCallback? onImport,
}) async {
  final t = AppTokens.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: t.surface,
    builder: (ctx) {
      final tt = AppTokens.of(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xxl,
            AppSpace.sm,
            AppSpace.xxl,
            AppSpace.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '听书只要三步',
                style: AppType.title.copyWith(color: tt.text),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                '导入、合成、播放都在手机里完成；不需要账号，断网也能听。',
                style: AppType.body.copyWith(color: tt.muted, height: 1.7),
              ),
              const SizedBox(height: AppSpace.xl),
              const _HowToSteps(),
              const SizedBox(height: AppSpace.xl),
              const _QuickTips(),
              const SizedBox(height: AppSpace.xl),
              _PrimaryButton(
                label: onImport == null ? '知道了' : '导入一本 TXT',
                onTap: () {
                  Navigator.pop(ctx);
                  onImport?.call();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FirstRunEmptyState extends StatelessWidget {
  final VoidCallback? onImport;
  final VoidCallback onHowTo;

  const _FirstRunEmptyState({required this.onImport, required this.onHowTo});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.huge,
          AppSpace.xxl,
          AppSpace.huge,
        ),
        // 外层铺满页面栏线（24 → 366），里面再收阅读宽度：
        // 按钮和 onboarding 的主按钮同宽，别让两块主按钮一宽一窄。
        child: Column(
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                children: <Widget>[
                  Text(
                    '书架空空',
                    textAlign: TextAlign.center,
                    style: AppType.display.copyWith(color: t.text),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    '导入一本 TXT，切章、分声、合成，都在手机里完成。不需要账号，断网也能听。',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: t.muted, height: 1.75),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xxl),
            _PrimaryButton(label: '导入 TXT', onTap: onImport),
            const SizedBox(height: AppSpace.sm),
            // 一行字要看起来能点：给下划线。和按钮同灰、无标记时它不像链接。
            TextButton(
              onPressed: onHowTo,
              child: Text(
                '怎么听？',
                style: AppType.meta.copyWith(
                  color: t.muted,
                  decoration: TextDecoration.underline,
                  decorationColor: t.faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTips extends StatelessWidget {
  const _QuickTips();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _QuickTip(
          icon: Icons.touch_app_rounded,
          title: '点书名开始听',
          note: '进入章节目录，选一章',
        ),
        SizedBox(height: AppSpace.md),
        _QuickTip(
          icon: Icons.speed_rounded,
          title: '底部调语速和定时',
          note: '睡眠定时最后 20 秒渐弱',
        ),
        SizedBox(height: AppSpace.md),
        _QuickTip(
          icon: Icons.offline_bolt_rounded,
          title: '本机合成，熄屏可听',
          note: '断网也能听，不需要账号',
        ),
      ],
    );
  }
}

class _QuickTip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;

  const _QuickTip({
    required this.icon,
    required this.title,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: t.goldText),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppType.bodyStrong.copyWith(color: t.text),
              ),
              const SizedBox(height: 1),
              Text(note, style: AppType.caption.copyWith(color: t.faint)),
            ],
          ),
        ),
      ],
    );
  }
}

class FirstImportSheet extends StatelessWidget {
  final BookItem book;
  final bool ready;

  const FirstImportSheet({super.key, required this.book, required this.ready});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    // 只留一句：弹层不是说明书，说明和按钮只差一级字号时，三条会糊成一片。
    // 留下的是「本机合成 + 断网可听」——这是它和别的听书应用唯一的不同。
    final tip = ready
        ? '本机合成，断网也能听，不需要账号'
        : '第 1 章在后台合成，通常十几秒 · 不需要账号';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.md,
          AppSpace.xxl,
          AppSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '已放入书架',
              style: AppType.caption.copyWith(
                color: t.faint,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.title.copyWith(color: t.text),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              tip,
              style: AppType.body.copyWith(color: t.muted, height: 1.5),
            ),
            const SizedBox(height: AppSpace.lg),
            InkWell(
              onTap: () => Navigator.pop(context, ready ? 'listen' : 'shelf'),
              borderRadius: BorderRadius.circular(8),
              // 和全站主按钮同一个描边：弹层里也不该单独出现一块实心白。
              child: Container(
                height: 48,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: t.text, width: 1),
                ),
                child: Text(
                  ready ? '现在听第一章' : '去书架',
                  style: AppType.button.copyWith(color: t.text),
                ),
              ),
            ),
            if (ready)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, 'shelf'),
                  child: Text(
                    '先去书架',
                    style: AppType.meta.copyWith(color: t.faint),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 最近

class RecentScreen extends StatefulWidget {
  final List<BookItem>? previewBooks;

  const RecentScreen({super.key, this.previewBooks});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<BookItem> books = <BookItem>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final preview = widget.previewBooks;
    if (preview != null) {
      books = preview.where((b) => b.lastPosMs > 0).toList();
      loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final out = await loadLibrary();
    if (!mounted) return;
    setState(() {
      books = out.where((b) => b.lastPosMs > 0).toList();
      loading = false;
    });
  }

  void _open(BookItem b) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ChaptersScreen(book: b)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Material(
        color: t.bg,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xxl,
                      AppSpace.lg,
                      AppSpace.xxl,
                      AppSpace.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '最近',
                          style: AppType.display.copyWith(color: t.text),
                        ),
                        const Spacer(),
                        Text(
                          '${books.length} 本在听',
                          style: AppType.caption.copyWith(color: t.faint),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.text,
                              ),
                            ),
                          )
                        : books.isEmpty
                        ? const EmptyState(
                            title: '还没有收听记录',
                            body: '从书架挑一本，听几分钟后这里会出现续听入口。',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: t.text,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpace.xxl,
                                AppSpace.md,
                                AppSpace.xxl,
                                AppSpace.section,
                              ),
                              children: <Widget>[
                                _ContinueHero(
                                  book: books.first,
                                  seq: books.first.lastSeq,
                                  positionMs: books.first.lastPosMs,
                                  onTap: () => _open(books.first),
                                ),
                                if (books.length > 1) ...<Widget>[
                                  SectionHeader(
                                    '收听记录',
                                    note: '${books.length - 1} 本',
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      AppSpace.section,
                                      0,
                                      AppSpace.sm,
                                    ),
                                  ),
                                  for (
                                    var i = 1;
                                    i < books.length;
                                    i++
                                  ) ...<Widget>[
                                    _RecentRow(
                                      book: books[i],
                                      onTap: () => _open(books[i]),
                                      onResume: () {
                                        final b = books[i];
                                        Navigator.of(context).push(
                                          playerRoute(
                                            PlayerScreen(
                                              book: b,
                                              startSeq: b.lastSeq,
                                              startMs: b.lastPosMs,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    if (i < books.length - 1)
                                      Divider(color: t.line, height: 1),
                                  ],
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final BookItem book;
  final VoidCallback onTap;
  final VoidCallback onResume;

  const _RecentRow({
    required this.book,
    required this.onTap,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.book.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第 ${book.lastSeq + 1} 章，听到 ${fmt(Duration(milliseconds: book.lastPosMs))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.faint),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onResume,
              tooltip: '继续听',
              icon: Icon(Icons.play_arrow_rounded, color: t.text, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 设置

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: Material(
        color: t.bg,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpace.section),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xxl,
                      AppSpace.md,
                      AppSpace.xxl,
                      AppSpace.sm,
                    ),
                    child: Text(
                      '设置',
                      style: AppType.display.copyWith(color: t.text),
                    ),
                  ),
                  const _SettingSection(
                    title: '外观',
                    children: <Widget>[_ThemeModeSetting()],
                  ),
                  _SettingSection(
                    title: '播放',
                    children: <Widget>[
                      _ChoiceSetting<int>(
                        title: '快进 / 快退',
                        note: '播放器两侧按钮的秒数',
                        values: const <int>[10, 15, 30, 45, 60],
                        label: (v) => '$v 秒',
                        notifier: AppSettings.instance.skipSeconds,
                        onChanged: AppSettings.instance.setSkipSeconds,
                      ),
                      _ChoiceSetting<double>(
                        title: '默认语速',
                        note: '新书第一次播放时使用',
                        values: const <double>[0.75, 1.0, 1.25, 1.5, 2.0],
                        label: (v) => '${v}x',
                        notifier: AppSettings.instance.defaultSpeed,
                        onChanged: AppSettings.instance.setDefaultSpeed,
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AppSettings.instance.autoRewind,
                        builder: (ctx, value, _) => SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.xxl,
                          ),
                          title: Text(
                            '暂停后自动回退',
                            style: AppType.body.copyWith(color: t.text),
                          ),
                          subtitle: Text(
                            '离开一会儿再回来，从刚才那句继续',
                            style: AppType.caption.copyWith(color: t.faint),
                          ),
                          value: value,
                          // 打开的开关用品牌橙，不用一块实心白：夜里那是一条
                          // 44×22 的小光条，比正文还亮。
                          activeTrackColor: t.gold,
                          activeThumbColor: t.bg,
                          inactiveTrackColor: Colors.transparent,
                          inactiveThumbColor: t.faint,
                          trackOutlineColor: WidgetStatePropertyAll<Color>(
                            t.line,
                          ),
                          onChanged: (v) =>
                              AppSettings.instance.setAutoRewind(v),
                        ),
                      ),
                    ],
                  ),
                  _SettingSection(
                    title: '音色',
                    children: <Widget>[
                      _ChoiceSetting<bool>(
                        title: '音色来源',
                        note: '仅本机：全部在手机里合成，不联网。自动：联网时用云端音色，断网自动换回本机。',
                        values: <bool>[true, false],
                        label: _voiceSourceLabel,
                        notifier: AppSettings.instance.cloudAllowed,
                        onChanged: AppSettings.instance.setCloudAllowed,
                      ),
                    ],
                  ),
                  _SettingSection(
                    title: '睡眠',
                    children: <Widget>[
                      _ChoiceSetting<int>(
                        title: '默认定时',
                        note: '打开播放器时预选的分钟数',
                        values: const <int>[15, 30, 45, 60],
                        label: (v) => '$v 分钟',
                        notifier: AppSettings.instance.sleepDefault,
                        onChanged: AppSettings.instance.setSleepDefault,
                      ),
                    ],
                  ),
                  _SettingSection(
                    title: '关于',
                    trailing: '拾声 v$kAppVersion',
                    children: <Widget>[
                      ListTile(
                        minVerticalPadding: AppSpace.sm,
                        leading: Icon(
                          Icons.help_outline_rounded,
                          color: t.muted,
                        ),
                        title: Text(
                          '怎么听',
                          style: AppType.body.copyWith(color: t.text),
                        ),
                        subtitle: Text(
                          '导入、合成、播放的三步',
                          style: AppType.caption.copyWith(color: t.faint),
                        ),
                        onTap: () => showHowToSheet(context),
                      ),
                      // 隐私声明不是设置项，没有可点的动作，不值得占一条 ListTile。
                      // 它和版本号一起落在页脚：脚注就写在页面最底下。
                      ValueListenableBuilder<bool>(
                        valueListenable: AppSettings.instance.cloudAllowed,
                        builder: (ctx, allowCloud, _) => Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpace.xxl,
                            AppSpace.sm,
                            AppSpace.xxl,
                            0,
                          ),
                          // 页脚说的是事实，不是承诺：选了「仅本机」就别再提云端。
                          child: Text(
                            allowCloud
                                ? '书和进度留在本机。联网用云端音色，断网用本机音色。'
                                : '书、进度和音频都留在本机，合成不联网。',
                            style: AppType.caption.copyWith(
                              color: t.faint,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  final String title;
  final String? trailing;
  final List<Widget> children;

  const _SettingSection({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xxl,
            AppSpace.lg,
            AppSpace.xxl,
            AppSpace.sm,
          ),
          child: Row(
            children: <Widget>[
              Text(
                title,
                style: AppType.caption.copyWith(
                  color: t.faint,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppType.caption.copyWith(color: t.whisper),
                ),
            ],
          ),
        ),
        ...children,
        Padding(
          padding: const EdgeInsets.only(left: AppSpace.xxl, right: AppSpace.xxl),
          child: Divider(color: t.line, height: AppSpace.lg),
        ),
      ],
    );
  }
}

class _ThemeModeSetting extends StatelessWidget {
  const _ThemeModeSetting();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (ctx, mode, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('主题', style: AppType.body.copyWith(color: t.text)),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final entry in <(ThemeMode, String)>[
                  (ThemeMode.system, '跟随系统'),
                  (ThemeMode.light, '浅色'),
                  (ThemeMode.dark, '深色'),
                ])
                  AppPill(
                    entry.$2,
                    selected: mode == entry.$1,
                    onTap: () => AppSettings.instance.setThemeMode(entry.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _voiceSourceLabel(bool auto) => auto ? '自动' : '仅本机';

class _ChoiceSetting<T> extends StatelessWidget {
  final String title;
  final String note;
  final List<T> values;
  final String Function(T) label;
  final ValueNotifier<T> notifier;
  final Future<void> Function(T) onChanged;

  const _ChoiceSetting({
    required this.title,
    required this.note,
    required this.values,
    required this.label,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xxl,
        AppSpace.sm,
        AppSpace.xxl,
        AppSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: AppType.body.copyWith(color: t.text)),
          const SizedBox(height: 2),
          Text(note, style: AppType.caption.copyWith(color: t.faint)),
          const SizedBox(height: AppSpace.sm),
          ValueListenableBuilder<T>(
            valueListenable: notifier,
            builder: (ctx, current, _) => Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final v in values)
                  AppPill(
                    label(v),
                    selected: v == current,
                    onTap: () => onChanged(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 书籍详情 / 章节目录

class ChaptersScreen extends StatefulWidget {
  final BookItem book;
  final int? activeSeq;
  final bool preview;
  final Map<int, Map<String, dynamic>>? previewStates;

  const ChaptersScreen({
    super.key,
    required this.book,
    this.activeSeq,
    this.preview = false,
    this.previewStates,
  });

  @override
  State<ChaptersScreen> createState() => _ChaptersScreenState();
}

class _ChaptersScreenState extends State<ChaptersScreen> {
  final Map<int, Map<String, dynamic>> _state = <int, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    if (widget.preview) {
      _state.addAll(widget.previewStates ?? <int, Map<String, dynamic>>{});
    } else {
      _loadStates();
    }
  }

  Future<void> _loadStates() async {
    for (final c in widget.book.ir.chapters) {
      final idx = await Data.readIndex(widget.book.bid, c.seq);
      if (idx != null) _state[c.seq] = idx;
    }
    if (mounted) setState(() {});
  }

  void _play(int seq, {int ms = 0}) {
    Navigator.of(context).push(
      playerRoute(PlayerScreen(book: widget.book, startSeq: seq, startMs: ms)),
    );
  }

  Future<void> _prioritize(int seq) async {
    await Renderer.ensure(() => Boot.tts);
    await Renderer.instance.touch(widget.book.bid, seq, Renderer.priUser);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已插队，稍等几秒就会开始')));
  }

  /// 一章有多长：合成完的读 index 里的真实时长，合成中的读预估，
  /// 一点没动的按字数估（4.3 字/秒，和合成引擎用的是同一个常数）。
  /// 目录上给出时长，人才知道点下去要花多久。
  static int _durationMs(Chapter c, Map<String, dynamic>? idx) {
    final total = (idx?['total_ms'] as num?)?.toInt() ?? 0;
    if (total > 0) return total;
    final est = (idx?['est_ms'] as num?)?.toInt() ?? 0;
    if (est > 0) return est;
    var sec = 0.0;
    for (final seg in c.segments) {
      sec += estSec(seg);
    }
    return (sec * 1000).round();
  }

  Widget _chapterRowFor(int i) {
    final chapters = widget.book.ir.chapters;
    final c = chapters[i];
    final idx = _state[c.seq];
    final fresh = idx?['pipe'] == audioPipelineVersion;
    final done = idx?['done'] == true && fresh;
    final rendering = idx != null && !done && fresh;
    final active = (widget.activeSeq ?? -1) == c.seq;
    return _ChapterRow(
      chapter: c,
      index: i,
      active: active,
      done: done,
      rendering: rendering,
      blocks: (idx?['blocks'] as List?)?.length ?? 0,
      plan: idx?['plan_blocks'] as int?,
      durationMs: _durationMs(c, idx),
      onTap: () => _play(c.seq),
      onPrioritize: () => _prioritize(c.seq),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final b = widget.book;
    final last = lastPlayed();
    final lastSeq = (last?['seq'] as num?)?.toInt() ?? b.lastSeq;
    final lastPos = (last?['pos'] as num?)?.toInt() ?? b.lastPosMs;
    final chapters = b.ir.chapters;
    final lastTitle = lastSeq >= 0 && lastSeq < chapters.length
        ? chapters[lastSeq].title
        : '第 ${lastSeq + 1} 章';

    // 目录从顶上排，不居中。居中会让「聊斋志异」在三章的书里停在 y233、
    // 在八章的书里停在 y97——同一个书名在同一个页面里不该有两个高度。
    // 三章的书下面空着，那是因为它真的只有三章，不是排版没写完。
    // 超过 40 章改回 SliverList，按需构建。
    final backBar = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.xxl, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            tooltip: '返回',
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: t.text),
          ),
        ],
      ),
    );

    final head = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.sm,
          AppSpace.xxl,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(b.title, style: AppType.display.copyWith(color: t.text)),
            const SizedBox(height: AppSpace.sm),
            Text(
              '${b.chapterCount} 章 · ${fmtListenTime(b.hanChars)} · ${b.generatedLabel}',
              style: AppType.meta.copyWith(color: t.faint),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.xl,
          AppSpace.xxl,
          0,
        ),
        child: _ResumeRow(
          chapter: lastTitle,
          time: fmt(Duration(milliseconds: lastPos)),
          onTap: () => _play(lastSeq, ms: lastPos),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xxl,
          AppSpace.xl,
          AppSpace.xxl,
          AppSpace.xs,
        ),
        child: Row(
          children: <Widget>[
            _Label('目录'),
            const Spacer(),
            // 计数是标签的一部分，不是另一个读数：同档字号、同一灰。
            Text(
              '${chapters.length} 章',
              style: AppType.caption.copyWith(color: t.faint, letterSpacing: 2),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                backBar,
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, box) {
                      if (chapters.length > 40) {
                        return CustomScrollView(
                          slivers: <Widget>[
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: head,
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.xxl,
                              ),
                              sliver: SliverList.builder(
                                itemCount: chapters.length,
                                itemBuilder: (c, i) => _chapterRowFor(i),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: AppSpace.huge),
                            ),
                          ],
                        );
                      }
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ...head,
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.xxl,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  for (var i = 0; i < chapters.length; i++)
                                    _chapterRowFor(i),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpace.huge),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _NowPlayingBar(),
    );
  }
}

class _ResumeRow extends StatelessWidget {
  final String chapter;
  final String time;
  final VoidCallback onTap;

  const _ResumeRow({
    required this.chapter,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line, width: .5)),
        ),
        child: Row(
          children: <Widget>[
            // 和书架上「继续」同一个形状：同一个动作不该有两种长相。
            _PlayCircle(onTap: onTap),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    chapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.book.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '继续收听',
                    style: AppType.caption.copyWith(color: t.faint),
                  ),
                ],
              ),
            ),
            Text(
              time,
              style: AppType.time.copyWith(color: t.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  /// 右列固定宽度：够放下「优先合成」四个字，也让每一行的右边缘对齐到同一条线。
  static const double _rightCol = 56;

  final dynamic chapter;
  final int index;
  final bool active;
  final bool done;
  final bool rendering;
  final int blocks;
  final int? plan;
  final int durationMs;
  final VoidCallback onTap;
  final VoidCallback onPrioritize;

  const _ChapterRow({
    required this.chapter,
    required this.index,
    required this.active,
    required this.done,
    required this.rendering,
    required this.blocks,
    required this.plan,
    required this.durationMs,
    required this.onTap,
    required this.onPrioritize,
  });

  static String _len(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    if (h > 0) return '$h 小时 $m 分';
    if (m > 0) return '$m 分 $sec 秒';
    return '$sec 秒';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final no = chapter.no as int?;
    final raw = (chapter.title as String?)?.trim() ?? '';
    // 行首已经单独给了章号，标题里重复的「第 N 章」就剥掉，别让一行出现两次章号。
    var title = raw.isEmpty ? '第 ${index + 1} 章' : raw;
    if (raw.isNotEmpty) {
      final stripped = raw.replaceFirst(
        RegExp(r'^第\s*[0-9０-９一二三四五六七八九十百千零两]+\s*[章回节]\s*[·、:：\-—]?\s*'),
        '',
      );
      if (stripped.isNotEmpty) title = stripped;
    }
    final pct = (rendering && (plan ?? 0) > 0)
        ? (blocks / plan! * 100).clamp(0, 100).round()
        : null;
    // 一行里只留两种信息：这章是什么（标题）、这章有多长加现在什么状态（副行）。
    // 「正在播」「合成到几成」都进副行，右列只放能按的动作，两种语义不再挤一格。
    final status = active
        ? '正在播放'
        : rendering
            ? (pct == null ? '合成中' : '合成中 $pct%')
            : null;
    final meta = status == null ? _len(durationMs) : '${_len(durationMs)} · $status';
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        decoration: BoxDecoration(
          border: Border(
            // 正在播的那一章用整行高的橙轨标记：三行章名同色同号时，
            // 一段 22px 的短条浮在行中间不构成「这一行」，整行高才读得出是行标记。
            // 未播的行用同宽的透明轨，保证所有行的内容起点完全对齐。
            left: BorderSide(
              color: active ? t.gold : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: t.line, width: .5),
          ),
        ),
        child: Row(
          children: <Widget>[
            // 12 - 3（上面那根轨）＝ 9，章号仍然落在同一条竖线上。
            const SizedBox(width: 9),
            SizedBox(
              width: 26,
              child: Text(
                (no ?? index + 1).toString().padLeft(3, '0'),
                style: AppType.caption.copyWith(
                  // 章号不跟着变橙：一屏只留一处橙（左侧竖条），
                  // 否则「正在播」这件事在同一行里说了两遍。
                  color: t.faint,
                  letterSpacing: .4,
                  fontFeatures: tabularNums,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 章名一视同仁：状态由副行说，标题不需要跟着变灰。
                    style: AppType.book.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta.copyWith(
                      color: active ? t.muted : t.faint,
                      fontFeatures: tabularNums,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            // 右列只放动作。状态已经写在副行里，这里再放一遍就是同一件事说两次。
            SizedBox(
              width: _rightCol,
              child: Align(
                alignment: Alignment.centerRight,
                child: active || rendering || done
                    ? null
                    // 未合成：给一个说得清的动作，别只放一个箭头让人猜。
                    // 用 muted 不用 text：这一页的主角是「正在播放」的那一章，
                    // 别的行的动作不该比它亮。muted 在暗底上仍有 7.19:1，读得清。
                    : InkResponse(
                        onTap: onPrioritize,
                        radius: 24,
                        child: Text(
                          '优先合成',
                          style: AppType.caption.copyWith(
                            color: t.muted,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final np = NowPlaying.instance;
    return AnimatedBuilder(
      animation: np,
      builder: (ctx, _) {
        if (!np.active) return const SizedBox.shrink();
        final total = np.duration.inMilliseconds;
        final progress = total > 0
            ? (np.position.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        return SafeArea(
          top: false,
          child: MiniPlayer(
            title: np.book!.title,
            chapter: '第 ${np.seq + 1} 章 · ${np.chapterTitle}',
            timeLabel: total > 0
                ? '${fmt(np.position)} / ${fmt(np.duration)}'
                : fmt(np.position),
            progress: progress,
            playing: np.playing,
            buffering: np.buffering,
            sleeping: np.sleepAt != null || np.sleepEndOfChapter,
            onTap: () {
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
            },
            onToggle: () {
              if (np.playing) {
                unawaited(audioPlayer.pause());
              } else if (audioPlayer.audioSource != null) {
                unawaited(audioPlayer.play());
              }
            },
          ),
        );
      },
    );
  }
}

class _HowToSteps extends StatelessWidget {
  const _HowToSteps();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: <Widget>[
        const _HowToStep(icon: Icons.file_open_outlined, title: '导入', note: '选一本小说'),
        _StepLine(t: t),
        const _HowToStep(icon: Icons.graphic_eq_rounded, title: '合成', note: '手机里完成'),
        _StepLine(t: t),
        const _HowToStep(icon: Icons.headphones_rounded, title: '收听', note: '熄屏可听'),
      ],
    );
  }
}

class _HowToStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;

  const _HowToStep({
    required this.icon,
    required this.title,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 20, color: t.muted),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final AppTokens t;

  const _StepLine({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: .5,
      margin: const EdgeInsets.only(bottom: 22),
      color: t.line,
    );
  }
}
