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
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE reels (
            url TEXT PRIMARY KEY, app TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '', keyPoints TEXT NOT NULL DEFAULT '[]', tags TEXT NOT NULL DEFAULT '[]',
            author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
            analysis TEXT NOT NULL DEFAULT 'done', step INTEGER NOT NULL DEFAULT 0, savedAt INTEGER NOT NULL)''');
          await db.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v INTEGER NOT NULL)');
          await db.insert('meta', {'k': 'processing_until', 'v': 0});
        },
      ),
    );
    return LibraryDb._(db);
  }

  Future<void> saveReel(Reel r) => _db.insert('reels', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> has(String url) async =>
      (await _db.query('reels', columns: ['url'], where: 'url = ?', whereArgs: [url])).isNotEmpty;

  /// Newest first; [query] matches title, summary, key points, tags, author and caption.
  Future<List<Reel>> reels({String query = ''}) async {
    final q = query.trim();
    final rows = q.isEmpty
        ? await _db.query('reels', orderBy: 'savedAt DESC')
        : await _db.query('reels',
            where: "(title || ' ' || summary || ' ' || keyPoints || ' ' || tags || ' ' || author || ' ' || caption) LIKE ?",
            whereArgs: ['%$q%'],
            orderBy: 'savedAt DESC');
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
