import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/reel_screen.dart';

List<(String, bool)> parts(String s) {
  final t = boldSpans(s);
  if (t.children == null) return [(t.text!, false)];
  return [for (final c in t.children!.cast<TextSpan>()) (c.text!, c.style?.fontWeight == FontWeight.w700)];
}

void main() {
  test('key words between ** are bold and the asterisks are hidden', () {
    expect(parts('**Top 5:** Audit (27) · Research (23)'), [('Top 5:', true), (' Audit (27) · Research (23)', false)]);
  });

  test('a line without markers, or with one unpaired, is shown as it is', () {
    expect(parts('Plain line'), [('Plain line', false)]);
    expect(parts('5 ** 2 is 25'), [('5 ** 2 is 25', false)]);
    expect(parts('**a** and **b'), [('a', true), (' and ', false), ('**b', false)]);
  });
}
