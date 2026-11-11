import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/data/folders.dart';
import 'package:reelbrain/data/library_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Reel note(String url, String title, {List<String> tags = const [], List<String> overview = const []}) =>
    Reel(url: url, app: 'instagram', title: title, summary: '', tags: tags, overview: overview, savedAt: 1);

void main() {
  sqfliteFfiInit();

  group('matching a new note to a folder (no AI)', () {
    const cooking = Folder(1, 'Cooking'), ml = Folder(2, 'Machine Learning'), fit = Folder(3, 'Fitness');

    test('every word of the folder name must be in the note', () {
      expect(matchFolder(note('a', 'Five minute pasta', tags: ['cooking', 'pasta']), [cooking, ml, fit]), 1);
      expect(matchFolder(note('b', 'Intro to machine learning'), [cooking, ml, fit]), 2);
      expect(matchFolder(note('c', 'Learning to juggle'), [cooking, ml, fit]), isNull, reason: 'only half of "Machine Learning"');
      expect(matchFolder(note('d', 'A sunset'), [cooking, ml, fit]), isNull);
    });

    test('simple plurals and -ing forms match', () {
      expect(matchFolder(note('a', 'Cook rice right'), [cooking]), 1);
      expect(matchFolder(note('b', 'Three recipes'), [const Folder(9, 'Recipe')]), 9);
    });

    test('a tie leaves the note in All', () {
      expect(matchFolder(note('a', 'Cooking for fitness', tags: ['cooking', 'fitness']), [cooking, fit]), isNull);
    });
  });

  group('organize answers', () {
    final folders = [const Folder(1, 'Cooking')];
    final notes = [
      for (var i = 0; i < 8; i++) note('u$i', 'note $i'),
    ];

    test('their folders by name, any case; unknown names and numbers are ignored', () {
      final p = OrganizePlan();
      expect(p.addAnswer('Sure! {"assign": {"0": "cooking", "1": "Nope", "2": null, "99": "Cooking"}, "suggest": []}', folders, notes), isTrue);
      expect(p.assign, {'u0': 1, 'u1': null, 'u2': null});
    });

    test('a new folder needs $minSuggested notes, never "All", never a name they already have', () {
      final p = OrganizePlan()
        ..addAnswer(
            '{"assign": {"0": "Cooking"}, "suggest": ['
            '{"name": "Python", "notes": [1, 2, 3]}, {"name": "Solo", "notes": [4]}, {"name": "All", "notes": [5, 6, 7]},'
            '{"name": "COOKING", "notes": [5, 6, 7]}, {"name": "Travel", "notes": [0, 5, 6]}]}',
            folders,
            notes);
      expect([for (final (n, u) in p.suggestions()) '$n:${u.join(',')}'], ['Python:u1,u2,u3'],
          reason: 'Travel loses u0 (already in Cooking) and falls below $minSuggested');
    });

    test('suggestions from several chunks merge by name', () {
      final p = OrganizePlan()
        ..addAnswer('{"assign": {}, "suggest": [{"name": "Python", "notes": [0, 1]}]}', folders, notes.sublist(0, 4))
        ..addAnswer('{"assign": {}, "suggest": [{"name": "python", "notes": [0]}]}', folders, notes.sublist(4));
      expect([for (final (n, u) in p.suggestions()) '$n:${u.join(',')}'], ['Python:u0,u1,u4']);
    });

    test('garbage is not usable', () {
      expect(OrganizePlan().addAnswer('no json here', folders, notes), isFalse);
      expect(OrganizePlan().addAnswer('{"assign": [1, 2]}', folders, notes), isTrue, reason: 'a wrong shape is ignored, not fatal');
    });

    test('the request carries titles and tags, never links or transcripts', () {
      final r = organizeRequest(folders, [
        Reel(url: 'https://secret.link/x', app: 'instagram', title: 'Pasta', summary: '', tags: const ['food'], transcript: 'hidden words', savedAt: 1),
      ]);
      expect(r, contains('0. Pasta [food]'));
      expect(r, contains('Their folders: Cooking'));
      expect(r, isNot(contains('secret.link')));
      expect(r, isNot(contains('hidden words')));
    });
  });

  group('folders in the database', () {
    late LibraryDb db;
    setUp(() async => db = await LibraryDb.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    tearDown(() => db.close());

    test('names are unique in any case, and "All" is reserved', () async {
      expect(await db.addFolder('Cooking', 1), isNotNull);
      expect(await db.addFolder('cooking', 2), isNull);
      expect(await db.addFolder('All', 3), isNull);
      expect(await db.addFolder('  ', 4), isNull);
    });

    test('deleting a folder keeps its notes and removes its chat; each folder has its own thread', () async {
      final a = (await db.addFolder('A', 1))!, b = (await db.addFolder('B', 2))!;
      await db.saveReel(note('u1', 't'));
      await db.setFolders({'u1': a});
      await db.saveFolderChat(a, ['q a', 'answer a'], 1);
      await db.saveFolderChat(b, ['q b', 'answer b'], 1);
      await db.saveFolderChat(0, ['q all', 'answer all'], 1);
      expect(await db.folderChat(a), ['q a', 'answer a']);
      expect(await db.folderChat(b), ['q b', 'answer b']);
      await db.deleteFolder(a);
      expect(await db.folderChat(a), isEmpty);
      expect(await db.folderChat(b), ['q b', 'answer b']);
      expect(await db.folderChat(0), ['q all', 'answer all']);
      expect(await db.folderOf(), isEmpty);
      expect((await db.reels()).single.url, 'u1');
    });

    test('re-saving a note keeps its folder; erase clears everything', () async {
      final a = (await db.addFolder('A', 1))!;
      await db.saveReel(note('u1', 't'));
      await db.setFolders({'u1': a});
      await db.saveReel(note('u1', 'renamed'));
      expect(await db.folderOf(), {'u1': a});
      await db.eraseAll();
      expect(await db.folders(), isEmpty);
      expect(await db.folderOf(), isEmpty);
    });
  });

  test('a version 7 library with notes upgrades to folders and keeps its notes', () async {
    final dir = await Directory.systemTemp.createTemp('lib7');
    final path = '${dir.path}/reel_brain.db';
    final v7 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE reels (url TEXT PRIMARY KEY, app TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '',
              summary TEXT NOT NULL DEFAULT '', keyPoints TEXT NOT NULL DEFAULT '[]', tags TEXT NOT NULL DEFAULT '[]',
              author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '', analysis TEXT NOT NULL DEFAULT 'done',
              step INTEGER NOT NULL DEFAULT 0, savedAt INTEGER NOT NULL, seenAt INTEGER NOT NULL DEFAULT 0,
              archived INTEGER NOT NULL DEFAULT 0, overview TEXT NOT NULL DEFAULT '[]', mentions TEXT NOT NULL DEFAULT '[]',
              transcript TEXT NOT NULL DEFAULT '', onScreenText TEXT NOT NULL DEFAULT '')''');
            await d.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v INTEGER NOT NULL)');
            await d.execute('CREATE TABLE chats (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, updatedAt INTEGER NOT NULL, turns TEXT NOT NULL)');
            await d.execute('CREATE TABLE note_chats (url TEXT PRIMARY KEY, updatedAt INTEGER NOT NULL, turns TEXT NOT NULL)');
            await d.insert('reels', {'url': 'old', 'title': 'Old note', 'savedAt': 5});
          },
        ));
    await v7.close();
    final db = await LibraryDb.open(factory: databaseFactoryFfi, path: path);
    expect((await db.reels()).single.title, 'Old note');
    expect(await db.folders(), isEmpty);
    expect(await db.addFolder('New', 1), isNotNull);
    await db.close();
    await dir.delete(recursive: true);
  });
}
