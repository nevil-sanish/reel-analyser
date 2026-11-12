import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/native/counter_bridge.dart';
import 'package:reelbrain/ui/library_screen.dart';

void main() {
  const day = 24 * 3600 * 1000;
  final now = 100 * day;
  PendingItem f(int id, int age) => PendingItem(id: id, url: 'https://www.linkedin.com/posts/x-$id', app: 'linkedin', createdAt: now - age, status: 'failed');

  test('a failed row keeps its reason from the queue', () {
    final p = PendingItem.fromMap({'id': 3, 'url': 'u', 'status': 'failed', 'title': 'LinkedIn did not show this post'});
    expect(p.title, 'LinkedIn did not show this post');
    expect(PendingItem.fromMap({'id': 4, 'url': 'u'}).title, '');
  });

  test('recent failures: newest first, last 7 days only, not ones the open app already shows', () {
    final out = recentFailures([f(1, 8 * day), f(2, 2 * day), f(3, 1000), f(4, 500)], {4}, now);
    expect(out.map((p) => p.id), [3, 2]);
  });
}
