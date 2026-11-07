import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/data/export.dart';
import 'package:reelbrain/data/key_backup.dart';

void main() {
  const keys = {
    'gemini': ['AIzaSyFAKE-ONE', 'AIzaSyFAKE-TWO'],
    'openai': 'sk-fake',
    'claude': null,
    'groq': null,
    'apify': null,
  };

  test('keys round-trip through the passphrase; the file never holds them in clear', () async {
    final blob = await KeyBackup.encrypt(keys, 'correct horse battery');
    expect(jsonEncode(blob), isNot(contains('AIzaSy')));
    expect(jsonEncode(blob), isNot(contains('sk-fake')));
    final back = await KeyBackup.decrypt(blob, 'correct horse battery');
    expect(back['gemini'], ['AIzaSyFAKE-ONE', 'AIzaSyFAKE-TWO']);
    expect(back['openai'], 'sk-fake');
  });

  test('a wrong passphrase or a damaged file is refused', () async {
    final blob = await KeyBackup.encrypt(keys, 'correct horse battery');
    await expectLater(KeyBackup.decrypt(blob, 'wrong passphrase'), throwsA(isA<WrongPassphrase>()));
    final bad = {...blob, 'ct': base64Encode(List.filled(40, 1))};
    await expectLater(KeyBackup.decrypt(bad, 'correct horse battery'), throwsA(isA<WrongPassphrase>()));
  });

  test('the encrypted block rides in library.json and old files without one still import', () async {
    final blob = await KeyBackup.encrypt(keys, 'correct horse battery');
    expect(encryptedKeysOf(exportJson(const [], const [], blob)), isNotNull);
    expect(encryptedKeysOf(exportJson(const [])), isNull);
    expect(encryptedKeysOf('[]'), isNull);
  });

  test('only Instagram and YouTube https links are opened', () {
    expect(isReelLink('https://www.instagram.com/reel/abc/'), isTrue);
    expect(isReelLink('https://youtu.be/abcdefg'), isTrue);
    expect(isReelLink('https://www.youtube.com/shorts/abcdefg'), isTrue);
    for (final bad in ['http://www.instagram.com/reel/a/', 'https://evil.com/?u=instagram.com', 'https://instagram.com.evil.com/x', 'javascript:alert(1)', 'file:///etc/passwd', 'intent://x#Intent;end', 'photo:/data/x.jpg']) {
      expect(isReelLink(bad), isFalse, reason: bad);
    }
  });
}
