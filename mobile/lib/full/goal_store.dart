import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/library_db.dart';

/// Daily goals' own tables, in the same `reel_brain.db`. They are created here, by the full build, when the goals are first used:
/// the shared database code knows nothing about them, so the semi build has no goal tables and no goal queries.
class GoalStore {
  final Database _db;
  GoalStore._(this._db);

  static final _opened = Expando<Future<GoalStore>>();

  /// One store per database, with its tables made on first use.
  static Future<GoalStore> of(LibraryDb lib) => _opened[lib] ??= () async {
        await _ensure(lib.raw);
        return GoalStore._(lib.raw);
      }();

  /// Version 7: daily goals (full build). `goal_cfg` keeps every version of the goals with the day it starts to count, so a day
  /// is judged by the goals that were in force on it. `goal_days` is one judged day: the counts, met or missed (null = could not
  /// be read), the misses in a row and the last blocked day. Only public usernames and numbers: nothing else is kept.
  static Future<void> _ensure(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS goal_cfg (fromDate TEXT PRIMARY KEY, json TEXT NOT NULL)');
    await db.execute('''CREATE TABLE IF NOT EXISTS goal_days (
        date TEXT PRIMARY KEY, counts TEXT NOT NULL, met INTEGER, streak INTEGER NOT NULL DEFAULT 0,
        until TEXT, evaluatedAt INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS goal_changes (
        id INTEGER PRIMARY KEY CHECK (id = 1), requestedOn TEXT, deniedOn TEXT)''');
  }

  Future<void> saveGoalConfig(String fromDate, String json) =>
      _db.insert('goal_cfg', {'fromDate': fromDate, 'json': json}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// The goals most recently saved.
  Future<String?> latestGoalConfigJson() async {
    final r = await _db.query('goal_cfg', orderBy: 'fromDate DESC', limit: 1);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  /// The goals in force on [date] (yyyy-MM-dd): the latest saved on or before it.
  Future<String?> goalConfigJsonFor(String date) async {
    final r = await _db.query('goal_cfg', where: 'fromDate <= ?', whereArgs: [date], orderBy: 'fromDate DESC', limit: 1);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  Future<String?> firstGoalConfigDate() async {
    final r = await _db.query('goal_cfg', orderBy: 'fromDate ASC', limit: 1);
    return r.isEmpty ? null : r.first['fromDate'] as String;
  }

  Future<String?> lastGoalDay() async {
    final r = await _db.query('goal_days', columns: ['date'], orderBy: 'date DESC', limit: 1);
    return r.isEmpty ? null : r.first['date'] as String;
  }

  /// Misses in a row and the last blocked day, as of the latest judged day.
  Future<(int, String?)> goalPenaltyRow() async {
    final r = await _db.query('goal_days', columns: ['streak', 'until'], orderBy: 'date DESC', limit: 1);
    return r.isEmpty ? (0, null) : (r.first['streak'] as int, r.first['until'] as String?);
  }

  Future<void> saveGoalDay(String date, Map<String, int?> counts, bool? met, int streak, String? until) => _db.insert(
      'goal_days',
      {'date': date, 'counts': jsonEncode(counts), 'met': met == null ? null : (met ? 1 : 0), 'streak': streak, 'until': until, 'evaluatedAt': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace);

  /// The privacy policy keeps judged days for 90 days. The goals themselves stay until changed or erased.
  Future<void> pruneGoalDays(String before) => _db.delete('goal_days', where: 'date < ?', whereArgs: [before]);

  /// Newest first: (date, counts by source, met or null, misses in a row).
  Future<List<(String, Map<String, int?>, bool?, int)>> goalDays({int limit = 30}) async => [
        for (final r in await _db.query('goal_days', orderBy: 'date DESC', limit: limit))
          (
            r['date'] as String,
            {for (final e in (jsonDecode(r['counts'] as String) as Map).entries) '${e.key}': (e.value as num?)?.toInt()},
            r['met'] == null ? null : r['met'] == 1,
            r['streak'] as int,
          ),
      ];

  /// The username last used for each source in any saved version of the goals. A username is locked once it has been used,
  /// even if the source is switched off and on again.
  Future<Map<String, String>> lockedHandles() async {
    final rows = await _db.query('goal_cfg', orderBy: 'fromDate ASC');
    final out = <String, String>{};
    for (final r in rows) {
      try {
        for (final g in (jsonDecode(r['json']! as String) as Map)['goals'] as List) {
          out['${(g as Map)['source']}'] = '${g['handle']}';
        }
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// The day a username change was asked for (null when none is waiting).
  Future<String?> changeRequestedOn() async {
    final r = await _db.query('goal_changes', where: 'id = 1');
    return r.isEmpty ? null : r.first['requestedOn'] as String?;
  }

  Future<void> requestChange(String date) =>
      _db.insert('goal_changes', {'id': 1, 'requestedOn': date}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> clearChange() => _db.delete('goal_changes');

  /// Erase all my data.
  Future<void> eraseAll() async {
    await _db.delete('goal_cfg');
    await _db.delete('goal_days');
    await _db.delete('goal_changes');
  }
}
