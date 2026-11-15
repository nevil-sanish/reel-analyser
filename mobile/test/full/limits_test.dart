import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/full/limit_bar.dart';
import 'package:reelbrain/full/limits.dart';

void main() {
  test('hostOf reads what people type', () {
    expect(hostOf('https://www.Example.com:8080/a?b=1'), 'example.com');
    expect(hostOf('example.com/a'), 'example.com');
    expect(hostOf('m.youtube.com'), 'm.youtube.com');
    expect(hostOf('not a site'), isNull);
    expect(hostOf('localhost'), isNull);
    expect(hostOf(''), isNull);
  });

  test('isStricter: nothing may be loosened or dropped', () {
    const a = LimitItem('app', 'com.a', 'A', 30);
    expect(isStricter([a], [a.withLimit(20)]), isTrue);
    expect(isStricter([a], [a, const LimitItem('site', 'x.com', 'x.com', 5)]), isTrue);
    expect(isStricter([a], [a.withLimit(31)]), isFalse);
    expect(isStricter([a], [const LimitItem('site', 'x.com', 'x.com', 5)]), isFalse);
    expect(isStricter(const [], [a]), isTrue);
  });

  test('signature ignores order; encode round trips', () {
    const a = LimitItem('app', 'com.a', 'A', 30);
    const b = LimitItem('site', 'x.com', 'x.com', 5);
    expect(limitsSignature([a, b]), limitsSignature([b, a]));
    expect(limitsSignature([a]), isNot(limitsSignature([a.withLimit(31)])));
    final back = LimitItem.parse(LimitItem.encode([a, b]));
    expect(back.map((i) => i.key), ['app:com.a', 'site:x.com']);
    expect(LimitItem.parse('garbage'), isEmpty);
  });

  test('progress fraction stays between 0 and 1', () {
    expect(limitFraction(0, 30), 0);
    expect(limitFraction(15 * 60000, 30), 0.5);
    expect(limitFraction(99 * 60000, 30), 1);
    expect(limitFraction(1, 0), 1);
    expect(minutesText(60), '1 h');
    expect(minutesText(90), '1 h 30 min');
    expect(minutesText(45), '45 min');
  });
}
