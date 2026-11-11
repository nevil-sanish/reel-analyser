import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models.dart';

/// `reel_brain.db`, owned by Dart (PLAN §4.7). Kotlin never opens it.
class LibraryDb {
  final Database _db;
  LibraryDb._(this._db);

  static Future<LibraryDb> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'reel_brain.db'),
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE reels (
            url TEXT PRIMARY KEY, app TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '', keyPoints TEXT NOT NULL DEFAULT '[]', tags TEXT NOT NULL DEFAULT '[]',
            author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
            analysis TEXT NOT NULL DEFAULT 'done', step INTEGER NOT NULL DEFAULT 0, savedAt INTEGER NOT NULL)''');
          await db.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v INTEGER NOT NULL)');
          await db.insert('meta', {'k': 'processing_until', 'v': 0});
          await _v2(db);
          await _v3(db);
          await _v4(db);
          await _v5(db);
          await _v6(db);
          await _v7(db);
          await _v8(db);
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _v2(db);
          if (from < 3) await _v3(db);
          if (from < 4) await _v4(db);
          if (from < 5) await _v5(db);
          if (from < 6) await _v6(db);
          if (from < 7) await _v7(db);
          if (from < 8) await _v8(db);
        },
      ),
    );
    return LibraryDb._(db);
  }

  /// Version 2: seen / archived. Seen notes older than 3 days move to the archive (never deleted).
  static Future<void> _v2(Database db) async {
    await db.execute('ALTER TABLE reels ADD COLUMN seenAt INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE reels ADD COLUMN archived INTEGER NOT NULL DEFAULT 0');
  }

  /// Version 3: saved chats. `turns` is a JSON list alternating question, answer.
  static Future<void> _v3(Database db) => db.execute('''CREATE TABLE chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, updatedAt INTEGER NOT NULL, turns TEXT NOT NULL)''');

  /// Version 4: the overview bullets and mentions of richer notes (v0.9.2).
  static Future<void> _v4(Database db) async {
    await db.execute("ALTER TABLE reels ADD COLUMN overview TEXT NOT NULL DEFAULT '[]'");
    await db.execute("ALTER TABLE reels ADD COLUMN mentions TEXT NOT NULL DEFAULT '[]'");
  }

  /// Version 5: the transcript and on-screen text of v0.9.6 notes.
  static Future<void> _v5(Database db) async {
    await db.execute("ALTER TABLE reels ADD COLUMN transcript TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE reels ADD COLUMN onScreenText TEXT NOT NULL DEFAULT ''");
  }

  /// Version 6: one chat thread per note. `turns` alternates question, answer, like `chats`.
  static Future<void> _v6(Database db) => db.execute(
      'CREATE TABLE note_chats (url TEXT PRIMARY KEY, updatedAt INTEGER NOT NULL, turns TEXT NOT NULL)');

  /// The chat thread of one note (empty when none yet). It holds only that note's conversation.
  Future<List<String>> noteChat(String url) async {
    final r = await _db.query('note_chats', where: 'url = ?', whereArgs: [url]);
    return r.isEmpty ? [] : [for (final t in jsonDecode(r.first['turns'] as String) as List) '$t'];
  }

  Future<void> saveNoteChat(String url, List<String> turns, int now) => _db.insert(
      'note_chats', {'url': url, 'updatedAt': now, 'turns': jsonEncode(turns)},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteNoteChat(String url) => _db.delete('note_chats', where: 'url = ?', whereArgs: [url]);

  /// Every note's thread by link, for export.
  Future<Map<String, List<String>>> noteChats() async => {
        for (final r in await _db.query('note_chats'))
          r['url'] as String: [for (final t in jsonDecode(r['turns'] as String) as List) '$t'],
      };

  /// Version 7 was daily goals (full build). Those tables now belong to `lib/full/goal_store.dart`, which creates them itself, so this
  /// build keeps the version number (a phone that already has v7 must not see it go down) and creates nothing.
  static Future<void> _v7(Database db) async {}

  /// Version 8: folders (1.2.0.0). A note is in at most one folder; `folder_items` is kept apart from `reels` so re-saving or
  /// re-analysing a note, Undo after a delete and export never touch it. Rows of deleted notes are ignored, not cleaned.
  /// `folder_chats` holds one independent thread per folder (id 0 = the All folder).
  static Future<void> _v8(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS folders (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, createdAt INTEGER NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS folder_items (url TEXT PRIMARY KEY, folderId INTEGER NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS folder_chats (folderId INTEGER PRIMARY KEY, updatedAt INTEGER NOT NULL, turns TEXT NOT NULL)');
  }

  /// Oldest first.
  Future<List<Folder>> folders() async => [
        for (final r in await _db.query('folders', orderBy: 'createdAt, id')) Folder(r['id'] as int, r['name'] as String),
      ];

  /// The new folder's id, or null when a folder of that name (any case) already exists or the name is empty or "All".
  Future<int?> addFolder(String name, int now) async {
    final n = name.trim();
    if (n.isEmpty || n.toLowerCase() == 'all') return null;
    final id = await _db.insert('folders', {'name': n, 'createdAt': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
    return id == 0 ? null : id;
  }

  /// False when another folder already has that name.
  Future<bool> renameFolder(int id, String name) async {
    final n = name.trim();
    if (n.isEmpty || n.toLowerCase() == 'all') return false;
    try {
      return await _db.update('folders', {'name': n}, where: 'id = ?', whereArgs: [id]) == 1;
    } on DatabaseException {
      return false;
    }
  }

  /// The folder and its chat go; its notes stay, in All only.
  Future<void> deleteFolder(int id) => _db.transaction((t) async {
        await t.delete('folders', where: 'id = ?', whereArgs: [id]);
        await t.delete('folder_items', where: 'folderId = ?', whereArgs: [id]);
        await t.delete('folder_chats', where: 'folderId = ?', whereArgs: [id]);
      });

  /// Note link → folder id, for every note that is in a folder.
  Future<Map<String, int>> folderOf() async => {
        for (final r in await _db.query('folder_items')) r['url'] as String: r['folderId'] as int,
      };

  /// Puts each note in its folder (null = All only), all at once.
  Future<void> setFolders(Map<String, int?> byUrl) => _db.transaction((t) async {
        for (final e in byUrl.entries) {
          if (e.value == null) {
            await t.delete('folder_items', where: 'url = ?', whereArgs: [e.key]);
          } else {
            await t.insert('folder_items', {'url': e.key, 'folderId': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });

  /// The folder's chat thread (empty when none yet).
  Future<List<String>> folderChat(int folderId) async {
    final r = await _db.query('folder_chats', where: 'folderId = ?', whereArgs: [folderId]);
    return r.isEmpty ? [] : [for (final t in jsonDecode(r.first['turns'] as String) as List) '$t'];
  }

  Future<void> saveFolderChat(int folderId, List<String> turns, int now) => turns.isEmpty
      ? _db.delete('folder_chats', where: 'folderId = ?', whereArgs: [folderId])
      : _db.insert('folder_chats', {'folderId': folderId, 'updatedAt': now, 'turns': jsonEncode(turns)},
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// The open database, for the full build's own stores.
  Database get raw => _db;

  /// Creates the chat when [id] is null; returns its id.
  Future<int> saveChat(int? id, List<String> turns, int now) async {
    final row = {'title': turns.first, 'updatedAt': now, 'turns': jsonEncode(turns)};
    if (id == null) return _db.insert('chats', row);
    await _db.update('chats', row, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  /// Newest first: (id, title, updatedAt, turns).
  Future<List<(int, String, int, List<String>)>> chats() async => [
        for (final r in await _db.query('chats', orderBy: 'updatedAt DESC'))
          (r['id'] as int, r['title'] as String, r['updatedAt'] as int, [for (final t in jsonDecode(r['turns'] as String) as List) '$t']),
      ];

  /// Undo for a deleted chat: puts it back with its id and time.
  Future<void> restoreChat((int, String, int, List<String>) c) => _db.insert(
      'chats', {'id': c.$1, 'title': c.$2, 'updatedAt': c.$3, 'turns': jsonEncode(c.$4)},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteChat(int id) => _db.delete('chats', where: 'id = ?', whereArgs: [id]);

  Future<void> markSeen(String url, int now) =>
      _db.update('reels', {'seenAt': now}, where: 'url = ? AND seenAt = 0', whereArgs: [url]);

  /// Undo for "mark read".
  Future<void> markUnseen(String url) => _db.update('reels', {'seenAt': 0}, where: 'url = ?', whereArgs: [url]);

  /// A link shared again: no new analysis, the note just comes back to the top of the library, unread
  /// (out of the archive if it was there).
  Future<void> resurface(String url, int now) =>
      _db.update('reels', {'savedAt': now, 'seenAt': 0, 'archived': 0}, where: 'url = ?', whereArgs: [url]);

  Future<void> setArchived(String url, bool archived) =>
      _db.update('reels', {'archived': archived ? 1 : 0}, where: 'url = ?', whereArgs: [url]);

  /// Seen notes saved more than 3 days ago leave the library for the archive. Unseen ones stay until read.
  Future<int> archiveOld(int now) => _db.update('reels', {'archived': 1},
      where: 'archived = 0 AND seenAt > 0 AND savedAt < ?', whereArgs: [now - const Duration(days: 3).inMilliseconds]);

  Future<void> saveReel(Reel r) => _db.insert('reels', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> has(String url) async =>
      (await _db.query('reels', columns: ['url'], where: 'url = ?', whereArgs: [url])).isNotEmpty;

  /// Newest first; [query] matches title, overview, summary, key points, mentions, tags, author and caption.
  /// [archived]: null = everything (chat, export), false = the library, true = the archive.
  Future<List<Reel>> reels({String query = '', bool? archived}) async {
    final q = query.trim();
    final where = [
      if (archived != null) 'archived = ${archived ? 1 : 0}',
      if (q.isNotEmpty)
        "(title || ' ' || overview || ' ' || summary || ' ' || keyPoints || ' ' || mentions || ' ' || tags || ' ' || author || ' ' || caption || ' ' || transcript || ' ' || onScreenText) LIKE ?",
    ];
    final rows = await _db.query('reels',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: q.isEmpty ? null : ['%$q%'], orderBy: 'savedAt DESC');
    return rows.map(Reel.fromRow).toList();
  }

  Future<void> delete(String url) => _db.delete('reels', where: 'url = ?', whereArgs: [url]);

  /// The app and the background task share one queue; whoever sets this first runs it (T-PIPE-10).
  Future<bool> tryLock(int now, {Duration hold = const Duration(seconds: 90)}) async {
    final n = await _db.rawUpdate(
        "UPDATE meta SET v = ? WHERE k = 'processing_until' AND v < ?", [now + hold.inMilliseconds, now]);
    return n == 1;
  }

  /// Which Gemini key the next reel starts with. Kept here, not in secure storage, so the background task
  /// never writes to the key store.
  Future<int> geminiTurn() async {
    final r = await _db.query('meta', where: "k = 'gemini_turn'");
    return r.isEmpty ? 0 : r.first['v'] as int;
  }

  Future<void> setGeminiTurn(int v) => _db.insert('meta', {'k': 'gemini_turn', 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Keeps the lock while a long run is still working through the queue.
  Future<void> extendLock(int now, {Duration hold = const Duration(seconds: 90)}) =>
      _db.rawUpdate("UPDATE meta SET v = ? WHERE k = 'processing_until'", [now + hold.inMilliseconds]);

  Future<void> unlock() => _db.rawUpdate("UPDATE meta SET v = 0 WHERE k = 'processing_until'");

  /// Erase all my data: every note and chat.
  Future<void> eraseAll() async {
    await _db.delete('reels');
    await _db.delete('chats');
    await _db.delete('note_chats');
    await _db.delete('folders');
    await _db.delete('folder_items');
    await _db.delete('folder_chats');
    await _db.update('meta', {'v': 0}, where: "k = 'gemini_turn'");
  }

  Future<void> close() => _db.close();
}
