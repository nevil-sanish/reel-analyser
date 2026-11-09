import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/data/blocker.dart';

void main() {
  test('config round trip and damaged values', () {
    final c = BlockConfig(
      'separate',
      {'instagram', 'browser'},
      {
        'instagram': const BlockRule(30, [TimeSlot(480, 540)]),
        'browser': const BlockRule(null, []),
      },
    );
    final back = BlockConfig.parse(c.toJson())!;
    expect(back.mode, 'separate');
    expect(back.items, {'instagram', 'browser'});
    expect(back.rules['instagram']!.limitMin, 30);
    expect(back.rules['instagram']!.intervals, [const TimeSlot(480, 540)]);
    expect(back.rules['browser']!.limitMin, isNull);
    expect(BlockConfig.parse('nonsense'), isNull);
    expect(BlockConfig.parse(null), isNull);
  });

  test('history lines say what happened', () {
    expect(
      BlockEvent(DateTime(2026), 'limit', 'instagram').label,
      contains('daily limit'),
    );
    expect(
      BlockEvent(DateTime(2026), 'cancelled', 'youtube').label,
      contains('Cancelled the block'),
    );
    expect(
      BlockEvent(DateTime(2026), 'removed', '').label,
      contains('for good'),
    );
  });

  group('paragraph guard', () {
    final t0 = DateTime(2026, 11, 9, 10);
    final para = List.generate(55, (i) => 'word$i').join(' ');

    String typeAll(
      ParagraphGuard g,
      String text, {
      Duration every = const Duration(seconds: 3),
    }) {
      var now = t0, s = '';
      for (final ch in text.split('')) {
        s += ch;
        now = now.add(every ~/ 4);
        expect(g.accept(s, now), isTrue);
      }
      return s;
    }

    test('typing it by hand is accepted', () {
      final g = ParagraphGuard();
      typeAll(g, para);
      expect(g.check(), isNull);
    });

    test('a paste is refused, and so is a chunk bigger than a swiped word', () {
      final g = ParagraphGuard();
      expect(g.accept('hello', t0), isTrue);
      expect(g.accept('hello $para', t0), isFalse);
      expect(g.text, 'hello');
      expect(g.accept('hello there friend', t0), isTrue);
    });

    test('too short, or written too fast, is refused', () {
      final short = ParagraphGuard();
      typeAll(short, 'I want it gone because it is hard.');
      expect(short.check(), contains('at least'));
      final fast = ParagraphGuard();
      typeAll(fast, para, every: const Duration(milliseconds: 20));
      expect(fast.check(), contains('by hand'));
    });

    test('wording and dashes typical of AI are refused', () {
      for (final bad in [
        '$para — and more',
        '$para as an AI I',
        '$para let us delve',
      ]) {
        final g = ParagraphGuard();
        typeAll(g, bad);
        expect(g.check(), contains('AI'), reason: bad);
      }
    });
  });
}
