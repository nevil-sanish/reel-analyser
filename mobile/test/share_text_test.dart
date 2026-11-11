import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';

void main() {
  test('the share text has the analysis and the link, not the transcript', () {
    const r = Reel(
      url: 'https://www.instagram.com/reel/abc/',
      app: 'instagram',
      title: 'Five minute pasta',
      summary: 'A quick pasta.',
      keyPoints: ['Boil water'],
      tags: [],
      overview: ['Fast dinner'],
      mentions: ['Garlic'],
      author: 'chef',
      caption: '',
      transcript: 'secret words',
      onScreenText: '',
      analysis: 'done',
      step: 0,
      savedAt: 0,
    );
    final s = r.toShareText();
    expect(s, startsWith('Five minute pasta\nhttps://www.instagram.com/reel/abc/'));
    expect(s, contains('• Fast dinner'));
    expect(s, contains('• Boil water'));
    expect(s, contains('Mentioned: Garlic'));
    expect(s, isNot(contains('secret words')));
  });
}
