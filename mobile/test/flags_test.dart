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
}
