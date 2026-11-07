package app.reelbrain

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** `counter.db`, owned by Kotlin; Dart reaches it only through `reelbot/counter` (PLAN §4.7). */
class CounterDb private constructor(ctx: Context) : SQLiteOpenHelper(ctx, "counter.db", null, 4), TrackerSink {
    companion object {
        @Volatile private var instance: CounterDb? = null
        fun get(ctx: Context): CounterDb =
            instance ?: synchronized(this) { instance ?: CounterDb(ctx.applicationContext).also { instance = it } }
    }

    override fun onConfigure(db: SQLiteDatabase) { db.enableWriteAheadLogging() }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE pending_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT, app TEXT NOT NULL DEFAULT '',
              author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
              on_screen_text TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'queued',
              title TEXT NOT NULL DEFAULT '')"""
        )
        createCounterTables(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createCounterTables(db)
        // Version 3: the analysed note's title, for the digest (Kotlin never opens Dart's reel_brain.db).
        if (oldVersion < 3) db.execSQL("ALTER TABLE pending_items ADD COLUMN title TEXT NOT NULL DEFAULT ''")
        // Version 4: watched reels are kept as anonymous fingerprints only; wipe the text earlier versions stored.
        if (oldVersion < 4) db.execSQL("UPDATE seen_items SET author = '', caption = ''")
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

    override fun commitItem(date: String, app: String, fp: String, firstSeen: Long, item: ItemText) {
        writableDatabase.insertWithOnConflict("seen_items", null, ContentValues().apply {
            // Only the fingerprint (a hash) and the time: nothing about what the reel was.
            put("date", date); put("app", app); put("fp", fp); put("first_seen", firstSeen)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    override fun addDwell(date: String, app: String, fp: String, ms: Long) {
        writableDatabase.execSQL("UPDATE seen_items SET dwell_ms = dwell_ms + ? WHERE date = ? AND app = ? AND fp = ?", arrayOf<Any>(ms, date, app, fp))
    }

    override fun addScreenTime(date: String, app: String, ms: Long) = bump("screen_time", "ms", date, app, ms)
    override fun addUnknown(date: String, app: String) = bump("unknown_items", "n", date, app, 1)

    /** UPSERT needs SQLite 3.24 (Android 11); minSdk is 29. */
    private fun bump(table: String, col: String, date: String, app: String, by: Long) {
        val db = writableDatabase
        db.execSQL("INSERT OR IGNORE INTO $table (date, app) VALUES (?, ?)", arrayOf(date, app))
        db.execSQL("UPDATE $table SET $col = $col + ? WHERE date = ? AND app = ?", arrayOf<Any>(by, date, app))
    }

    fun daily(days: Int, today: String): List<Map<String, Any?>> = query(
        "SELECT date, app, reels, ms, unknown FROM daily_counts WHERE date > date(?, ?) ORDER BY date DESC, app",
        arrayOf(today, "-$days days"),
    ) { mapOf("date" to it.getString(0), "app" to it.getString(1), "reels" to it.getLong(2), "ms" to it.getLong(3), "unknown" to it.getLong(4)) }

    /** v0.8.1 Insights: reels and watch time by local hour of day over the last [days] days (from first-seen times). */
    fun hourly(days: Int, today: String): List<Map<String, Any?>> = query(
        """SELECT CAST(strftime('%H', first_seen / 1000, 'unixepoch', 'localtime') AS INTEGER) AS h, COUNT(*), SUM(dwell_ms)
           FROM seen_items WHERE date > date(?, ?) GROUP BY h ORDER BY h""",
        arrayOf(today, "-$days days"),
    ) { mapOf("hour" to it.getLong(0), "reels" to it.getLong(1), "ms" to it.getLong(2)) }

    fun seenItems(date: String): List<Map<String, Any?>> = query(
        "SELECT app, fp, first_seen, dwell_ms, author, caption FROM seen_items WHERE date = ? ORDER BY first_seen DESC", arrayOf(date),
    ) {
        mapOf("app" to it.getString(0), "fp" to it.getString(1), "firstSeen" to it.getLong(2), "dwellMs" to it.getLong(3),
            "author" to it.getString(4), "caption" to it.getString(5))
    }

    fun debugState(): List<Map<String, Any?>> =
        query("SELECT k, v, ts FROM debug_state ORDER BY k", null) { mapOf("k" to it.getString(0), "v" to it.getString(1), "ts" to it.getLong(2)) }

    /** Capture off: drop what it recorded about the screen (it can include captions). */
    fun clearCapture() {
        writableDatabase.delete("debug_state", "k = 'now' OR k LIKE 'tree_%'", null)
    }

    fun debug(k: String): String? = query("SELECT v FROM debug_state WHERE k = ?", arrayOf(k)) { it.getString(0) }.firstOrNull()

    fun setDebug(k: String, v: String, ts: Long) {
        writableDatabase.insertWithOnConflict("debug_state", null, ContentValues().apply { put("k", k); put("v", v); put("ts", ts) },
            SQLiteDatabase.CONFLICT_REPLACE)
    }

    /** (reels, unknown) for one app on one day, for the unknown alert. */
    fun totals(date: String, app: String): Pair<Long, Long> =
        query("SELECT reels, unknown FROM daily_counts WHERE date = ? AND app = ?", arrayOf(date, app)) { it.getLong(0) to it.getLong(1) }
            .firstOrNull() ?: (0L to 0L)

    private fun <T> query(sql: String, args: Array<String>?, row: (android.database.Cursor) -> T): List<T> =
        readableDatabase.rawQuery(sql, args).use { c -> buildList { while (c.moveToNext()) add(row(c)) } }

    /**
     * The retention rules of the Privacy Policy: Insights rows (counts, screen time, unknown counts) are kept 90 days,
     * and finished, failed or stopped queue entries 30 days. [today] is the local date as yyyy-MM-dd, [now] epoch ms.
     */
    fun prune(today: String, now: Long) {
        val db = writableDatabase
        for (t in listOf("seen_items", "screen_time", "unknown_items")) {
            db.execSQL("DELETE FROM $t WHERE date < date(?, '-90 days')", arrayOf(today))
        }
        db.delete("pending_items", "status != 'queued' AND created_at < ?", arrayOf((now - 30L * 24 * 3600 * 1000).toString()))
    }

    /** "Erase all my data": every counter, queue and debug row. */
    fun eraseAll() {
        val db = writableDatabase
        for (t in listOf("pending_items", "seen_items", "screen_time", "unknown_items", "debug_state")) db.delete(t, null, null)
    }

    /** SHARE-IN: queues a shared link. */
    fun addShared(link: ShareUrls.Link, now: Long) {
        writableDatabase.insert("pending_items", null, ContentValues().apply {
            put("url", link.url); put("app", link.app); put("created_at", now)
        })
    }

    /** v0.8: a shared photo, already copied into app storage; the runner sends it to the AI as an image. */
    fun addPhoto(path: String, caption: String, now: Long) {
        writableDatabase.insert("pending_items", null, ContentValues().apply {
            put("url", "photo:$path"); put("app", "photo"); put("caption", caption); put("created_at", now)
        })
    }

    fun pending(status: String?): List<Map<String, Any?>> {
        val where = if (status == null) "" else "WHERE status = ?"
        val args = if (status == null) null else arrayOf(status)
        return readableDatabase.rawQuery(
            "SELECT id, url, app, author, caption, on_screen_text, created_at, status FROM pending_items $where ORDER BY id", args
        ).use { c ->
            buildList {
                while (c.moveToNext()) add(mapOf(
                    "id" to c.getLong(0), "url" to c.getString(1), "app" to c.getString(2),
                    "author" to c.getString(3), "caption" to c.getString(4), "onScreenText" to c.getString(5),
                    "createdAt" to c.getLong(6), "status" to c.getString(7),
                ))
            }
        }
    }

    fun setStatus(id: Long, status: String, title: String = "") {
        writableDatabase.update("pending_items", ContentValues().apply { put("status", status); put("title", title) },
            "id = ?", arrayOf(id.toString()))
    }

    /** Items shared or saved since local midnight, and the titles of those already analysed. */
    fun savedToday(now: Long): Pair<Int, List<String>> {
        val midnight = java.util.Calendar.getInstance().apply {
            timeInMillis = now
            set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        val rows = query("SELECT status, title FROM pending_items WHERE created_at >= ? ORDER BY id", arrayOf(midnight.toString())) {
            it.getString(0) to it.getString(1)
        }
        val analysed = setOf("done", "caption+thumbnail", "text-only")
        return rows.size to rows.filter { it.first in analysed && it.second.isNotBlank() }.map { it.second }
    }
}
