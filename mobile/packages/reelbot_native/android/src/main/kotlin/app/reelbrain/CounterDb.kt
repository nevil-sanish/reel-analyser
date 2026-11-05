package app.reelbrain

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** `counter.db`, owned by Kotlin; Dart reaches it only through `reelbot/counter` (PLAN §4.7). */
class CounterDb private constructor(ctx: Context) : SQLiteOpenHelper(ctx, "counter.db", null, 1) {
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
              status TEXT NOT NULL DEFAULT 'queued')"""
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /** SHARE-IN: fills a fresh URL-less bubble row, else inserts a new queued row. */
    @Synchronized
    fun addShared(link: ShareUrls.Link, now: Long) {
        val db = writableDatabase
        db.rawQuery("SELECT id, url, created_at FROM pending_items ORDER BY id DESC LIMIT 1", null).use { c ->
            if (c.moveToFirst() && ShareUrls.shouldAttach(c.getString(1), c.getLong(2), now)) {
                db.update("pending_items", ContentValues().apply { put("url", link.url); put("app", link.app) },
                    "id = ?", arrayOf(c.getLong(0).toString()))
                return
            }
        }
        db.insert("pending_items", null, ContentValues().apply {
            put("url", link.url); put("app", link.app); put("created_at", now)
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

    fun setStatus(id: Long, status: String) {
        writableDatabase.update("pending_items", ContentValues().apply { put("status", status) }, "id = ?", arrayOf(id.toString()))
    }
}
