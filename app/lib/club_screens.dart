import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'boot.dart';
import 'cleanup.dart';
import 'club_ui.dart';
import 'design.dart';
import 'globals.dart' show audioPlayer, prefs;
import 'importer.dart';
import 'library_revision.dart';
import 'models.dart';
import 'playback.dart';
import 'player.dart';
import 'render.dart';
import 'settings.dart';
import 'store.dart';
import 'textfront.dart';
import 'ui_kit.dart';
import 'version.dart';
import 'voicestudio.dart';
import 'voices.dart';

Future<List<BookItem>> _loadAllBooks() async {
  final pairs = await Data.listBooks();
  final out = <BookItem>[];
  for (final (bid, ir) in pairs) {
    out.add(await loadBookItem(bid, ir));
  }
  out.sort((a, b) {
    final aPlayed = a.lastPosMs > 0 ? 0 : 1;
    final bPlayed = b.lastPosMs > 0 ? 0 : 1;
    if (aPlayed != bPlayed) return aPlayed - bPlayed;
    return a.title.compareTo(b.title);
  });
  return out;
}

String _cleanChapterTitle(String raw, int seq) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '第 ${seq + 1} 幕';
  final stripped = trimmed.replaceFirst(
    RegExp(
      r'^第\s*[0-9０-９一二三四五六七八九十百千零两]+\s*[章回节幕]\s*[·：:\-—]?\s*',
    ),
    '',
  );
  return stripped.isEmpty ? trimmed : stripped;
}

class CastClubScreen extends StatefulWidget {
  final List<BookItem>? previewBooks;
  final BookItem? previewLast;
  final int previewSeq;
  final int previewPos;

  const CastClubScreen({
    super.key,
    this.previewBooks,
    this.previewLast,
    this.previewSeq = 0,
    this.previewPos = 0,
  });

  @override
  State<CastClubScreen> createState() => _CastClubScreenState();
}

class _CastClubScreenState extends State<CastClubScreen> {
  List<BookItem> books = <BookItem>[];
  bool loading = true;
  bool importing = false;
  Map<String, dynamic>? _last;
  Map<int, Map<String, dynamic>> _states = <int, Map<String, dynamic>>{};
  BookVoices? _voices;
  String? _npBid;
  int? _npSeq;

  @override
  void initState() {
    super.initState();
    if (widget.previewBooks != null) {
      books = widget.previewBooks!;
      _last = widget.previewLast == null
          ? null
          : <String, dynamic>{
              'bid': widget.previewLast!.bid,
              'seq': widget.previewSeq,
              'pos': widget.previewPos,
            };
      loading = false;
      _primePreviewStates();
      return;
    }
    _last = lastPlayed();
    _npBid = _last?['bid'] as String?;
    _npSeq = (_last?['seq'] as num?)?.toInt();
    NowPlaying.instance.addListener(_onNowPlaying);
    unawaited(_load());
  }

  void _primePreviewStates() {
    final book = _lastBook;
    if (book == null || book.chapterCount == 0) return;
    final start = _lastSeq.clamp(0, book.chapterCount - 1);
    for (var seq = start; seq < math.min(start + 3, book.chapterCount); seq++) {
      _states[seq] = <String, dynamic>{
        'pipe': audioPipelineVersion,
        'done': seq == start,
        'blocks': <dynamic>[],
        'total_ms': 0,
        'est_ms': (seq + 1) * 74000,
      };
    }
  }

  @override
  void dispose() {
    if (widget.previewBooks == null) {
      NowPlaying.instance.removeListener(_onNowPlaying);
    }
    super.dispose();
  }

  void _onNowPlaying() {
    final np = NowPlaying.instance;
    final bid = np.book?.bid;
    if (bid == null) return;
    if (bid == _npBid && np.seq == _npSeq) return;
    _npBid = bid;
    _npSeq = np.seq;
    if (!mounted) return;
    setState(() {
      _last = <String, dynamic>{
        'bid': bid,
        'seq': np.seq,
        'pos': np.position.inMilliseconds,
      };
    });
    unawaited(_loadStates());
  }

  Future<void> _load() async {
    final out = await _loadAllBooks();
    var voices = _voices;
    final bid = _last?['bid'] as String?;
    if (bid != null) voices = await Data.loadVoices(bid);
    if (!mounted) return;
    setState(() {
      books = out;
      loading = false;
      _last = lastPlayed();
      _voices = voices;
    });
    await _loadStates();
  }

  Future<void> _loadStates() async {
    final book = _lastBook;
    if (book == null || book.chapterCount == 0) return;
    final start = _lastSeq.clamp(0, book.chapterCount - 1);
    final end = math.min(start + 3, book.chapterCount);
    final next = <int, Map<String, dynamic>>{};
    for (var seq = start; seq < end; seq++) {
      final idx = await Data.readIndex(book.bid, seq);
      if (idx != null) next[seq] = idx;
    }
    if (mounted) setState(() => _states = next);
  }

  BookItem? get _lastBook {
    final bid = _last?['bid'] as String?;
    if (bid == null) return null;
    for (final book in books) {
      if (book.bid == bid) return book;
    }
    return null;
  }

  int get _lastSeq {
    final raw = _last?['seq'];
    if (raw is num) return raw.toInt();
    return _lastBook?.lastSeq ?? 0;
  }

  int get _lastPos {
    final raw = _last?['pos'];
    if (raw is num) return raw.toInt();
    return _lastBook?.lastPosMs ?? 0;
  }

  Future<void> _import() async {
    if (importing) return;
    setState(() => importing = true);
    final status = ValueNotifier<String>('正在拆章、分角色，这一步只在本机做。');
    final nav = Navigator.of(context, rootNavigator: true);
    var sheetOpen = true;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTokens.of(context).surface,
        builder: (_) => _ImportProgressSheet(status: status),
      ).then((_) => sheetOpen = false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    BookItem? fresh;
    try {
      final result = await importTxt();
      if (result != null && mounted) {
        invalidateBookItem(result.$1);
        fresh = BookItem(result.$1, result.$2, 0, 0);
        status.value = '《${result.$2.title}》已进场，后台开始合成第一幕。';
        bumpLibraryRevision();
        if (sheetOpen && nav.canPop()) nav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已收入剧本架：${result.$2.title}'),
          ),
        );
      } else if (sheetOpen && nav.canPop()) {
        nav.pop();
      }
    } catch (error) {
      status.value = '导入失败：$error';
      if (mounted) {
        if (sheetOpen && nav.canPop()) nav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$error')),
        );
      }
    } finally {
      status.dispose();
      if (mounted) setState(() => importing = false);
      await _load();
    }
    if (fresh != null && mounted && !AppSettings.instance.firstImportDone) {
      await AppSettings.instance.markFirstImportDone();
      final idx = await Data.readIndex(fresh.bid, 0);
      if (mounted) {
        final action = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: AppTokens.of(context).surface,
          builder: (_) => _OpeningNightSheet(
            book: fresh!,
            ready: idx?['done'] == true,
          ),
        );
        if (action == 'listen' && mounted) {
          _resume(fresh, seq: 0, pos: 0);
        }
      }
    }
  }

  Future<void> _confirmDelete(BookItem book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = AppTokens.of(ctx);
        return AlertDialog(
          title: Text('撤下《${book.title}》？'),
          content: const Text('书稿、角色和已合成的音频都会从本机删除，无法恢复。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('留着', style: AppType.button.copyWith(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除', style: AppType.button.copyWith(color: t.danger)),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await Data.deleteBook(book.bid);
    invalidateBookItem(book.bid);
    if (NowPlaying.instance.book?.bid == book.bid) {
      NowPlaying.instance.clear();
    }
    if (_last?['bid'] == book.bid) await prefs.remove('last');
    bumpLibraryRevision();
    await _load();
  }

  void _openBook(BookItem book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScriptScreen(book: book)),
    );
  }

  void _resume(BookItem book, {int? seq, int? pos}) {
    Navigator.of(context).push(
      playerRoute(
        PlayerScreen(
          book: book,
          startSeq: seq ?? _lastSeq,
          startMs: pos ?? _lastPos,
        ),
      ),
    );
  }

  void _showHowTo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.of(context).surface,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppTokens.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const ClubTag('OPENING NIGHT', color: Color(0xFFFFE347)),
                const SizedBox(height: 14),
                Text('三步开演', style: AppType.title.copyWith(color: t.text)),
                const SizedBox(height: 8),
                Text(
                  '导入一本 TXT，自动分章、分角色；本机合成声音；'
                  '然后按角色阵容开场。断网也能听。',
                  style: AppType.body.copyWith(color: t.muted, height: 1.7),
                ),
                const SizedBox(height: 20),
                ClubButton(
                  label: importing ? '正在导入' : '导入 TXT',
                  icon: Icons.upload_file_rounded,
                  color: t.lemon,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!importing) unawaited(_import());
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final book = _lastBook;
    final cast = book == null
        ? const <CastMember>[]
        : castForBook(book.ir, voices: _voices);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ClubBackdrop(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RefreshIndicator(
                onRefresh: _load,
                color: t.coral,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: _ClubMasthead(
                        count: books.length,
                        importing: importing,
                        onHowTo: _showHowTo,
                      ),
                    ),
                    if (loading)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: t.coral,
                          ),
                        ),
                      )
                    else if (books.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyClub(
                          onImport: importing ? null : _import,
                          onHowTo: _showHowTo,
                        ),
                      )
                    else ...<Widget>[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: <Widget>[
                                  ClubTag(
                                    'CASTING NOW',
                                    color: t.coral,
                                  ),
                                  Text(
                                    '先认识角色，再开始听。',
                                    style: AppType.meta.copyWith(
                                      color: t.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '今晚的阵容',
                                style: AppType.hero.copyWith(color: t.text),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '不是挑一本书。是挑一组声音。',
                                style: AppType.body.copyWith(
                                  color: t.muted,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (book == null)
                                _StartCard(
                                  onImport: importing ? null : _import,
                                )
                              else
                                _BookHero(
                                  book: book,
                                  seq: _lastSeq,
                                  positionMs: _lastPos,
                                  onResume: () => _resume(book),
                                  onScript: () => _openBook(book),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (book != null) ...<Widget>[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                            child: ClubSectionTitle(
                              kicker: 'CAST / 角色',
                              title: '这一场的角色',
                              accent: t.mint,
                              trailing: ClubTag('${cast.length} 位'),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 174,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                              itemCount: cast.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (ctx, i) => _CastCard(
                                member: cast[i],
                                book: book,
                                onTap: () => _openBook(book),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                            child: ClubSectionTitle(
                              kicker: 'SCRIPT / 剧本',
                              title: '接下来上场',
                              accent: t.lemon,
                              trailing: Text(
                                '${_lastSeq + 1} / ${book.chapterCount}',
                                style: AppType.meta.copyWith(color: t.faint),
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                            child: _NextTickets(
                              book: book,
                              fromSeq: _lastSeq,
                              states: _states,
                              onTap: (seq) => _resume(
                                book,
                                seq: seq,
                                pos: seq == _lastSeq ? null : 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                          child: ClubSectionTitle(
                            kicker: 'SHELF / 全部',
                            title: '剧本架',
                            accent: t.lilac,
                            trailing: Text(
                              '${books.length} 本',
                              style: AppType.meta.copyWith(color: t.faint),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        sliver: SliverList.separated(
                          itemCount: books.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final item = books[i];
                            return _ShelfCard(
                              book: item,
                              index: i,
                              active: item.bid == book?.bid,
                              onTap: () => _openBook(item),
                              onLongPress: () => _confirmDelete(item),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 44),
                          child: _ImportCard(
                            busy: importing,
                            onTap: importing ? null : _import,
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
      ),
    );
  }
}

class _ClubMasthead extends StatelessWidget {
  final int count;
  final bool importing;
  final VoidCallback onHowTo;

  const _ClubMasthead({
    required this.count,
    required this.importing,
    required this.onHowTo,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.lemon,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.outline, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: t.outline,
                  offset: const Offset(2.5, 2.5),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Text(
              '拾',
              style: AppType.title.copyWith(color: t.onAccent, fontSize: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '拾声',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.title.copyWith(color: t.text),
                ),
                Text(
                  'CAST CLUB / 本机',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: t.faint, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkResponse(
            onTap: onHowTo,
            radius: 24,
            child: Icon(
              Icons.help_outline_rounded,
              size: 21,
              color: t.muted,
            ),
          ),
          const SizedBox(width: 12),
          ClubTag(
            importing ? '正在拆本' : '$count 本剧本',
            color: t.surface,
          ),
        ],
      ),
    );
  }
}

class _BookHero extends StatelessWidget {
  final BookItem book;
  final int seq;
  final int positionMs;
  final VoidCallback onResume;
  final VoidCallback onScript;

  const _BookHero({
    required this.book,
    required this.seq,
    required this.positionMs,
    required this.onResume,
    required this.onScript,
  });

  double get _progress {
    final total = book.renderedMs;
    if (total <= 0 || book.chapterCount <= 0) return 0;
    final average = total / book.chapterCount;
    return ((seq * average + positionMs) / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final chapter = seq >= 0 && seq < book.ir.chapters.length
        ? _cleanChapterTitle(book.ir.chapters[seq].title, seq)
        : '第 ${seq + 1} 幕';
    return ClubCard(
      color: t.coral,
      shadow: 6,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClubTag('正在上演', color: t.lemon),
              const Spacer(),
              ClubTag(
                '第 ${seq + 1} 幕',
                color: t.surface,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(
              color: t.onAccent,
              fontSize: 25,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$chapter · ${fmt(Duration(milliseconds: positionMs))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(
              color: t.onAccent.withValues(alpha: .82),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: t.onAccent.withValues(alpha: .14),
              valueColor: AlwaysStoppedAnimation<Color>(t.lemon),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _Metric(
                icon: Icons.menu_book_rounded,
                value: '${book.chapterCount} 幕',
              ),
              const SizedBox(width: 12),
              _Metric(
                icon: Icons.schedule_rounded,
                value: fmtListenTime(book.hanChars),
              ),
              const Spacer(),
              Text(
                '已存 ${(book.renderedRatio * 100).round()}%',
                style: AppType.meta.copyWith(color: t.onAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: ClubButton(
                  label: '继续 ${fmt(Duration(milliseconds: positionMs))}',
                  icon: Icons.play_arrow_rounded,
                  color: t.lemon,
                  expand: true,
                  onTap: onResume,
                ),
              ),
              const SizedBox(width: 10),
              ClubCard(
                color: t.surface,
                radius: AppRadius.pill,
                shadow: 3,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                onTap: onScript,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.auto_stories_rounded, size: 18, color: t.text),
                    const SizedBox(width: 6),
                    Text(
                      '剧本',
                      style: AppType.button.copyWith(color: t.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _Metric({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: t.onAccent),
        const SizedBox(width: 4),
        Text(value, style: AppType.meta.copyWith(color: t.onAccent)),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  final CastMember member;
  final BookItem book;
  final VoidCallback onTap;

  const _CastCard({
    required this.member,
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SizedBox(
      width: 112,
      child: ClubCard(
        color: member.narrator ? t.surfaceAlt : t.surface,
        padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
        shadow: 3,
        onTap: onTap,
        child: Column(
          children: <Widget>[
            ClubAvatar(member: member, size: 48),
            const SizedBox(height: 7),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.book.copyWith(color: t.text),
            ),
            const SizedBox(height: 1),
            Text(
              member.roleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                color: t.faint,
                letterSpacing: .2,
              ),
            ),
            const Spacer(),
            ClubWaveform(
              bars: 9,
              height: 14,
              color: castToneColor(t, member.tone),
            ),
            const SizedBox(height: 5),
            Text(
              member.voiceCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(
                color: t.faint,
                fontSize: 9,
                letterSpacing: .3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextTickets extends StatelessWidget {
  final BookItem book;
  final int fromSeq;
  final Map<int, Map<String, dynamic>> states;
  final ValueChanged<int> onTap;

  const _NextTickets({
    required this.book,
    required this.fromSeq,
    required this.states,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chapters = book.ir.chapters;
    if (chapters.isEmpty) return const SizedBox.shrink();
    final start = fromSeq.clamp(0, chapters.length - 1);
    final end = math.min(start + 3, chapters.length);
    return Column(
      children: <Widget>[
        for (var seq = start; seq < end; seq++)
          Padding(
            padding: EdgeInsets.only(bottom: seq + 1 < end ? 10 : 0),
            child: _NextTicket(
              chapter: chapters[seq],
              seq: seq,
              index: seq - start,
              active: seq == fromSeq,
              idx: states[seq],
              onTap: () => onTap(seq),
            ),
          ),
      ],
    );
  }
}

class _NextTicket extends StatelessWidget {
  final Chapter chapter;
  final int seq;
  final int index;
  final bool active;
  final Map<String, dynamic>? idx;
  final VoidCallback onTap;

  const _NextTicket({
    required this.chapter,
    required this.seq,
    required this.index,
    required this.active,
    required this.idx,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final fresh = idx?['pipe'] == audioPipelineVersion;
    final done = idx?['done'] == true && fresh;
    final rendering = idx != null && fresh && !done;
    final status = active
        ? '正在听'
        : done
        ? '已合成'
        : rendering
        ? '合成中'
        : '待合成';
    final color = active
        ? t.coral
        : chapterToneColor(t, index + 1);
    return ClubCard(
      color: color,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? t.surface : t.surface.withValues(alpha: .76),
              shape: BoxShape.circle,
              border: Border.all(color: t.outline, width: 1.6),
            ),
            child: Text(
              '${seq + 1}'.padLeft(2, '0'),
              style: AppType.book.copyWith(
                color: t.text,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _cleanChapterTitle(chapter.title, seq),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.book.copyWith(
                    color: active ? t.onAccent : t.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  status,
                  style: AppType.caption.copyWith(
                    color: active
                        ? t.onAccent.withValues(alpha: .75)
                        : t.muted,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.play_arrow_rounded,
            size: 22,
            color: active ? t.onAccent : t.text,
          ),
        ],
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  final BookItem book;
  final int index;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ShelfCard({
    required this.book,
    required this.index,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = active ? t.surfaceAlt : chapterToneColor(t, index);
    return ClubCard(
      color: color,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: t.outline, width: 1.6),
            ),
            child: Text(
              book.title.isEmpty ? '书' : book.title.substring(0, 1),
              style: AppType.title.copyWith(color: t.text, fontSize: 19),
            ),
          ),
          const SizedBox(width: 11),
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
                const SizedBox(height: 2),
                Text(
                  '${book.chapterCount} 幕 · ${fmtListenTime(book.hanChars)}'
                  '${book.lastPosMs > 0 ? ' · 听到 ${fmt(Duration(milliseconds: book.lastPosMs))}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: t.muted,
                    letterSpacing: .1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            ClubTag('正在听', color: t.lemon)
          else
            Icon(Icons.chevron_right_rounded, color: t.muted, size: 22),
        ],
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _ImportCard({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: t.surface,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: t.lilac,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.outline, width: 1.8),
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.onAccent,
                    ),
                  )
                : Icon(Icons.add_rounded, color: t.onAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  busy ? '正在拆本' : '导入 TXT 新剧本',
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
                Text(
                  '书留在本机，断网也能听',
                  style: AppType.caption.copyWith(color: t.faint),
                ),
              ],
            ),
          ),
          Icon(Icons.upload_file_rounded, size: 20, color: t.muted),
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  final VoidCallback? onImport;

  const _StartCard({this.onImport});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: t.coral,
      shadow: 6,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClubTag('今晚还空着', color: t.lemon),
          const SizedBox(height: 12),
          Text(
            '从一本 TXT 开场',
            style: AppType.title.copyWith(
              color: t.onAccent,
              fontSize: 25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '切章、分角色、合成声音，都在本机完成。',
            style: AppType.body.copyWith(
              color: t.onAccent.withValues(alpha: .82),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          ClubButton(
            label: '导入 TXT',
            icon: Icons.upload_file_rounded,
            color: t.lemon,
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}

class _EmptyClub extends StatelessWidget {
  final VoidCallback? onImport;
  final VoidCallback onHowTo;

  const _EmptyClub({required this.onImport, required this.onHowTo});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 34, 26, 54),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.lemon,
                shape: BoxShape.circle,
                border: Border.all(color: t.outline, width: 2.5),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: t.outline,
                    offset: const Offset(6, 6),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Text(
                '空',
                style: AppType.hero.copyWith(
                  color: t.onAccent,
                  fontSize: 52,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '还没开演',
              style: AppType.hero.copyWith(color: t.text),
            ),
            const SizedBox(height: 8),
            Text(
              '先导入一本 TXT。拾声会把章节和说话人拆开，'
              '让每个角色坐进自己的位置。',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: t.muted, height: 1.7),
            ),
            const SizedBox(height: 20),
            ClubButton(
              label: '导入第一本',
              icon: Icons.upload_file_rounded,
              onTap: onImport,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onHowTo,
              child: Text(
                '怎么开演？',
                style: AppType.body.copyWith(
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

class _ImportProgressSheet extends StatelessWidget {
  final ValueNotifier<String> status;

  const _ImportProgressSheet({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClubAvatar(label: '导', tone: CastTone.lilac, size: 54),
            const SizedBox(height: 14),
            Text('正在拆本', style: AppType.title.copyWith(color: t.text)),
            const SizedBox(height: 7),
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (ctx, value, _) => Text(
                value,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.muted, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningNightSheet extends StatelessWidget {
  final BookItem book;
  final bool ready;

  const _OpeningNightSheet({required this.book, required this.ready});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClubTag('OPENING NIGHT', color: t.lemon),
            const SizedBox(height: 12),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.title.copyWith(color: t.text, fontSize: 25),
            ),
            const SizedBox(height: 6),
            Text(
              ready
                  ? '第一幕已经备好。戴上耳机，认识一下今晚的角色。'
                  : '第一幕正在后台合成。通常十几秒，先去剧本架等它。',
              style: AppType.body.copyWith(color: t.muted, height: 1.65),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: ClubButton(
                    label: ready ? '现在开场' : '去剧本架',
                    icon: ready
                        ? Icons.play_arrow_rounded
                        : Icons.menu_book_rounded,
                    expand: true,
                    onTap: () => Navigator.pop(
                      context,
                      ready ? 'listen' : 'shelf',
                    ),
                  ),
                ),
                if (ready) ...<Widget>[
                  const SizedBox(width: 10),
                  ClubCard(
                    color: t.surface,
                    radius: AppRadius.pill,
                    shadow: 3,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    onTap: () => Navigator.pop(context, 'shelf'),
                    child: Text(
                      '等一下',
                      style: AppType.button.copyWith(color: t.text),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ScriptBoardScreen extends StatefulWidget {
  final List<BookItem>? previewBooks;
  final VoidCallback? onGoCast;

  const ScriptBoardScreen({
    super.key,
    this.previewBooks,
    this.onGoCast,
  });

  @override
  State<ScriptBoardScreen> createState() => _ScriptBoardScreenState();
}

class _ScriptBoardScreenState extends State<ScriptBoardScreen> {
  List<BookItem> books = <BookItem>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.previewBooks != null) {
      books = widget.previewBooks!;
      loading = false;
      return;
    }
    libraryRevision.addListener(_onRevision);
    unawaited(_load());
  }

  @override
  void dispose() {
    if (widget.previewBooks == null) {
      libraryRevision.removeListener(_onRevision);
    }
    super.dispose();
  }

  void _onRevision() {
    unawaited(_load());
  }

  Future<void> _load() async {
    final out = await _loadAllBooks();
    if (!mounted) return;
    setState(() {
      books = out;
      loading = false;
    });
  }

  void _open(BookItem book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScriptScreen(book: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ClubBackdrop(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: RefreshIndicator(
                onRefresh: _load,
                color: t.coral,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: t.mint,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: t.outline, width: 2),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: t.outline,
                                    offset: const Offset(2.5, 2.5),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.auto_stories_rounded,
                                color: t.onAccent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '剧本库',
                                  style: AppType.title.copyWith(color: t.text),
                                ),
                                Text(
                                  'SCRIPTS / 本机',
                                  style: AppType.label.copyWith(
                                    color: t.faint,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            ClubTag('${books.length} 本'),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '翻到想听的那一幕',
                              style: AppType.hero.copyWith(color: t.text),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '每本剧本都带着自己的角色表、分镜和合成进度。',
                              style: AppType.body.copyWith(
                                color: t.muted,
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    else if (books.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyScripts(onGoCast: widget.onGoCast),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 44),
                        sliver: SliverList.separated(
                          itemCount: books.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (ctx, i) => _ScriptBoardCard(
                            book: books[i],
                            index: i,
                            onTap: () => _open(books[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScriptBoardCard extends StatelessWidget {
  final BookItem book;
  final int index;
  final VoidCallback onTap;

  const _ScriptBoardCard({
    required this.book,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final cast = castForBook(book.ir).take(3).toList();
    final color = chapterToneColor(t, index);
    return ClubCard(
      color: color,
      shadow: 4,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClubTag(
                'NO.${'${index + 1}'.padLeft(2, '0')}',
                color: t.surface,
              ),
              if (book.lastPosMs > 0) ...<Widget>[
                const SizedBox(width: 6),
                ClubTag('上次听到 ${fmt(Duration(milliseconds: book.lastPosMs))}'),
              ],
              const Spacer(),
              Icon(Icons.arrow_outward_rounded, size: 19, color: t.text),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(
              color: t.text,
              fontSize: 24,
              height: 1.24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${book.chapterCount} 幕 · ${fmtListenTime(book.hanChars)} · '
            '已存 ${(book.renderedRatio * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: t.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (var i = 0; i < cast.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: ClubAvatar(
                    member: cast[i],
                    size: 28,
                    outlined: false,
                  ),
                ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  cast.map((e) => e.name).join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: t.muted,
                    letterSpacing: .2,
                  ),
                ),
              ),
              Text(
                '翻剧本',
                style: AppType.caption.copyWith(
                  color: t.text,
                  decoration: TextDecoration.underline,
                  decorationColor: t.faint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyScripts extends StatelessWidget {
  final VoidCallback? onGoCast;

  const _EmptyScripts({this.onGoCast});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '剧本架是空的',
              style: AppType.hero.copyWith(color: t.text),
            ),
            const SizedBox(height: 8),
            Text(
              '先去阵容导入一本 TXT。',
              style: AppType.body.copyWith(color: t.muted),
            ),
            const SizedBox(height: 18),
            ClubButton(
              label: '去阵容',
              icon: Icons.groups_2_outlined,
              onTap: onGoCast,
            ),
          ],
        ),
      ),
    );
  }
}

class ScriptScreen extends StatefulWidget {
  final BookItem book;
  final int? activeSeq;
  final bool preview;
  final bool pickOnly;
  final Map<int, Map<String, dynamic>>? previewStates;

  const ScriptScreen({
    super.key,
    required this.book,
    this.activeSeq,
    this.preview = false,
    this.pickOnly = false,
    this.previewStates,
  });

  @override
  State<ScriptScreen> createState() => _ScriptScreenState();
}

class _ScriptScreenState extends State<ScriptScreen> {
  final Map<int, Map<String, dynamic>> _state =
      <int, Map<String, dynamic>>{};
  Timer? _timer;
  bool _refreshing = false;
  BookVoices? _voices;

  @override
  void initState() {
    super.initState();
    final previewStates = widget.previewStates;
    if (previewStates != null) {
      _state.addAll(previewStates);
      return;
    }
    unawaited(_loadAll());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshStates()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final voices = await Data.loadVoices(widget.book.bid);
    for (final chapter in widget.book.ir.chapters) {
      final idx = await Data.readIndex(widget.book.bid, chapter.seq);
      if (idx != null) _state[chapter.seq] = idx;
    }
    if (!mounted) return;
    setState(() => _voices = voices);
  }

  Future<void> _refreshStates() async {
    if (_refreshing || !mounted || widget.preview) return;
    _refreshing = true;
    try {
      var changed = false;
      final summary = await Data.readSummary(widget.book.bid);
      final doneMap =
          (summary?['chapters'] as Map?) ?? const <String, dynamic>{};
      for (final chapter in widget.book.ir.chapters) {
        final entry = doneMap['${chapter.seq}'];
        if (entry is Map &&
            entry['done'] == true &&
            entry['pipe'] == audioPipelineVersion) {
          final current = _state[chapter.seq];
          if (current == null || current['done'] != true) {
            _state[chapter.seq] = Map<String, dynamic>.from(entry);
            changed = true;
          }
        }
      }
      final focus = <int>{};
      final active = widget.activeSeq;
      if (active != null) {
        for (var offset = 0; offset <= 3; offset++) {
          focus.add(active + offset);
        }
      } else {
        focus.addAll(<int>[0, 1, 2]);
      }
      for (final entry in _state.entries) {
        if (entry.value['done'] != true) focus.add(entry.key);
      }
      for (final seq in focus) {
        if (seq < 0 || seq >= widget.book.ir.chapters.length) continue;
        final idx = await Data.readIndex(widget.book.bid, seq);
        if (idx == null) continue;
        final before = _state[seq];
        final same = before != null &&
            before['done'] == idx['done'] &&
            (before['blocks'] as List?)?.length ==
                (idx['blocks'] as List?)?.length &&
            before['total_ms'] == idx['total_ms'] &&
            before['plan_blocks'] == idx['plan_blocks'] &&
            before['error'] == idx['error'];
        if (!same) {
          _state[seq] = idx;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    } finally {
      _refreshing = false;
    }
  }

  void _play(int seq, {int ms = 0}) {
    if (widget.pickOnly) {
      Navigator.of(context).pop(seq);
      return;
    }
    Navigator.of(context)
        .push(
          playerRoute(
            PlayerScreen(
              book: widget.book,
              startSeq: seq,
              startMs: ms,
            ),
          ),
        )
        .then((_) {
      if (mounted) unawaited(_refreshStates());
    });
  }

  Future<void> _prioritize(int seq) async {
    setState(() {
      _state[seq] = <String, dynamic>{
        'pipe': audioPipelineVersion,
        'done': false,
        'blocks': <dynamic>[],
        'total_ms': 0,
        'plan_blocks': null,
      };
    });
    await Renderer.ensure(() => Boot.tts);
    await Renderer.instance.touch(widget.book.bid, seq, Renderer.priUser);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已把这幕提前，几秒后开工。')),
    );
  }

  static int _durationMs(Chapter chapter, Map<String, dynamic>? idx) {
    final total = (idx?['total_ms'] as num?)?.toInt() ?? 0;
    if (total > 0) return total;
    final estimated = (idx?['est_ms'] as num?)?.toInt() ?? 0;
    if (estimated > 0) return estimated;
    var seconds = 0.0;
    for (final segment in chapter.segments) {
      seconds += estSec(segment);
    }
    return (seconds * 1000).round();
  }

  int get _lastSeq {
    final last = lastPlayed();
    if (last?['bid'] == widget.book.bid) {
      return (last?['seq'] as num?)?.toInt() ?? widget.book.lastSeq;
    }
    return widget.book.lastSeq;
  }

  int get _lastPos {
    final last = lastPlayed();
    if (last?['bid'] == widget.book.bid) {
      return (last?['pos'] as num?)?.toInt() ?? widget.book.lastPosMs;
    }
    return widget.book.lastPosMs;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final book = widget.book;
    final chapters = book.ir.chapters;
    final lastSeq = _lastSeq.clamp(
      0,
      math.max(0, chapters.length - 1),
    ).toInt();
    final lastPos = _lastPos;
    final lastTitle = chapters.isEmpty
        ? '第一幕'
        : _cleanChapterTitle(chapters[lastSeq].title, lastSeq);
    final cast = castForBook(book.ir, voices: _voices);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ClubBackdrop(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 24, 0),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            tooltip: '返回',
                            icon: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 18,
                              color: t.text,
                            ),
                          ),
                          Text(
                            '剧本',
                            style: AppType.bodyStrong.copyWith(color: t.muted),
                          ),
                          const Spacer(),
                          ClubTag('${chapters.length} 幕'),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const ClubTag(
                                'SCRIPT / 剧本',
                                color: Color(0xFFFFE347),
                              ),
                              const Spacer(),
                              Text(
                                book.generatedLabel,
                                style: AppType.meta.copyWith(color: t.faint),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            book.title,
                            style: AppType.hero.copyWith(
                              color: t.text,
                              fontSize: 34,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${book.chapterCount} 幕 · '
                            '${fmtListenTime(book.hanChars)} · 本机合成',
                            style: AppType.meta.copyWith(color: t.muted),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 34,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: cast.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (ctx, i) => Container(
                                padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                                decoration: BoxDecoration(
                                  color: t.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: t.outline,
                                    width: 1.4,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    ClubAvatar(
                                      member: cast[i],
                                      size: 26,
                                      outlined: false,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      cast[i].name,
                                      style: AppType.caption.copyWith(
                                        color: t.text,
                                        letterSpacing: .1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ResumeTicket(
                            title: lastTitle,
                            time: fmt(Duration(milliseconds: lastPos)),
                            onTap: () => _play(lastSeq, ms: lastPos),
                          ),
                          const SizedBox(height: 24),
                          ClubSectionTitle(
                            kicker: 'SCENES / 分镜',
                            title: '分镜表',
                            accent: t.mint,
                            trailing: Text(
                              '从第 ${lastSeq + 1} 幕继续',
                              style: AppType.meta.copyWith(color: t.faint),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (ctx, i) {
                        final chapter = chapters[i];
                        final idx = _state[chapter.seq];
                        final fresh = idx?['pipe'] == audioPipelineVersion;
                        final done = idx?['done'] == true && fresh;
                        final rendering = idx != null && !done && fresh;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ChapterCard(
                            chapter: chapter,
                            index: i,
                            active: widget.activeSeq == chapter.seq,
                            done: done,
                            rendering: rendering,
                            blocks: (idx?['blocks'] as List?)?.length ?? 0,
                            plan: idx?['plan_blocks'] as int?,
                            durationMs: _durationMs(chapter, idx),
                            onTap: () => _play(chapter.seq),
                            onPrioritize: () => _prioritize(chapter.seq),
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 42)),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.pickOnly ? null : const _ClubNowPlayingBar(),
    );
  }
}

class _ResumeTicket extends StatelessWidget {
  final String title;
  final String time;
  final VoidCallback onTap;

  const _ResumeTicket({
    required this.title,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: t.lemon,
      shadow: 4,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface,
              shape: BoxShape.circle,
              border: Border.all(color: t.outline, width: 1.8),
            ),
            child: Icon(Icons.play_arrow_rounded, color: t.text, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '上次停在这里',
                  style: AppType.label.copyWith(color: t.muted, fontSize: 9),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.book.copyWith(color: t.text),
                ),
              ],
            ),
          ),
          Text(time, style: AppType.time.copyWith(color: t.text)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: t.text, size: 22),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final Chapter chapter;
  final int index;
  final bool active;
  final bool done;
  final bool rendering;
  final int blocks;
  final int? plan;
  final int durationMs;
  final VoidCallback onTap;
  final VoidCallback onPrioritize;

  const _ChapterCard({
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

  String _lengthLabel(int ms) {
    final seconds = (ms / 1000).round();
    final minutes = seconds ~/ 60;
    final remain = seconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60} 小时 ${minutes % 60} 分';
    }
    if (minutes > 0) return '$minutes 分 $remain 秒';
    return '$seconds 秒';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final percent = rendering && (plan ?? 0) > 0
        ? (blocks / plan! * 100).clamp(0, 100).round()
        : null;
    final color = active ? t.coral : chapterToneColor(t, index);
    final fg = active ? t.onAccent : t.text;
    final status = active
        ? '正在播放'
        : rendering
        ? (percent == null ? '正在合成' : '合成 $percent%')
        : done
        ? '已合成'
        : '待合成';
    return ClubCard(
      color: color,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: t.outline, width: 1.6),
            ),
            child: Text(
              '${chapter.no ?? index + 1}'.padLeft(2, '0'),
              style: AppType.book.copyWith(
                color: t.text,
                fontSize: 17,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _cleanChapterTitle(chapter.title, index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.book.copyWith(color: fg),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_lengthLabel(durationMs)} · $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: active ? t.onAccent.withValues(alpha: .76) : t.muted,
                    letterSpacing: .1,
                  ),
                ),
                if (rendering) ...<Widget>[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: percent == null ? null : percent / 100,
                      minHeight: 4,
                      backgroundColor: t.onAccent.withValues(alpha: .12),
                      valueColor: AlwaysStoppedAnimation<Color>(t.coral),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            Icon(Icons.graphic_eq_rounded, color: t.onAccent, size: 23)
          else if (rendering)
            Text(
              percent == null ? '···' : '$percent%',
              style: AppType.meta.copyWith(color: t.text),
            )
          else if (done)
            Icon(Icons.check_circle_rounded, color: t.success, size: 21)
          else
            InkResponse(
              onTap: onPrioritize,
              radius: 26,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.outline, width: 1.3),
                ),
                child: Text(
                  '先合成',
                  style: AppType.caption.copyWith(
                    color: t.text,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClubNowPlayingBar extends StatelessWidget {
  const _ClubNowPlayingBar();

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
            chapter: '第 ${np.seq + 1} 幕 · ${np.chapterTitle}',
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

enum _VoiceSource { local, auto, voiceStudio }

class AuditionScreen extends StatefulWidget {
  final BookItem? previewBook;

  const AuditionScreen({super.key, this.previewBook});

  @override
  State<AuditionScreen> createState() => _AuditionScreenState();
}

class _AuditionScreenState extends State<AuditionScreen> {
  BookItem? _book;
  BookVoices? _voices;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.previewBook != null) {
      _book = widget.previewBook;
      _loading = false;
      return;
    }
    libraryRevision.addListener(_onRevision);
    unawaited(_loadCurrent());
  }

  @override
  void dispose() {
    if (widget.previewBook == null) {
      libraryRevision.removeListener(_onRevision);
    }
    super.dispose();
  }

  void _onRevision() {
    unawaited(_loadCurrent());
  }

  Future<void> _loadCurrent() async {
    final last = lastPlayed();
    final bid = last?['bid'] as String?;
    if (bid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final ir = await Data.loadBook(bid);
    if (ir == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final item = await loadBookItem(bid, ir);
    final voices = await Data.loadVoices(bid);
    if (!mounted) return;
    setState(() {
      _book = item;
      _voices = voices;
      _loading = false;
    });
  }

  _VoiceSource get _source {
    final settings = AppSettings.instance;
    if (settings.voiceStudioEnabled.value) return _VoiceSource.voiceStudio;
    if (settings.cloudAllowed.value) return _VoiceSource.auto;
    return _VoiceSource.local;
  }

  String get _sourceLabel {
    return switch (_source) {
      _VoiceSource.local => '本机',
      _VoiceSource.auto => '自动',
      _VoiceSource.voiceStudio => '外接',
    };
  }

  List<CastMember> get _cast {
    final book = _book;
    if (book != null) {
      return castForBook(book.ir, voices: _voices, limit: 4);
    }
    return const <CastMember>[
      CastMember(
        name: '旁白',
        tone: CastTone.narrator,
        sid: VoicePool.defaultNarrator,
        lines: 0,
        narrator: true,
      ),
      CastMember(
        name: '男声',
        tone: CastTone.lemon,
        sid: VoicePool.defaultDialogueM,
        lines: 0,
      ),
      CastMember(
        name: '女声',
        tone: CastTone.coral,
        sid: VoicePool.defaultDialogueF,
        lines: 0,
      ),
    ];
  }

  String _roleOf(CastMember member) {
    if (_book != null) return member.roleLabel;
    if (member.narrator) return '旁白音轨';
    return member.name == '男声' ? '男声音轨' : '女声音轨';
  }

  Future<void> _selectSource(_VoiceSource source) async {
    final settings = AppSettings.instance;
    switch (source) {
      case _VoiceSource.local:
        await settings.setVoiceStudioEnabled(false);
        await settings.setCloudAllowed(false);
        break;
      case _VoiceSource.auto:
        await settings.setVoiceStudioEnabled(false);
        await settings.setCloudAllowed(true);
        break;
      case _VoiceSource.voiceStudio:
        await settings.setCloudAllowed(false);
        await settings.setVoiceStudioEnabled(true);
        unawaited(VoiceStudioTts.available(force: true));
        break;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final settings = AppSettings.instance;
    final cast = _cast;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ClubBackdrop(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 46),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.coral,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.outline, width: 2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: t.outline,
                              offset: const Offset(2.5, 2.5),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: t.onAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '试镜间',
                            style: AppType.title.copyWith(color: t.text),
                          ),
                          Text(
                            'VOICE / 声卡',
                            style: AppType.label.copyWith(
                              color: t.faint,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      ClubTag(_sourceLabel, color: t.mint),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '给每个角色\n一张声卡',
                    style: AppType.hero.copyWith(
                      color: t.text,
                      height: 1.04,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _book == null
                        ? '还没有在演的书。先看系统给旁白、男声、女声分配了哪三路声音。'
                        : '《${_book!.title}》的角色已经自动对号入座。'
                            '换声源会从下一句开始生效。',
                    style: AppType.body.copyWith(color: t.muted, height: 1.65),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: t.coral,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < cast.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == cast.length - 1 ? 0 : 10,
                        ),
                        child: _VoiceCard(
                          member: cast[i],
                          role: _roleOf(cast[i]),
                          source: _sourceLabel,
                          index: i,
                        ),
                      ),
                  const SizedBox(height: 24),
                  _SettingsCard(
                    title: '声音来源',
                    note: '本机不出网；自动会在联网时尝试云端音色，断网回本机；'
                        '外接用你电脑上的 VoiceStudio。',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: Listenable.merge(<Listenable>[
                            settings.cloudAllowed,
                            settings.voiceStudioEnabled,
                          ]),
                          builder: (ctx, _) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              _Pill(
                                label: '本机',
                                selected: _source == _VoiceSource.local,
                                onTap: () => _selectSource(_VoiceSource.local),
                              ),
                              _Pill(
                                label: '自动',
                                selected: _source == _VoiceSource.auto,
                                onTap: () => _selectSource(_VoiceSource.auto),
                              ),
                              _Pill(
                                label: '外接 VoiceStudio',
                                selected:
                                    _source == _VoiceSource.voiceStudio,
                                onTap: () =>
                                    _selectSource(_VoiceSource.voiceStudio),
                              ),
                            ],
                          ),
                        ),
                        if (_source == _VoiceSource.voiceStudio) ...<Widget>[
                          const SizedBox(height: 14),
                          _VsField(
                            label: 'VoiceStudio 地址',
                            hint: 'http://192.168.1.20:3900',
                            value: settings.voiceStudioUrl.value,
                            keyboard: TextInputType.url,
                            onChanged: settings.setVoiceStudioUrl,
                          ),
                          const SizedBox(height: 10),
                          _VsField(
                            label: 'API Key（没有就留空）',
                            hint: 'Bearer token',
                            value: settings.voiceStudioKey.value,
                            obscure: true,
                            onChanged: settings.setVoiceStudioKey,
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<String?>(
                            valueListenable: VoiceStudioTts.statusLine,
                            builder: (ctx, status, _) {
                              if (status == null || status.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                status,
                                style: AppType.caption.copyWith(
                                  color: t.faint,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '播放',
                    note: '这些值会成为下一次开场的默认值。',
                    child: Column(
                      children: <Widget>[
                        _ChoicePills<int>(
                          title: '快进 / 快退',
                          values: const <int>[10, 15, 30, 45, 60],
                          label: (value) => '$value 秒',
                          notifier: settings.skipSeconds,
                          onChanged: settings.setSkipSeconds,
                        ),
                        const SizedBox(height: 14),
                        _ChoicePills<double>(
                          title: '默认语速',
                          values: const <double>[0.75, 1.0, 1.25, 1.5, 2.0],
                          label: (value) => '${value}x',
                          notifier: settings.defaultSpeed,
                          onChanged: settings.setDefaultSpeed,
                        ),
                        const SizedBox(height: 14),
                        _ChoicePills<int>(
                          title: '默认睡眠',
                          values: const <int>[15, 30, 45, 60],
                          label: (value) => '$value 分钟',
                          notifier: settings.sleepDefault,
                          onChanged: settings.setSleepDefault,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: settings.autoRewind,
                          builder: (ctx, value, _) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '暂停久了自动回退',
                                      style: AppType.body.copyWith(
                                        color: t.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '离开一会儿回来，从刚才那句接上。',
                                      style: AppType.caption.copyWith(
                                        color: t.faint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch.adaptive(
                                value: value,
                                activeTrackColor: t.coral,
                                activeThumbColor: t.onAccent,
                                inactiveTrackColor: t.surfaceAlt,
                                inactiveThumbColor: t.surface,
                                trackOutlineColor:
                                    WidgetStatePropertyAll<Color>(t.outline),
                                onChanged: settings.setAutoRewind,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '外观',
                    note: '剧场的灯可以亮一点，也可以暗一点。',
                    child: ValueListenableBuilder<ThemeMode>(
                      valueListenable: settings.themeMode,
                      builder: (ctx, mode, _) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final entry in <(ThemeMode, String)>[
                            (ThemeMode.system, '跟随系统'),
                            (ThemeMode.light, '亮场'),
                            (ThemeMode.dark, '暗场'),
                          ])
                            _Pill(
                              label: entry.$2,
                              selected: mode == entry.$1,
                              onTap: () =>
                                  settings.setThemeMode(entry.$1),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _StoragePanel(),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    title: '关于',
                    note: '书、角色和听读进度都留在本机。',
                    trailing: '拾声 v$kAppVersion',
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: t.success,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '默认不联网。只有你主动选「自动」或「外接」时，'
                            '才把待合成的句子送出去。',
                            style: AppType.caption.copyWith(
                              color: t.muted,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
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

class _VoiceCard extends StatelessWidget {
  final CastMember member;
  final String role;
  final String source;
  final int index;

  const _VoiceCard({
    required this.member,
    required this.role,
    required this.source,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: index.isEven ? t.surface : t.surfaceAlt,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Row(
        children: <Widget>[
          ClubAvatar(member: member, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.book.copyWith(color: t.text),
                      ),
                    ),
                    ClubTag(source, color: t.lemon),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$role · ${member.voiceCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: t.muted,
                    letterSpacing: .1,
                  ),
                ),
                const SizedBox(height: 8),
                ClubWaveform(
                  bars: 15,
                  height: 19,
                  color: castToneColor(t, member.tone),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: <Widget>[
              Icon(Icons.mic_none_rounded, size: 20, color: t.muted),
              const SizedBox(height: 18),
              Icon(Icons.lock_outline_rounded, size: 13, color: t.faint),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? note;
  final String? trailing;
  final Widget child;

  const _SettingsCard({
    required this.title,
    required this.child,
    this.note,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: t.surface,
      shadow: 3,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: AppType.title.copyWith(color: t.text, fontSize: 19),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppType.caption.copyWith(color: t.faint),
                ),
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              note!,
              style: AppType.caption.copyWith(
                color: t.muted,
                height: 1.5,
                letterSpacing: .1,
              ),
            ),
          ],
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Pill({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClubCard(
      color: selected ? t.coral : t.surface,
      radius: AppRadius.pill,
      shadow: selected ? 2 : 0,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      onTap: onTap,
      child: Text(
        label,
        maxLines: 1,
        style: AppType.button.copyWith(
          color: selected ? t.onAccent : t.text,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ChoicePills<T> extends StatelessWidget {
  final String title;
  final List<T> values;
  final String Function(T) label;
  final ValueNotifier<T> notifier;
  final Future<void> Function(T) onChanged;

  const _ChoicePills({
    required this.title,
    required this.values,
    required this.label,
    required this.notifier,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: AppType.bodyStrong.copyWith(color: t.text)),
        const SizedBox(height: 8),
        ValueListenableBuilder<T>(
          valueListenable: notifier,
          builder: (ctx, current, _) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final value in values)
                _Pill(
                  label: label(value),
                  selected: value == current,
                  onTap: () => onChanged(value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VsField extends StatelessWidget {
  final String label;
  final String hint;
  final String value;
  final TextInputType? keyboard;
  final bool obscure;
  final Future<void> Function(String) onChanged;

  const _VsField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.keyboard,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return TextFormField(
      initialValue: value,
      keyboardType: keyboard,
      obscureText: obscure,
      style: AppType.body.copyWith(color: t.text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppType.caption.copyWith(color: t.muted),
        hintStyle: AppType.caption.copyWith(color: t.faint),
        filled: true,
        fillColor: t.surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.outline, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.coral, width: 2),
        ),
      ),
      onChanged: (text) => unawaited(onChanged(text)),
    );
  }
}

class _StoragePanel extends StatefulWidget {
  const _StoragePanel();

  @override
  State<_StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<_StoragePanel> {
  late Future<StorageAudit> _audit;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _audit = Cleanup.audit();
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  Future<void> _refresh() async {
    setState(() => _audit = Cleanup.audit());
    await _audit;
  }

  Future<void> _clean() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cap =
          AppSettings.instance.storageCapMb.value * 1024 * 1024;
      final report = await Cleanup.enforce(
        capBytes: cap,
        reason: 'manual',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.ran
                ? '已清理 ${_fmtBytes(report.freedBytes)}，删除 ${report.chaptersDeleted} 幕。'
                : '占用还在上限内，不用清。',
          ),
        ),
      );
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('清理失败，稍后再试。')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return _SettingsCard(
      title: '存储',
      note: '超过上限时，从最久没听的音频开始清；正在听的几幕不碰。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FutureBuilder<StorageAudit>(
            future: _audit,
            builder: (ctx, snapshot) {
              final audit = snapshot.data;
              final value = audit == null ? '计算中…' : _fmtBytes(audit.totalBytes);
              return Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '当前占用',
                      style: AppType.bodyStrong.copyWith(color: t.text),
                    ),
                  ),
                  Text(
                    value,
                    style: AppType.book.copyWith(
                      color: t.text,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Pill(
                    label: _busy ? '清理中' : '清理',
                    selected: false,
                    onTap: _busy ? null : _clean,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _ChoicePills<int>(
            title: '存储上限',
            values: const <int>[512, 1024, 2048, 4096, 0],
            label: (value) => value == 0 ? '不限' : '$value MB',
            notifier: AppSettings.instance.storageCapMb,
            onChanged: (value) async {
              await AppSettings.instance.setStorageCapMb(value);
            },
          ),
        ],
      ),
    );
  }
}
