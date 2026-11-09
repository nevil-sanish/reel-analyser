import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/full_bridge.dart';
import 'package:reelbrain/full/insights_screen.dart';

void main() {
  test('T-UI-03 insights: empty days filled, weekday averages, hour labels', () {
    final now = DateTime(2026, 11, 6); // a Friday
    final days = fillDays([const DayTotal('2026-11-04', {'instagram': 3}, 600000, 0)], 7, now);
    expect(days.map((d) => d.date), ['2026-10-31', '2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06']);
    expect(days[4].reels, 3);
    expect(days.last.reels, 0);
    final w = weekdayMinutes(days);
    expect(w[2], 10); // Wednesday 4 Nov: 10 minutes
    expect(w[4], 0);
    expect([hourLabel(0), hourLabel(9), hourLabel(12), hourLabel(21)], ['12a', '9a', '12p', '9p']);
    final hours = List.filled(24, (0, 0));
    hours[1] = (5, 60000);
    hours[20] = (3, 30000);
    expect([for (final b in timeBlocks(hours)) (b.$1, b.$3)], [('Night', 5), ('Morning', 0), ('Afternoon', 0), ('Evening', 3)]);
  });
}
