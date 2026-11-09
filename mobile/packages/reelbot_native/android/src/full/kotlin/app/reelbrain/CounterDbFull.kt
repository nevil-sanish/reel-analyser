package app.reelbrain

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase

// The counter, blocker and debug tables of `counter.db`, and everything that reads or writes them. Full build only:
// the semi build has none of these tables (see src/semi/.../FlavorSchema.kt). `counter.db` stays at version 5 in both.

object FlavorSchema {
    fun onCreate(db: SQLiteDatabase) {
        createCounterTables(db)
        createBlockTables(db)
    }

    fun onUpgrade(db: SQLiteDatabase, oldVersion: Int) {
        if (oldVersion < 2) createCounterTables(db)
        // Version 4: watched reels are kept as anonymous fingerprints only; wipe the text earlier versions stored.
        if (oldVersion < 4) db.execSQL("UPDATE seen_items SET author = '', caption = ''")
        // Version 5: the reel blocker (1.0.9.0).
        if (oldVersion < 5) createBlockTables(db)
    }

    fun erase(db: SQLiteDatabase) {
        for (t in listOf("seen_items", "screen_time", "unknown_items", "debug_state", "block_state", "block_use", "block_events")) db.delete(t, null, null)
    }

    /** Version 5: the blocker's rules, reel time per item and day, and its history (dates and kinds only, no photos). */
    private fun createBlockTables(db: SQLiteDatabase) {
        listOf(
            "CREATE TABLE block_state (k TEXT PRIMARY KEY, v TEXT NOT NULL)",
            "CREATE TABLE block_use (date TEXT NOT NULL, app TEXT NOT NULL, ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (date, app))",
            "CREATE TABLE block_events (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, kind TEXT NOT NULL, surface TEXT NOT NULL DEFAULT '')",
        ).forEach(db::execSQL)
    }

    /** Version 2: the Phase 2 counter (IMPLEMENTATION §3.3). */
    private fun createCounterTables(db: SQLiteDatabase) {
        listOf(
            """CREATE TABLE seen_items (
              date TEXT NOT NULL, app TEXT NOT NULL, fp TEXT NOT NULL,
              first_seen INTEGER NOT NULL, dwell_ms INTEGER NOT NULL DEFAULT 0,
              author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
              PRIMARY KEY (date, app, fp))""",
            "CREATE TABLE screen_time (date TEXT NOT NULL, app TEXT NOT NULL, ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (date, app))",
            "CREATE TABLE unknown_items (date TEXT NOT NULL, app TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (date, app))",
            "CREATE TABLE debug_state (k TEXT PRIMARY KEY, v TEXT NOT NULL, ts INTEGER NOT NULL)",
            """CREATE VIEW daily_counts AS
              SELECT d.date, d.app,
                (SELECT COUNT(*) FROM seen_items s WHERE s.date = d.date AND s.app = d.app) AS reels,
                COALESCE((SELECT ms FROM screen_time t WHERE t.date = d.date AND t.app = d.app), 0) AS ms,
                COALESCE((SELECT n FROM unknown_items u WHERE u.date = d.date AND u.app = d.app), 0) AS unknown
              FROM (SELECT date, app FROM seen_items UNION SELECT date, app FROM screen_time
                    UNION SELECT date, app FROM unknown_items) d""",
        ).forEach(db::execSQL)
    }

}

/** What the reel tracker and the block meter write into. */
class CounterSink(private val db: CounterDb) : TrackerSink, BlockMeter.Sink {
    override fun commitItem(date: String, app: String, fp: String, firstSeen: Long, item: ItemText) {
        db.writableDatabase.insertWithOnConflict("seen_items", null, ContentValues().apply {
            // Only the fingerprint (a hash) and the time: nothing about what the reel was.
            put("date", date); put("app", app); put("fp", fp); put("first_seen", firstSeen)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    override fun addDwell(date: String, app: String, fp: String, ms: Long) {
        db.writableDatabase.execSQL("UPDATE seen_items SET dwell_ms = dwell_ms + ? WHERE date = ? AND app = ? AND fp = ?", arrayOf<Any>(ms, date, app, fp))
    }

    override fun addUse(date: String, surface: String, ms: Long) = db.bump("block_use", "ms", date, surface, ms)

    override fun addScreenTime(date: String, app: String, ms: Long) = db.bump("screen_time", "ms", date, app, ms)

    override fun addUnknown(date: String, app: String) = db.bump("unknown_items", "n", date, app, 1)
}

private fun CounterDb.kv(k: String): String? = query("SELECT v FROM block_state WHERE k = ?", arrayOf(k)) { it.getString(0) }.firstOrNull()
private fun CounterDb.setKv(k: String, v: String?) {
    if (v == null) writableDatabase.delete("block_state", "k = ?", arrayOf(k))
    else writableDatabase.insertWithOnConflict("block_state", null, ContentValues().apply { put("k", k); put("v", v) }, SQLiteDatabase.CONFLICT_REPLACE)
}

/** The blocker's stored state exactly as saved; apply [BlockPolicy.effective] to get what is in force now. */
fun CounterDb.blockState() = BlockState(
    BlockConfig.parse(kv("active")), BlockConfig.parse(kv("pending")), kv("pendingFrom")?.toLongOrNull() ?: 0, kv("suspended"))

/** The state in force now: pending rules that are due are made active and saved. */
fun CounterDb.currentBlockState(now: Long): BlockState {
    val s = blockState()
    val e = BlockPolicy.effective(s, now)
    if (e != s) saveBlockState(e)
    return e
}

fun CounterDb.saveBlockState(s: BlockState) {
    setKv("active", s.active?.toJson()); setKv("pending", s.pending?.toJson())
    setKv("pendingFrom", if (s.pending != null) s.pendingFrom.toString() else null); setKv("suspended", s.suspendedDate)
}

/** The penalty for missed daily goals, as Dart last reported it. */
fun CounterDb.punish(): Punish? = Punish.parse(kv("punish"))

fun CounterDb.setPunish(p: Punish) = setKv("punish", p.toJson())


fun CounterDb.usedToday(date: String): Map<String, Long> =
    query("SELECT app, ms FROM block_use WHERE date = ?", arrayOf(date)) { it.getString(0) to it.getLong(1) }.toMap()

fun CounterDb.addEvent(ts: Long, kind: String, surface: String = "") {
    writableDatabase.insert("block_events", null, ContentValues().apply { put("ts", ts); put("kind", kind); put("surface", surface) })
}

fun CounterDb.hasEvent(kind: String, surface: String, since: Long): Boolean =
    query("SELECT 1 FROM block_events WHERE kind = ? AND surface = ? AND ts >= ? LIMIT 1", arrayOf(kind, surface, since.toString())) { 1 }.isNotEmpty()

fun CounterDb.events(limit: Int): List<Map<String, Any?>> =
    query("SELECT ts, kind, surface FROM block_events ORDER BY ts DESC LIMIT ?", arrayOf(limit.toString())) {
        mapOf("ts" to it.getLong(0), "kind" to it.getString(1), "surface" to it.getString(2))
    }


fun CounterDb.daily(days: Int, today: String): List<Map<String, Any?>> = query(
    "SELECT date, app, reels, ms, unknown FROM daily_counts WHERE date > date(?, ?) ORDER BY date DESC, app",
    arrayOf(today, "-$days days"),
) { mapOf("date" to it.getString(0), "app" to it.getString(1), "reels" to it.getLong(2), "ms" to it.getLong(3), "unknown" to it.getLong(4)) }

/** v0.8.1 Insights: reels and watch time by local hour of day over the last [days] days (from first-seen times). */
fun CounterDb.hourly(days: Int, today: String): List<Map<String, Any?>> = query(
    """SELECT CAST(strftime('%H', first_seen / 1000, 'unixepoch', 'localtime') AS INTEGER) AS h, COUNT(*), SUM(dwell_ms)
       FROM seen_items WHERE date > date(?, ?) GROUP BY h ORDER BY h""",
    arrayOf(today, "-$days days"),
) { mapOf("hour" to it.getLong(0), "reels" to it.getLong(1), "ms" to it.getLong(2)) }

fun CounterDb.seenItems(date: String): List<Map<String, Any?>> = query(
    "SELECT app, fp, first_seen, dwell_ms, author, caption FROM seen_items WHERE date = ? ORDER BY first_seen DESC", arrayOf(date),
) {
    mapOf("app" to it.getString(0), "fp" to it.getString(1), "firstSeen" to it.getLong(2), "dwellMs" to it.getLong(3),
        "author" to it.getString(4), "caption" to it.getString(5))
}

fun CounterDb.debugState(): List<Map<String, Any?>> =
    query("SELECT k, v, ts FROM debug_state ORDER BY k", null) { mapOf("k" to it.getString(0), "v" to it.getString(1), "ts" to it.getLong(2)) }

/** Capture off: drop what it recorded about the screen (it can include captions). */
fun CounterDb.clearCapture() {
    writableDatabase.delete("debug_state", "k = 'now' OR k LIKE 'tree_%'", null)
}

fun CounterDb.debug(k: String): String? = query("SELECT v FROM debug_state WHERE k = ?", arrayOf(k)) { it.getString(0) }.firstOrNull()

fun CounterDb.setDebug(k: String, v: String, ts: Long) {
    writableDatabase.insertWithOnConflict("debug_state", null, ContentValues().apply { put("k", k); put("v", v); put("ts", ts) },
        SQLiteDatabase.CONFLICT_REPLACE)
}

/** (reels, unknown) for one app on one day, for the unknown alert. */
fun CounterDb.totals(date: String, app: String): Pair<Long, Long> =
    query("SELECT reels, unknown FROM daily_counts WHERE date = ? AND app = ?", arrayOf(date, app)) { it.getLong(0) to it.getLong(1) }
        .firstOrNull() ?: (0L to 0L)

/** The retention rules of the Privacy Policy: Insights rows are kept 90 days, and the queue 30 ([CounterDb.pruneQueue]). */
fun CounterDb.prune(today: String, now: Long) {
    val db = writableDatabase
    for (t in listOf("seen_items", "screen_time", "unknown_items")) {
        db.execSQL("DELETE FROM $t WHERE date < date(?, '-90 days')", arrayOf(today))
    }
    db.execSQL("DELETE FROM block_use WHERE date < date(?, '-90 days')", arrayOf(today))
    db.delete("block_events", "ts < ?", arrayOf((now - 90L * 24 * 3600 * 1000).toString()))
    pruneQueue(now)
}
