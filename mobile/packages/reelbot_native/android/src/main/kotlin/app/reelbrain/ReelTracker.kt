package app.reelbrain

import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** What could be read for the reel on screen. `likes` is the raw like-count label, "" if none. */
data class ItemText(
    val author: String = "", val caption: String = "", val audio: String = "",
    val title: String = "", val likes: String = "",
) {
    /** Likes alone don't identify a reel. */
    fun isBlank() = author.isBlank() && caption.isBlank() && audio.isBlank() && title.isBlank()
}

object Fingerprint {
    private val ws = Regex("\\s+")
    private val moreLess = Regex("(\\s*(…|\\.\\.\\.)\\s*more|\\s+more|\\s+less|^more|^less)$", RegexOption.IGNORE_CASE)
    private val ellipsis = Regex("\\s*(…|\\.\\.\\.)$")
    private val count = Regex("^([0-9][0-9,]*(?:\\.[0-9]+)?)\\s*([KkMmBb]?)$")

    fun normalize(s: String): String {
        var t = s.replace(ws, " ").trim()
        t = t.replace(moreLess, "").replace(ellipsis, "").trim()
        return t.lowercase(Locale.ROOT)
    }

    /** `523` → `520`, `12.3K` → `12000`: two significant figures, so a count ticking up mid-watch keeps the id. */
    fun likeBucket(label: String): String {
        val m = count.matchEntire(label.trim()) ?: return ""
        val base = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: return ""
        val n = (base * when (m.groupValues[2].lowercase()) { "k" -> 1e3; "m" -> 1e6; "b" -> 1e9; else -> 1.0 }).toLong()
        if (n < 100) return n.toString()
        var scale = 1L
        while (n / scale >= 100) scale *= 10
        return (n / scale * scale).toString()
    }

    fun of(app: String, item: ItemText?): String? {
        if (item == null || item.isBlank()) return null
        val captionless = item.caption.isBlank() && item.audio.isBlank() && item.title.isBlank()
        val extra = if (captionless) likeBucket(item.likes) else ""
        // 40 caption characters: the truncated "… more" and the expanded caption give the same id.
        val key = listOf(app, normalize(item.author), normalize(item.caption).take(40), normalize(item.audio), normalize(item.title), extra)
            .joinToString("|")
        return MessageDigest.getInstance("SHA-1").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }.take(20)
    }
}

/** The phone's local calendar day, which is what "today" means to the user. */
fun localDate(ms: Long): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date(ms))

interface TrackerSink {
    /** Repeats of (date, app, fp) are ignored. */
    fun commitItem(date: String, app: String, fp: String, firstSeen: Long, item: ItemText)
    fun addDwell(date: String, app: String, fp: String, ms: Long)
    fun addScreenTime(date: String, app: String, ms: Long)
    fun addUnknown(date: String, app: String)
}

/** Turns a stream of "what's on screen" observations into counted reels, dwell and screen time (IMPLEMENTATION §3.1). */
class ReelTracker(
    private val sink: TrackerSink,
    private val minDwellMs: Long = 1500,
    private val maxGapMs: Long = 5000,
    private val flushEveryMs: Long = 30000,
    private val dateOf: (Long) -> String = ::localDate,
) {
    private var app: String? = null
    private var lastSeen = 0L
    private var lastFlush = 0L
    private var fp: String? = null
    private var item: ItemText? = null
    private var since = 0L
    private var committed = false

    val active get() = app != null
    val currentApp get() = app
    val current get() = fp to item

    @Synchronized
    fun observe(now: Long, app: String?, inReels: Boolean, seen: ItemText?) {
        if (active && now - lastSeen > maxGapMs) end(lastSeen) // a sleeping phone isn't watch time
        if (app == null || !inReels) { end(now); return }
        val newFp = Fingerprint.of(app, seen)
        if (app != this.app) {
            end(now)
            this.app = app
            lastFlush = now
            start(now, newFp, seen)
        } else if (newFp != fp) {
            leave(now)
            start(now, newFp, seen)
        }
        lastSeen = now
        if (!committed && now - since >= minDwellMs) commit()
        if (now - lastFlush >= flushEveryMs) flush(now)
    }

    @Synchronized
    fun end(now: Long) {
        if (app == null) return
        val at = maxOf(now, lastFlush)
        if (!committed && at - since >= minDwellMs) commit()
        leave(at)
        flush(at)
        this.app = null; fp = null; item = null; committed = false
    }

    private fun start(now: Long, newFp: String?, seen: ItemText?) {
        fp = newFp; item = seen; since = now; committed = false
    }

    private fun commit() {
        val a = app!!
        val f = fp
        if (f == null) sink.addUnknown(dateOf(since), a) else sink.commitItem(dateOf(since), a, f, since, item!!)
        committed = true
    }

    private fun leave(now: Long) {
        val f = fp ?: return
        if (committed) sink.addDwell(dateOf(since), app!!, f, now - since)
    }

    private fun flush(now: Long) {
        if (now > lastFlush) sink.addScreenTime(dateOf(lastFlush), app!!, now - lastFlush)
        lastFlush = now
    }
}

/** "Reel Bot can't read Instagram/YouTube any more": at least 5 unknown and 30% of the day's items, once a day. */
object UnknownAlert {
    fun shouldAlert(reels: Long, unknown: Long, alreadyAlerted: Boolean) =
        !alreadyAlerted && unknown >= 5 && unknown * 10 >= (reels + unknown) * 3
}
