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
        version: 3,
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
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _v2(db);
          if (from < 3) await _v3(db);
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

  Future<void> deleteChat(int id) => _db.delete('chats', where: 'id = ?', whereArgs: [id]);

  Future<void> markSeen(String url, int now) =>
      _db.update('reels', {'seenAt': now}, where: 'url = ? AND seenAt = 0', whereArgs: [url]);

  Future<void> setArchived(String url, bool archived) =>
      _db.update('reels', {'archived': archived ? 1 : 0}, where: 'url = ?', whereArgs: [url]);

  /// Seen notes saved more than 3 days ago leave the library for the archive. Unseen ones stay until read.
  Future<int> archiveOld(int now) => _db.update('reels', {'archived': 1},
      where: 'archived = 0 AND seenAt > 0 AND savedAt < ?', whereArgs: [now - const Duration(days: 3).inMilliseconds]);

  Future<void> saveReel(Reel r) => _db.insert('reels', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> has(String url) async =>
      (await _db.query('reels', columns: ['url'], where: 'url = ?', whereArgs: [url])).isNotEmpty;

  /// Newest first; [query] matches title, summary, key points, tags, author and caption.
  /// [archived]: null = everything (chat, export), false = the library, true = the archive.
  Future<List<Reel>> reels({String query = '', bool? archived}) async {
    final q = query.trim();
    final where = [
      if (archived != null) 'archived = ${archived ? 1 : 0}',
      if (q.isNotEmpty) "(title || ' ' || summary || ' ' || keyPoints || ' ' || tags || ' ' || author || ' ' || caption) LIKE ?",
    ];
    final rows = await _db.query('reels',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: q.isEmpty ? null : ['%$q%'], orderBy: 'savedAt DESC');
    return rows.map(Reel.fromRow).toList();
  }

  Future<void> delete(String url) => _db.delete('reels', where: 'url = ?', whereArgs: [url]);

  /// The app and the background task share one queue; whoever sets this first runs it (T-PIPE-10).
  Future<bool> tryLock(int now, {Duration hold = const Duration(minutes: 5)}) async {
    final n = await _db.rawUpdate(
        "UPDATE meta SET v = ? WHERE k = 'processing_until' AND v < ?", [now + hold.inMilliseconds, now]);
    return n == 1;
  }

  Future<void> unlock() => _db.rawUpdate("UPDATE meta SET v = 0 WHERE k = 'processing_until'");

  Future<void> close() => _db.close();
}
