import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/data/auto_backup.dart';

void main() {
  test('one file per day, named with the date', () {
    expect(AutoBackup.fileName(DateTime(2026, 11, 29, 0, 0, 3)), 'backup-2026-11-29.json');
    expect(AutoBackup.fileName(DateTime(2026, 1, 5, 23, 59)), 'backup-2026-01-05.json');
  });

  test('the next run is the coming midnight, across months and years', () {
    expect(AutoBackup.nextMidnight(DateTime(2026, 11, 28, 18, 5)), DateTime(2026, 11, 29));
    expect(AutoBackup.nextMidnight(DateTime(2026, 11, 30, 0, 0, 1)), DateTime(2026, 12, 1));
    expect(AutoBackup.nextMidnight(DateTime(2026, 12, 31, 23, 0)), DateTime(2027, 1, 1));
  });

  test('due once a day', () {
    final now = DateTime(2026, 11, 29, 0, 1);
    expect(AutoBackup.due(null, now), isTrue);
    expect(AutoBackup.due('2026-11-28', now), isTrue);
    expect(AutoBackup.due('2026-11-29', now), isFalse);
  });
}
