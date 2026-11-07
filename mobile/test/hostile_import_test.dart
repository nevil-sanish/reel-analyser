import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/data/export.dart';
import 'package:reelbrain/data/key_backup.dart';
import 'package:reelbrain/data/library_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Attack tests: a backup file is untrusted input. None of these may crash the app or leave a half-written library.
void main() {
  sqfliteFfiInit();
  late LibraryDb db;
  setUp(() async => db = await LibraryDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => db.close());

  Future<Object?> attempt(String json) async {
    try {
      await importJson(db, json);
      return null;
    } on Object catch (e) {
      return e; // refused with an error the Settings screen catches: fine
    }
  }

  test('wrong shapes are refused, not crashed on', () async {
    for (final bad in ['', 'null', '42', '"text"', '{}', '{"reels":5}', '{"reels":[1,2]}', '{"reels":[{}]}', '{"reels":[{"url":null}]}', '[[]]', '{"reels":[{"url":["x"]}]}']) {
      final e = await attempt(bad);
      expect(e == null || e is Exception || e is Error, isTrue, reason: bad);
    }
    expect(await db.reels(), isEmpty);
  });

  test('hostile text is stored as plain text and never executed', () async {
    const evil = "'; DROP TABLE reels;-- <script>alert(1)</script> \u0000 \u202e";
    await importJson(db, jsonEncode({'reels': [{'url': 'https://www.instagram.com/reel/abc/', 'title': evil, 'summary': evil, 'keyPoints': [evil], 'tags': [evil]}]}));
    final r = (await db.reels()).single;
    expect(r.title, evil);
    expect((await db.reels(query: "'; DROP")).length, 1); // the search is parameterised too
    expect(await db.reels(), hasLength(1)); // the table is still there
  });

  test('a note whose link is not an Instagram or YouTube link is kept but never opened', () async {
    await importJson(db, jsonEncode({'reels': [{'url': 'javascript:alert(1)', 'title': 'x'}, {'url': 'file:///etc/passwd', 'title': 'y'}]}));
    for (final r in await db.reels()) {
      expect(isReelLink(r.url), isFalse);
    }
  });

  test('a very large file and a deeply nested one do not hang or crash', () async {
    final big = jsonEncode({'reels': [{'url': 'https://youtu.be/abcdefgh', 'title': 'A' * 5000000}]});
    expect(await attempt(big), isNull);
    final deep = '${'[' * 200000}${']' * 200000}';
    final e = await attempt(deep);
    expect(e == null || e is Error || e is Exception, isTrue);
  });

  test('a damaged or forged encrypted-keys block never yields keys', () async {
    final blob = await KeyBackup.encrypt({'gemini': ['k']}, 'a-long-passphrase');
    for (final forged in [
      {...blob, 'iter': 1},
      {...blob, 'iter': 2000000000}, // would grind the phone for hours
      {...blob, 'iter': -5},
      {...blob, 'salt': '!!!'},
      {...blob, 'nonce': ''},
      {...blob, 'mac': base64Encode(List.filled(16, 0))},
      <String, Object?>{},
    ]) {
      await expectLater(KeyBackup.decrypt(forged, 'a-long-passphrase'), throwsA(isA<WrongPassphrase>()));
    }
  });

  test('an imported note cannot point at a file outside the photos folder or at a non-web link', () async {
    final urls = [
      'photo:/data/user/0/app.reelbrain/databases/reel_flags.json',
      'photo:/data/user/0/app.reelbrain/files/photos/../../databases/reel_flags.json',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'intent://x#Intent;end',
    ];
    final (notes, _) = await importJson(db, jsonEncode({'reels': [for (final u in urls) {'url': u, 'title': 't'}]}));
    expect(notes, 0);
    final (ok, _) = await importJson(db, jsonEncode({'reels': [{'url': 'photo:/data/user/0/app.reelbrain/files/photos/1.jpg', 'title': 't'}]}));
    expect(ok, 1);
  });
}
