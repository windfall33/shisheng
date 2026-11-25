import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shisheng_reader/playback.dart';

void main() {
  test('后打开的播放器页接管，旧页不再拥有播放权', () {
    final session = PlaybackSession.instance;
    final oldPage = Object();
    final newPage = Object();

    session.claim(oldPage);
    expect(session.owns(oldPage), isTrue);
    expect(session.owns(newPage), isFalse);

    session.claim(newPage);
    expect(session.owns(oldPage), isFalse);
    expect(session.owns(newPage), isTrue);

    session.release(newPage);
    expect(session.owns(oldPage), isTrue);

    session.release(oldPage);
    expect(session.hasOwner, isFalse);
  });

  test('重复 claim 不会在栈里留下同一个页两次', () {
    final session = PlaybackSession.instance;
    final a = Object();
    final b = Object();

    session.claim(a);
    session.claim(b);
    session.claim(a);
    expect(session.owns(a), isTrue);

    session.release(a);
    expect(session.owns(b), isTrue);

    session.release(b);
    expect(session.hasOwner, isFalse);
  });

  test('音源 tag 必须同时匹配书和章，旧章不能冒充新章', () {
    final tag = MediaItem(id: 'book-a:0', title: '第一章');
    expect(audioTagMatchesChapter(tag, 'book-a', 0), isTrue);
    expect(audioTagMatchesChapter(tag, 'book-a', 1), isFalse);
    expect(audioTagMatchesChapter(tag, 'book-b', 0), isFalse);
    expect(audioTagMatchesChapter(null, 'book-a', 0), isFalse);
    expect(audioTagMatchesChapter('book-a:0', 'book-a', 0), isFalse);
  });

  test('播放键：播放中先暂停，音源匹配才继续，否则重新准备', () {
    expect(
      playbackTapAction(playing: true, sourceMatches: true),
      PlaybackTapAction.pause,
    );
    expect(
      playbackTapAction(playing: false, sourceMatches: true),
      PlaybackTapAction.resume,
    );
    expect(
      playbackTapAction(playing: false, sourceMatches: false),
      PlaybackTapAction.prepare,
    );
  });

  test('迷你播放器能识别「正在准备 / 正在合成」状态', () {
    final np = NowPlaying.instance;
    np.clear();
    np.setStatus('正在准备音频…');
    expect(np.preparing, isTrue);
    np.setStatus('正在缓冲 4/30 秒');
    expect(np.preparing, isTrue);
    np.setStatus('正在合成第一块…');
    expect(np.preparing, isTrue);
    np.setStatus('边播边合成 2/12 块');
    expect(np.preparing, isFalse);
    np.clear();
  });
}
