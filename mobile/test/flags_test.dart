import 'dart:io';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelbrain/data/key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('encryption', () {
    var broken = false;
    setUp(() {
      broken = false;
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('reelbot/counter'), (c) async {
        if (broken) throw PlatformException(code: 'keystore');
        final t = c.arguments['text'] as String;
        return c.method == 'seal' ? base64.encode(utf8.encode(t).reversed.toList()) : utf8.decode(base64.decode(t).reversed.toList());
      });
    });
    tearDown(() => TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('reelbot/counter'), null));

    String fileText() => File(p.join(dir.path, 'reel_flags.json')).readAsStringSync();

    test('a saved key is encrypted in the file and read back', () async {
      await KeyStore().setGroq('gsk_secret_value');
      expect(fileText(), isNot(contains('gsk_secret_value')));
      expect(fileText(), contains('enc1:'));
      expect(await KeyStore().groq, 'gsk_secret_value');
    });

    test('flags stay readable and unencrypted', () async {
      await KeyStore().setIntroSeen();
      expect(fileText(), contains('"intro_seen":"1"'));
    });

    test('a key saved before encryption existed is encrypted the first time it is read', () async {
      File(p.join(dir.path, 'reel_flags.json')).writeAsStringSync('{"secure_migrated":"1","openai":"sk-old"}');
      expect(await KeyStore().openai, 'sk-old');
      expect(fileText(), isNot(contains('sk-old')));
      expect(await KeyStore().openai, 'sk-old');
    });

    test('when the Keystore cannot encrypt, the key is still saved', () async {
      broken = true;
      await KeyStore().setClaude('sk-ant-x');
      expect(await KeyStore().claude, 'sk-ant-x');
    });

    test('when the Keystore cannot open a sealed key, it reads as not set instead of crashing', () async {
      await KeyStore().setApify('apify_x');
      broken = true;
      expect(await KeyStore().apify, isNull);
    });
  });
}
