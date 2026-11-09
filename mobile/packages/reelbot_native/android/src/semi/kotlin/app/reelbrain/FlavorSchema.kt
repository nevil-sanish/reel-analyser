package app.reelbrain

import android.database.sqlite.SQLiteDatabase

/** The semi build keeps only the share queue in `counter.db`. Its version stays 5 so a database written by an earlier build still opens. */
object FlavorSchema {
    fun onCreate(db: SQLiteDatabase) {}
    fun onUpgrade(db: SQLiteDatabase, oldVersion: Int) {}
    fun erase(db: SQLiteDatabase) {}
}
