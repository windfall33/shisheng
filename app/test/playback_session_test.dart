import 'package:flutter_test/flutter_test.dart';
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
}
