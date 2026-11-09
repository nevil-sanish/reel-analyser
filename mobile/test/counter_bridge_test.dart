import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/full_bridge.dart';
import 'package:reelbrain/native/counter_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Map<String, Object>? appUsage; // null: no Usage access

  setUp(() {
    calls.clear();
    appUsage = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('reelbot/counter'),
      (c) async {
        calls.add(c);
        return switch (c.method) {
          'daily' => [
              {'date': '2026-11-06', 'app': 'instagram', 'reels': 30, 'ms': 600000, 'unknown': 2},
              {'date': '2026-11-06', 'app': 'youtube', 'reels': 7, 'ms': 120000, 'unknown': 0},
              {'date': '2026-11-05', 'app': 'instagram', 'reels': 3, 'ms': 1000, 'unknown': 6},
            ],
          'seenItems' => [
              {'app': 'youtube', 'fp': 'ab', 'firstSeen': 5, 'dwellMs': 4000, 'author': 'x', 'caption': 'y'},
            ],
          'debugState' => [
              {'k': 'now', 'v': '{}', 'ts': 1},
            ],
          'appUsage' => appUsage,
          'hourly' => [
              {'hour': 21, 'reels': 4, 'ms': 50000},
            ],
          'pendingItems' => [
              {'id': 7, 'url': 'https://www.instagram.com/reel/A/', 'app': 'instagram', 'createdAt': 9, 'status': 'queued'},
            ],
          'fetchInstagram' => c.arguments['url'] == 'limited'
              ? throw PlatformException(code: 'rate_limited', message: 'every step hit a login wall; retrying in 10 min')
              : c.arguments['url'] == 'broken'
                  ? throw PlatformException(code: 'failed', message: 'IllegalArgumentException')
                  : {
                      'step': 2, 'author': 'chef', 'caption': 'Rice', 'thumbnailUrl': 't',
                      'videoPath': '/v.mp4', 'images': ['a', 'b'],
                    },
          _ => null,
        };
      },
    );
  });

  // T-CH-03 (Dart side)
  test('T-CH-03 daily groups by date; seenItems, debugState and setCapture map through', () async {
    final b = FullBridge();
    final h = await b.history();
    expect(h.map((d) => d.date), ['2026-11-06', '2026-11-05']);
    expect(h.first.reels, 37);
    expect(h.first.reelsByApp, {'instagram': 30, 'youtube': 7});
    expect(h.first.ms, 720000);
    expect(h.first.detectionLooksBroken, isFalse);
    expect(h.last.detectionLooksBroken, isTrue);
    expect((await b.seenItems('2026-11-06')).single.dwellMs, 4000);
    expect(await b.debugState(), {'now': '{}'});
    await b.setCapture(true);
    expect(calls.last.arguments, {'on': true});
  });

  // T-CH-01 (Dart side; the Kotlin round-trip is CounterPluginTest)
  test('T-CH-01 pendingItems maps rows; setPendingStatus sends id, status and title', () async {
    final b = CounterBridge();
    final p = (await b.pendingItems(status: 'queued')).single;
    expect((p.id, p.url, p.app, p.createdAt, p.author), (7, 'https://www.instagram.com/reel/A/', 'instagram', 9, ''));
    expect(calls.last.arguments, {'status': 'queued'});
    await b.setPendingStatus(7, 'done', title: 'Rice');
    expect(calls.last.arguments, {'id': 7, 'status': 'done', 'title': 'Rice'});
  });

  // T-CH-02
  test('T-CH-02 fetchInstagram maps the result; rate_limited becomes RateLimited, others stay PlatformException', () async {
    final b = CounterBridge();
    final f = await b.fetchInstagram('ok');
    expect((f.step, f.author, f.caption, f.thumbnailUrl, f.videoPath), (2, 'chef', 'Rice', 't', '/v.mp4'));
    expect(f.images, ['a', 'b']);
    await expectLater(b.fetchInstagram('limited'), throwsA(isA<RateLimited>().having((e) => e.loginWall, 'loginWall', isTrue)));
    await expectLater(b.fetchInstagram('broken'), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'failed')));
  });

  // T-USE-03
  test('T-USE-03 Usage-access time joins the counter days and replaces the hourly time', () async {
    final b = FullBridge();
    expect((await b.hourly())[21], (4, 50000)); // no Usage access: the counter's time

    appUsage = {
      'granted': true,
      'daily': [
        {'date': '2026-11-06', 'app': 'instagram', 'ms': 1800000},
        {'date': '2026-11-06', 'app': 'youtube', 'ms': 600000},
        {'date': '2026-11-04', 'app': 'youtube', 'ms': 60000},
      ],
      'hourly': [
        {'hour': 21, 'app': 'instagram', 'ms': 900000},
        {'hour': 21, 'app': 'youtube', 'ms': 300000},
        {'hour': 8, 'app': 'youtube', 'ms': 60000},
      ],
    };
    final h = await b.history();
    expect(h.map((d) => d.date), ['2026-11-06', '2026-11-05', '2026-11-04']);
    expect(h.first.reels, 37); // counts kept
    expect(h.first.appMs, {'instagram': 1800000, 'youtube': 600000});
    expect(h.first.timeMs, 2400000); // app time wins over the counter's 720000
    expect(h[1].timeMs, 1000); // no Usage-access row that day: the counter's time
    expect(h.last.reels, 0);
    final hours = await b.hourly();
    expect((hours[21], hours[8]), ((4, 1200000), (0, 60000)));
  });
}
