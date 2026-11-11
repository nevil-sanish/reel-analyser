package app.reelbrain

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** A span of the day in minutes since midnight. `start > end` runs over midnight (22:00 to 02:00). */
data class Interval(val start: Int, val end: Int) {
    fun contains(minute: Int) = if (start <= end) minute in start until end else minute >= start || minute < end
}

/** At most [limitMin] minutes of reels a day, and only inside [intervals] (none = any time). Both must hold. */
data class BlockRule(val limitMin: Int?, val intervals: List<Interval>)

/**
 * What the user chose to block. `items` are `instagram`, `youtube` and `browser`. In `shared` mode one rule (`all`)
 * covers them together, and their reel time is added up; in `separate` mode each item has its own rule.
 */
data class BlockConfig(val mode: String, val items: Set<String>, val rules: Map<String, BlockRule>) {
    fun ruleFor(surface: String) = rules[if (mode == "shared") "all" else surface]

    fun toJson(): String = JSONObject().apply {
        put("mode", mode)
        put("items", JSONArray(items.sorted()))
        put("rules", JSONObject().also { o ->
            for ((k, r) in rules) o.put(k, JSONObject().apply {
                put("limitMin", r.limitMin ?: JSONObject.NULL)
                put("intervals", JSONArray(r.intervals.map { JSONArray(listOf(it.start, it.end)) }))
            })
        })
    }.toString()

    companion object {
        val surfaces = setOf("instagram", "youtube", "browser")

        /** Null for anything that isn't a well-formed config, so a damaged value never blocks or crashes. */
        fun parse(json: String?): BlockConfig? = try {
            val o = JSONObject(json ?: return null)
            val mode = o.getString("mode").takeIf { it == "shared" || it == "separate" } ?: return null
            val items = o.getJSONArray("items").let { a -> (0 until a.length()).map { a.getString(it) }.filter { it in surfaces }.toSet() }
            val ro = o.getJSONObject("rules")
            val rules = ro.keys().asSequence().associateWith { k ->
                val r = ro.getJSONObject(k)
                val lim = if (r.isNull("limitMin")) null else r.getInt("limitMin").takeIf { it in 1..1440 }
                val iv = r.getJSONArray("intervals").let { a ->
                    (0 until a.length()).map { a.getJSONArray(it) }.map { Interval(it.getInt(0), it.getInt(1)) }
                }.filter { it.start in 0..1439 && it.end in 0..1439 && it.start != it.end }
                BlockRule(lim, iv)
            }
            BlockConfig(mode, items, rules)
        } catch (e: Exception) {
            null
        }
    }
}

/** The stored state: the rules in force, rules waiting for the next midnight, and the day the block was suspended. */
data class BlockState(
    val active: BlockConfig? = null,
    val pending: BlockConfig? = null,
    /** Epoch ms from which [pending] replaces [active]. */
    val pendingFrom: Long = 0,
    val suspendedDate: String? = null,
)

sealed class Verdict {
    object Allow : Verdict()
    /** [reason] is `limit` or `schedule`. */
    data class Block(val reason: String) : Verdict()
}

object BlockPolicy {
    fun minuteOfDay(ms: Long): Int = Calendar.getInstance().apply { timeInMillis = ms }.let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) }

    private fun midnight(ms: Long): Long = Calendar.getInstance().apply {
        timeInMillis = ms
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /** Pending rules that are due take over. Checked whenever the state is read, so nothing has to run at midnight. */
    fun effective(s: BlockState, now: Long): BlockState =
        if (s.pending != null && now >= s.pendingFrom) s.copy(active = s.pending, pending = null, pendingFrom = 0) else s

    /**
     * The first set-up applies at once. A later change (the app asks for a typed paragraph first) waits for the next
     * midnight, so it can never loosen today's rules.
     */
    fun save(s: BlockState, cfg: BlockConfig, now: Long): BlockState = when {
        s.active == null -> s.copy(active = cfg, pending = null, pendingFrom = 0)
        else -> s.copy(pending = cfg, pendingFrom = nextMidnight(now))
    }

    fun nextMidnight(now: Long): Long = Calendar.getInstance().apply {
        timeInMillis = midnight(now); add(Calendar.DAY_OF_MONTH, 1)
    }.timeInMillis

    /**
     * [usedMs] is today's reel time by item. Suspended for the day, an item that isn't blocked, or a rule-less item
     * always pass. Otherwise the limit and the schedule must both be met.
     */
    fun verdict(cfg: BlockConfig?, surface: String, minute: Int, usedMs: Map<String, Long>, suspendedToday: Boolean): Verdict {
        if (cfg == null || suspendedToday || surface !in cfg.items) return Verdict.Allow
        val rule = cfg.ruleFor(surface) ?: return Verdict.Allow
        val used = if (cfg.mode == "shared") cfg.items.sumOf { usedMs[it] ?: 0L } else usedMs[surface] ?: 0L
        if (rule.limitMin != null && used >= rule.limitMin * 60_000L) return Verdict.Block("limit")
        if (rule.intervals.isNotEmpty() && rule.intervals.none { it.contains(minute) }) return Verdict.Block("schedule")
        return Verdict.Allow
    }

    private fun hhmm(m: Int) = "%02d:%02d".format(m / 60, m % 60)

    fun name(surface: String) = when (surface) { "instagram" -> "Instagram Reels"; "youtube" -> "YouTube Shorts"; else -> "Reels and Shorts on the web" }

    /** The line the block screen shows. */
    fun describe(cfg: BlockConfig?, surface: String, reason: String): String {
        val r = cfg?.ruleFor(surface)
        val what = if (cfg?.mode == "shared") "Reels and Shorts" else name(surface)
        return if (reason == "limit") {
            val m = r?.limitMin ?: 0
            "You have used your daily limit of ${if (m % 60 == 0) "${m / 60} h" else if (m > 60) "${m / 60} h ${m % 60} min" else "$m min"} of $what."
        } else {
            "$what can only be watched at ${r?.intervals.orEmpty().joinToString(", ") { "${hhmm(it.start)}-${hhmm(it.end)}" }}."
        }
    }

    /** Which item a browser address belongs to: only the reels or shorts part of a site counts. */
    fun browserSurface(address: String): Boolean {
        val a = address.lowercase()
        return "instagram.com/reel" in a || "youtube.com/shorts" in a
    }
}

/** Counts reel time by item for the day. The service keeps the part not yet written, so a limit can't overrun while it waits. */
class BlockMeter(private val sink: Sink, private val maxGapMs: Long = 5000, private val flushEveryMs: Long = 2000) {
    interface Sink { fun addUse(date: String, surface: String, ms: Long) }

    private var surface: String? = null
    private var last = 0L
    private var unflushed = 0L
    private var date = ""

    val active get() = surface != null
    /** Reel time not yet written, for the surface being watched. */
    fun pending(forSurface: String) = if (surface == forSurface) unflushed else 0L

    @Synchronized
    fun observe(now: Long, current: String?, today: String) {
        if (surface != null && (current != surface || now - last > maxGapMs || today != date)) stop(minOf(now, last))
        if (current == null) return
        if (surface == null) { surface = current; last = now; date = today; unflushed = 0; return }
        unflushed += now - last
        last = now
        if (unflushed >= flushEveryMs) flush()
    }

    @Synchronized
    fun stop(at: Long = last) { flush(); surface = null; last = at }

    private fun flush() {
        val s = surface ?: return
        if (unflushed > 0) sink.addUse(date, s, unflushed)
        unflushed = 0
    }
}

/** Browsers whose address bar the blocker reads (only that one field, only to see if the page is a reel or a short). */
object Browsers {
    val packages = setOf(
        "com.android.chrome", "com.chrome.beta", "com.chrome.dev", "com.brave.browser", "com.microsoft.emmx",
        "org.mozilla.firefox", "org.mozilla.firefox_beta", "com.sec.android.app.sbrowser", "com.opera.browser",
        "com.vivaldi.browser", "com.duckduckgo.mobile.android", "com.kiwibrowser.browser",
    )
    val addressIds = listOf("url_bar", "url_field", "location_bar_edit_text", "mozac_browser_toolbar_url_view", "url_bar_title")
}

/**
 * The penalty for missed daily goals (1.1.1.0, full build): the whole app is blocked through [until] (yyyy-MM-dd, inclusive).
 * The goals are checked in Dart; it tells this side the result. `apps` holds `instagram` and/or `youtube`. Unlike the reel
 * limits it cannot be cancelled for the day.
 */
data class Punish(val until: String?, val apps: Set<String>, val streak: Int) {
    fun blocks(app: String, date: String) = until != null && app in apps && date <= until

    fun toJson(): String = JSONObject().apply {
        put("until", until ?: JSONObject.NULL)
        put("apps", JSONArray(apps.sorted()))
        put("streak", streak)
    }.toString()

    companion object {
        fun parse(json: String?): Punish? = try {
            val o = JSONObject(json ?: return null)
            val a = o.getJSONArray("apps")
            val apps = (0 until a.length()).map { a.getString(it) }.filter { it == "instagram" || it == "youtube" }.toSet()
            val u = if (o.isNull("until")) null else o.getString("until").takeIf { Regex("\\d{4}-\\d{2}-\\d{2}").matches(it) }
            Punish(u, apps, o.optInt("streak", 0))
        } catch (e: Exception) {
            null
        }
    }
}
