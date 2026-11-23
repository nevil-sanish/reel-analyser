import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/habits.dart';

void main() {
  group('scroll rule', () {
    test('stricter changes are free, looser ones are not', () {
      const before = ScrollRule(maxPerDay: 200, runSwipes: 20, quietSec: 30, pauseMinutes: 5);
      expect(const ScrollRule(maxPerDay: 150, runSwipes: 20, quietSec: 30, pauseMinutes: 5).noLooserThan(before), isTrue);
      expect(const ScrollRule(maxPerDay: 250, runSwipes: 20).noLooserThan(before), isFalse);
      expect(const ScrollRule(maxPerDay: 0, runSwipes: 20).noLooserThan(before), isFalse);
      expect(const ScrollRule(maxPerDay: 200).noLooserThan(before), isFalse, reason: 'dropping the run rule loosens');
      expect(const ScrollRule(maxPerDay: 200, runSwipes: 20, pauseMinutes: 3).noLooserThan(before), isFalse, reason: 'a shorter pause loosens');
      expect(const ScrollRule(maxPerDay: 100).noLooserThan(const ScrollRule()), isTrue, reason: 'from off, anything is stricter');
    });

    test('json round trip and damage', () {
      const r = ScrollRule(maxPerDay: 120, runSwipes: 15, quietSec: 40, pauseMinutes: 7);
      final b = ScrollRule.parse(r.toJson())!;
      expect([b.maxPerDay, b.runSwipes, b.quietSec, b.pauseMinutes], [120, 15, 40, 7]);
      expect(ScrollRule.parse('nope'), isNull);
      expect(ScrollRule.parse(null), isNull);
    });
  });

  group('habits', () {
    test('peak hours, late night and the usual day', () {
      final hourly = List.filled(24, 0)..[23] = 600000..[0] = 600000..[20] = 300000..[8] = 100000;
      final h = Habits.analyse(hourly, [90, 100, 100, 100, 0]);
      expect(h.peakHours, [0, 20, 23]);
      expect(h.lateNightShare, closeTo(1200000 / 1600000, 1e-9));
      expect(h.averageReels, 100);
      expect(h.todayAboveAverage, isFalse);
      expect(h.suggestedMaxSwipes, 80);
      expect(h.lateNightHeavy, isTrue);
    });

    test('today far above the usual is noticed, and no data gives no suggestion', () {
      expect(Habits.analyse(List.filled(24, 0), [200, 100, 100]).todayAboveAverage, isTrue);
      final none = Habits.analyse(List.filled(24, 0), []);
      expect(none.suggestedMaxSwipes, 0);
      expect(none.notes(), isEmpty);
    });
  });
}
