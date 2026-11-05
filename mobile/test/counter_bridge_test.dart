import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/native/counter_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
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
          _ => null,
        };
      },
    );
  });

  // T-CH-03 (Dart side)
  test('T-CH-03 daily groups by date; seenItems, debugState and setCapture map through', () async {
    final b = CounterBridge();
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
}
