import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';

void main() {
  test('T-UI-02 saved labels', () {
    final now = DateTime(2026, 11, 6, 14, 0);
    int at(DateTime t) => t.millisecondsSinceEpoch;
    expect(savedAgo(at(DateTime(2026, 11, 6, 13, 59, 40)), now), 'just now');
    expect(savedAgo(at(DateTime(2026, 11, 6, 13, 30)), now), '30m ago');
    expect(savedAgo(at(DateTime(2026, 11, 6, 2, 0)), now), '12h ago');
    expect(savedAgo(at(DateTime(2026, 11, 5, 23, 0)), now), 'yesterday');
    expect(savedAgo(at(DateTime(2026, 11, 3, 9, 0)), now), '3 Nov');
    expect(savedAgo(at(DateTime(2025, 12, 31)), now), '31 Dec 2025');
    expect(savedOn(at(DateTime(2026, 11, 6, 9, 5))), 'Saved 6 Nov 2026, 09:05');
  });

  test('T-UI-04 library kinds', () {
    Reel r(String app, String url) => Reel(url: url, app: app, title: '', summary: '', savedAt: 0);
    expect(r('instagram', 'https://www.instagram.com/reel/abc/').kind, 'reel');
    expect(r('instagram', 'https://www.instagram.com/p/abc/').kind, 'post');
    expect(r('youtube', 'https://www.youtube.com/shorts/x').kind, 'short');
    expect(r('photo', 'photo:/x.jpg').kind, 'photo');
  });
}
