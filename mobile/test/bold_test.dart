import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/chat_screen.dart';

void main() {
  test('**bold** shows as bold, other text is untouched', () {
    final s = boldSpans('a **b** c * d **e**');
    expect(s.toPlainText(), 'a b c * d e');
    expect((s.children!.whereType<TextSpan>().where((t) => t.style?.fontWeight == FontWeight.w700)).length, 2);
  });
  test('text without marks is unchanged', () {
    expect(boldSpans('plain ** text').toPlainText(), 'plain ** text');
  });
}
