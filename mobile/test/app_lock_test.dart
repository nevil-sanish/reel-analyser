import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/data/app_lock.dart';

class _Mem implements LockStorage {
  final m = <String, String>{};
  @override
  Future<String?> readLock(String k) async => m[k];
  @override
  Future<void> writeLock(String k, String? v) async => v == null || v.isEmpty ? m.remove(k) : m[k] = v;
}

void main() {
  test('only 4 to 8 digits are allowed', () {
    expect(AppLock.check('1234'), isNull);
    expect(AppLock.check('12345678'), isNull);
    expect(AppLock.check('123'), isNotNull);
    expect(AppLock.check('123456789'), isNotNull);
    expect(AppLock.check('12a4'), isNotNull);
  });

  test('set, verify right and wrong, remove; the passcode itself is never stored', () async {
    final s = _Mem();
    final l = AppLock(s);
    expect(await l.enabled, isFalse);
    await l.set('4821');
    expect(await l.enabled, isTrue);
    expect(s.m.values.join(), isNot(contains('4821')));
    expect(await l.verify('4821'), isTrue);
    expect(await l.verify('0000'), isFalse);
    await l.remove();
    expect(await l.enabled, isFalse);
  });

  test('five wrong tries start a wait that grows, and the right one is refused during it', () async {
    var t = DateTime(2026, 11, 15, 12);
    final l = AppLock(_Mem(), now: () => t);
    await l.set('4821');
    for (var i = 0; i < 4; i++) {
      expect(await l.verify('1111'), isFalse);
      expect(await l.waitLeft(), isNull);
    }
    expect(await l.verify('1111'), isFalse); // the 5th
    expect((await l.waitLeft())!.inSeconds, inInclusiveRange(29, 30));
    expect(await l.verify('4821'), isFalse, reason: 'refused while waiting');
    t = t.add(const Duration(seconds: 31));
    expect(await l.waitLeft(), isNull);
    expect(await l.verify('1111'), isFalse); // the 6th: wait doubles
    expect((await l.waitLeft())!.inSeconds, inInclusiveRange(59, 60));
    t = t.add(const Duration(seconds: 61));
    expect(await l.verify('4821'), isTrue);
    expect(await l.waitLeft(), isNull, reason: 'a right passcode clears the count');
  });
}
