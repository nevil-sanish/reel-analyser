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

  group('matching a new note to folders (no AI)', () {
    const cooking = Folder(1, 'Cooking'), ml = Folder(2, 'Machine Learning'), fit = Folder(3, 'Fitness');

    test('every word of the folder name must be in the note', () {
      expect(matchFolders(note('a', 'Five minute pasta', tags: ['cooking', 'pasta']), [cooking, ml, fit]), {1});
      expect(matchFolders(note('b', 'Intro to machine learning'), [cooking, ml, fit]), {2});
      expect(matchFolders(note('c', 'Learning to juggle'), [cooking, ml, fit]), isEmpty, reason: 'only half of "Machine Learning"');
      expect(matchFolders(note('d', 'A sunset'), [cooking, ml, fit]), isEmpty);
    });

    test('simple plurals and -ing forms match', () {
      expect(matchFolders(note('a', 'Cook rice right'), [cooking]), {1});
      expect(matchFolders(note('b', 'Three recipes'), [const Folder(9, 'Recipe')]), {9});
    });

    test('a note that fits two folders goes in both', () {
      expect(matchFolders(note('a', 'Cooking for fitness', tags: ['cooking', 'fitness']), [cooking, fit]), {1, 3});
    });
  });

  group('organize answers', () {
    final folders = [const Folder(1, 'Cooking'), const Folder(2, 'Claude AI')];
    final notes = [
      for (var i = 0; i < 9; i++) note('u$i', 'note $i'),
    ];

    test('a note goes in every one of their folders named, any case; unknown names and numbers are ignored', () {
      final p = OrganizePlan();
      expect(p.addAnswer('Sure! {"assign": {"0": ["cooking", "CLAUDE AI"], "1": "Nope", "2": null, "3": "Cooking", "99": ["Cooking"]}, "suggest": []}', folders, notes), isTrue);
      expect(p.assign, {'u0': {1, 2}, 'u3': {1}});
    });

    test('a new folder needs $minSuggested notes, never "All", never the same topic as theirs', () {
      final p = OrganizePlan()
        ..addAnswer(
            '{"assign": {}, "suggest": ['
            '{"name": "Python", "notes": [1, 2, 3]}, {"name": "Solo", "notes": [4]}, {"name": "All", "notes": [5, 6, 7]},'
            '{"name": "COOKING", "notes": [5, 6, 7]}, {"name": "Claude Anthropic AI", "notes": [4, 5, 6, 7]}]}',
            folders,
            notes);
      expect([for (final (n, u) in p.suggestions(folders, {})) '$n:${u.join(',')}'], ['Python:u1,u2,u3']);
    });

    test('two suggestions for one topic: only the bigger is kept', () {
      final p = OrganizePlan()
        ..addAnswer('{"assign": {}, "suggest": [{"name": "AI Agents", "notes": [0, 1, 2, 3]}, {"name": "Agents AI tools", "notes": [5, 6, 7]}]}', folders, notes);
      expect([for (final (n, _) in p.suggestions(folders, {})) n], ['AI Agents']);
    });

    test('a suggestion whose notes already sit together in one folder is dropped', () {
      final p = OrganizePlan()
        ..addAnswer('{"assign": {"4": ["Claude AI"]}, "suggest": [{"name": "Prompting", "notes": [3, 4, 5, 6]}, {"name": "Travel", "notes": [0, 1, 2]}]}', folders, notes);
      final grouped = {'u3': {2}, 'u5': {2}};
      expect([for (final (n, _) in p.suggestions(folders, grouped)) n], ['Travel'], reason: '3 of 4 Prompting notes are in Claude AI');
    });

    test('a suggestion mostly inside a bigger one is dropped', () {
      final p = OrganizePlan()
        ..addAnswer('{"assign": {}, "suggest": [{"name": "Python", "notes": [0, 1, 2, 3, 4]}, {"name": "Django", "notes": [0, 1, 2]}]}', folders, notes);
      expect([for (final (n, _) in p.suggestions(folders, {})) n], ['Python']);
    });

    test('suggestions from several chunks merge by name', () {
      final p = OrganizePlan()
        ..addAnswer('{"assign": {}, "suggest": [{"name": "Python", "notes": [0, 1]}]}', folders, notes.sublist(0, 4))
        ..addAnswer('{"assign": {}, "suggest": [{"name": "python", "notes": [0]}]}', folders, notes.sublist(4));
      expect([for (final (n, u) in p.suggestions(folders, {})) '$n:${u.join(',')}'], ['Python:u0,u1,u4']);
    });

    test('same topic by name', () {
      expect(sameTopic('Claude AI', 'Claude Anthropic AI'), isTrue);
      expect(sameTopic('Claude AI', 'ai claude'), isTrue);
      expect(sameTopic('AI', 'Claude AI'), isFalse);
      expect(sameTopic('Cooking', 'Fitness'), isFalse);
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
      expect(r, contains('Their folders: Cooking, Claude AI'));
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
      await db.addToFolders({'u1': {a}});
      await db.saveFolderChat(a, ['q a', 'answer a'], 1);
      await db.saveFolderChat(b, ['q b', 'answer b'], 1);
      await db.saveFolderChat(0, ['q all', 'answer all'], 1);
      expect(await db.folderChat(a), ['q a', 'answer a']);
      expect(await db.folderChat(b), ['q b', 'answer b']);
      await db.deleteFolder(a);
      expect(await db.folderChat(a), isEmpty);
      expect(await db.folderChat(b), ['q b', 'answer b']);
      expect(await db.folderChat(0), ['q all', 'answer all']);
      expect(await db.foldersOf(), isEmpty);
      expect((await db.reels()).single.url, 'u1');
    });

    test('re-saving a note keeps its folder; erase clears everything', () async {
      final a = (await db.addFolder('A', 1))!;
      await db.saveReel(note('u1', 't'));
      await db.addToFolders({'u1': {a}});
      await db.saveReel(note('u1', 'renamed'));
      expect(await db.foldersOf(), {'u1': {a}});
      await db.eraseAll();
      expect(await db.folders(), isEmpty);
      expect(await db.foldersOf(), isEmpty);
    });

    test('a note in several folders; taking it out of one keeps the others', () async {
      final a = (await db.addFolder('A', 1))!, b = (await db.addFolder('B', 2))!;
      await db.addToFolders({'u1': {a, b}, 'u2': {a}});
      await db.addToFolders({'u1': {a}});
      expect(await db.foldersOf(), {'u1': {a, b}, 'u2': {a}});
      await db.removeFromFolder(['u1', 'u2'], a);
      expect(await db.foldersOf(), {'u1': {b}});
      await db.deleteFolder(b);
      expect(await db.foldersOf(), isEmpty);
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

  test('a version 8 library keeps each note in its folder after the upgrade to several folders', () async {
    final dir = await Directory.systemTemp.createTemp('lib8');
    final path = '${dir.path}/reel_brain.db';
    final fresh = await LibraryDb.open(factory: databaseFactoryFfi, path: path);
    final a = (await fresh.addFolder('Cooking', 1))!;
    await fresh.saveReel(note('u1', 'Pasta'));
    await fresh.close();
    // Turn it back into a version 8 file: the one-folder table instead of note_folders.
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.execute('DROP TABLE note_folders');
    await raw.execute('CREATE TABLE folder_items (url TEXT PRIMARY KEY, folderId INTEGER NOT NULL)');
    await raw.insert('folder_items', {'url': 'u1', 'folderId': a});
    await raw.setVersion(8);
    await raw.close();
    final db = await LibraryDb.open(factory: databaseFactoryFfi, path: path);
    expect(await db.foldersOf(), {'u1': {a}});
    await db.close();
    await dir.delete(recursive: true);
  });
}
