import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelbrain/data/key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('flags');
    databaseFactory = databaseFactoryFfi;
    await databaseFactoryFfi.setDatabasesPath(dir.path);
  });
  tearDown(() => dir.delete(recursive: true));

  test('intro and terms flags survive a restart without touching secure storage', () async {
    expect(await KeyStore().flag('intro_seen'), isFalse);
    await KeyStore().setIntroSeen();
    await KeyStore().setFlag('legal_v1');
    expect(await KeyStore().introSeen, isTrue);
    expect(await KeyStore().flag('legal_v1'), isTrue);
    await KeyStore().setFlagTo('dark', true);
    await KeyStore().setFlagTo('dark', false);
    expect(await KeyStore().flag('dark'), isFalse);
    expect(File(p.join(dir.path, 'reel_flags.json')).existsSync(), isTrue);
  });

  test('API keys are read back from the file when the Keystore is empty or broken', () async {
    final k = KeyStore();
    await k.setOpenai('sk-test-1');
    await k.setGeminiKeys(['a', ' b ', '']);
    expect(await KeyStore().openai, 'sk-test-1');
    expect(await KeyStore().geminiKeys, ['a', 'b']);
    await k.setOpenai('');
    expect(await KeyStore().openai, isNull);
  });

  test('quick writes in a row all land', () async {
    final k = KeyStore();
    await Future.wait([for (var i = 0; i < 20; i++) k.setFlag('f$i')]);
    for (var i = 0; i < 20; i++) {
      expect(await k.flag('f$i'), isTrue);
    }
  });

  test('a damaged file reads as empty instead of crashing', () async {
    File(p.join(dir.path, 'reel_flags.json')).writeAsStringSync('{not json');
    expect(await KeyStore().flag('intro_seen'), isFalse);
    await KeyStore().setIntroSeen();
    expect(await KeyStore().introSeen, isTrue);
  });
}
