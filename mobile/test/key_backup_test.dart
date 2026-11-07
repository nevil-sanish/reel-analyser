import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
