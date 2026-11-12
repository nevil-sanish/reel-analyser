package app.reelbrain

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** `counter.db`, owned by Kotlin; Dart reaches it only through `reelbot/counter` (PLAN §4.7). */
class CounterDb private constructor(ctx: Context) : SQLiteOpenHelper(ctx, "counter.db", null, 5) {
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
        FlavorSchema.onCreate(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 3: the analysed note's title (Kotlin never opens Dart's reel_brain.db).
        if (oldVersion < 3) db.execSQL("ALTER TABLE pending_items ADD COLUMN title TEXT NOT NULL DEFAULT ''")
        // Versions 2, 4 and 5 belong to the counter and blocker tables, which only the full build has.
        FlavorSchema.onUpgrade(db, oldVersion)
    }

    /** UPSERT needs SQLite 3.24 (Android 11); minSdk is 29. */
    internal fun bump(table: String, col: String, date: String, app: String, by: Long) {
        val db = writableDatabase
        db.execSQL("INSERT OR IGNORE INTO $table (date, app) VALUES (?, ?)", arrayOf(date, app))
        db.execSQL("UPDATE $table SET $col = $col + ? WHERE date = ? AND app = ?", arrayOf<Any>(by, date, app))
    }

    internal fun <T> query(sql: String, args: Array<String>?, row: (android.database.Cursor) -> T): List<T> =
        readableDatabase.rawQuery(sql, args).use { c -> buildList { while (c.moveToNext()) add(row(c)) } }

    /** Finished, failed or stopped queue entries are dropped after 30 days (Privacy Policy). [now] is epoch ms. */
    fun pruneQueue(now: Long) {
        writableDatabase.delete("pending_items", "status != 'queued' AND created_at < ?", arrayOf((now - 30L * 24 * 3600 * 1000).toString()))
    }

    /** "Erase all my data": the queue, plus whatever tables this build has besides it. */
    fun eraseAll() {
        val db = writableDatabase
        db.delete("pending_items", null, null)
        FlavorSchema.erase(db)
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
            "SELECT id, url, app, author, caption, on_screen_text, created_at, status, title FROM pending_items $where ORDER BY id", args
        ).use { c ->
            buildList {
                while (c.moveToNext()) add(mapOf(
                    "id" to c.getLong(0), "url" to c.getString(1), "app" to c.getString(2),
                    "author" to c.getString(3), "caption" to c.getString(4), "onScreenText" to c.getString(5),
                    "createdAt" to c.getLong(6), "status" to c.getString(7), "title" to c.getString(8),
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
