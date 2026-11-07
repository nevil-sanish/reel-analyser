import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/chat_screen.dart';

void main() {
  test('**bold** shows as bold, other text is untouched', () {
    final s = boldSpans('a **b** c * d **e**');
    expect(s.toPlainText(), 'a b c * d e');
    expect((s.children!.whereType<TextSpan>().where((t) => t.style?.fontWeight == FontWeight.w700)).length, 2);
  });
  test('*italic* shows as italic; a lone asterisk or a bullet star is left alone', () {
    final s = boldSpans('*(Source: "x")* and * bullet and a*b');
    expect(s.toPlainText(), '(Source: "x") and * bullet and a*b');
    expect(s.children!.whereType<TextSpan>().where((t) => t.style?.fontStyle == FontStyle.italic).length, 1);
  });

  test('text without marks is unchanged', () {
    expect(boldSpans('plain ** text').toPlainText(), 'plain ** text');
  });
}
