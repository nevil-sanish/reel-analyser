import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/blocker.dart';

void main() {
  test('config round trip and damaged values', () {
    final c = BlockConfig(
      'separate',
      {'instagram', 'browser'},
      {
        'instagram': const BlockRule(30, [TimeSlot(480, 540)]),
        'browser': const BlockRule(null, []),
      },
      wholeApp: {'instagram'},
    );
    final back = BlockConfig.parse(c.toJson())!;
    expect(back.mode, 'separate');
    expect(back.items, {'instagram', 'browser'});
    expect(back.rules['instagram']!.limitMin, 30);
    expect(back.rules['instagram']!.intervals, [const TimeSlot(480, 540)]);
    expect(back.rules['browser']!.limitMin, isNull);
    expect(back.wholeApp, {'instagram'});
    expect(BlockConfig.parse('{"mode":"shared","items":[],"rules":{}}')!.wholeApp, isEmpty, reason: 'rules saved before 1.2.0.0');
    expect(describeRules(back), contains('the whole Instagram app'));
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
        expect(g.accept(s, now), isNull);
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
      expect(g.accept('hello', t0), isNull);
      expect(g.accept('hello $para', t0), ParagraphGuard.pasteMessage);
      expect(g.text, 'hello');
      expect(g.accept('hello there friend', t0), isNull);
    });

    test('too short, or written too fast, is refused', () {
      final short = ParagraphGuard();
      typeAll(short, 'I want it gone because it is hard.');
      expect(short.check(), contains('at least'));
      final fast = ParagraphGuard();
      typeAll(fast, para, every: const Duration(milliseconds: 400));
      expect(fast.check(), contains('by hand'));
    });

    test('typing very fast locks the field until 2 seconds pass with no typing', () {
      final g = ParagraphGuard();
      var now = t0, s = '';
      String? last;
      for (var i = 0; i < 30 && last == null; i++) {
        s += 'a';
        now = now.add(const Duration(milliseconds: 30));
        last = g.accept(s, now);
      }
      expect(last, ParagraphGuard.slowMessage);
      final kept = g.text;
      now = now.add(const Duration(milliseconds: 1500));
      expect(g.accept('${kept}b', now), ParagraphGuard.slowMessage, reason: 'still in the cooldown');
      now = now.add(const Duration(milliseconds: 1900));
      expect(g.accept('${kept}b', now), ParagraphGuard.slowMessage, reason: 'the try restarted the cooldown');
      now = now.add(const Duration(milliseconds: 2000));
      expect(g.accept('${kept}b', now), isNull, reason: '2 seconds without typing');
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
