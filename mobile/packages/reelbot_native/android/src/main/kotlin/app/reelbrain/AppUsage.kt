package app.reelbrain

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Time in Instagram and YouTube from Android's usage events (Usage access), no Accessibility needed.
 * It is time in the whole app, not only Reels or Shorts: the system knows which app was open, not what was on screen.
 */
object AppUsage {
    val apps = mapOf("com.instagram.android" to "instagram", "com.google.android.youtube" to "youtube")

    // UsageEvents.Event types; plain ints so this file stays testable on the JVM.
    const val RESUMED = 1
    const val PAUSED = 2
    const val STOPPED = 23
    const val SCREEN_OFF = 16
    const val KEYGUARD_SHOWN = 17
    const val SHUTDOWN = 26

    data class Event(val pkg: String, val type: Int, val time: Long, val cls: String = "")
    data class Session(val app: String, val start: Long, val end: Long)

    /**
     * Foreground sessions of the tracked apps: an app is in front while any of its screens (activity classes) is
     * resumed, so Instagram's overlays (comments, browser, modals) don't cut its time. Screen off or lock ends
     * every session, and one still open runs to [now]. Checked against `dumpsys usagestats` on a phone: this
     * gives the same minutes as Android's own; the first version, which ended a session at any other resume, lost ~20%.
     */
    fun sessions(events: List<Event>, now: Long): List<Session> {
        val out = mutableListOf<Session>()
        val resumed = apps.values.associateWith { mutableSetOf<String>() }
        val start = HashMap<String, Long>()
        fun close(app: String, t: Long) {
            val s = start.remove(app) ?: return
            if (t > s) out += Session(app, s, t)
        }
        for (e in events.sortedBy { it.time }) {
            if (e.type == SCREEN_OFF || e.type == KEYGUARD_SHOWN || e.type == SHUTDOWN) {
                for ((app, screens) in resumed) if (screens.isNotEmpty()) { screens.clear(); close(app, e.time) }
                continue
            }
            val app = apps[e.pkg] ?: continue
            val screens = resumed.getValue(app)
            when (e.type) {
                RESUMED -> if (screens.add(e.cls) && screens.size == 1) start[app] = e.time
                PAUSED, STOPPED -> if (screens.remove(e.cls) && screens.isEmpty()) close(app, e.time)
            }
        }
        for ((app, screens) in resumed) if (screens.isNotEmpty()) close(app, now)
        return out.sortedBy { it.start }
    }

    /** Milliseconds per (local date, app), and per (local hour 0–23, app), splitting sessions at the boundaries. */
    fun split(sessions: List<Session>, zone: ZoneId): Pair<Map<Pair<String, String>, Long>, Map<Pair<Int, String>, Long>> {
        val daily = HashMap<Pair<String, String>, Long>()
        val hourly = HashMap<Pair<Int, String>, Long>()
        for (s in sessions) {
            var t = s.start
            while (t < s.end) {
                val local = Instant.ofEpochMilli(t).atZone(zone)
                val nextHour = local.truncatedTo(ChronoUnit.HOURS).plusHours(1).toInstant().toEpochMilli()
                val stop = minOf(nextHour, s.end)
                daily.merge(local.toLocalDate().toString() to s.app, stop - t, Long::plus)
                hourly.merge(local.hour to s.app, stop - t, Long::plus)
                t = stop
            }
        }
        return daily to hourly
    }

    fun granted(ctx: Context): Boolean = ctx.getSystemService(AppOpsManager::class.java)
        .unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), ctx.packageName) ==
        AppOpsManager.MODE_ALLOWED

    /** Time per (date, app) and per (hour, app) for the last [days] days, today included; null without Usage access. */
    fun load(ctx: Context, days: Int): Pair<Map<Pair<String, String>, Long>, Map<Pair<Int, String>, Long>>? {
        if (!granted(ctx)) return null
        val zone = ZoneId.systemDefault()
        val now = System.currentTimeMillis()
        val from = LocalDate.now(zone).minusDays(days - 1L).atStartOfDay(zone).toInstant().toEpochMilli()
        val raw = ctx.getSystemService(UsageStatsManager::class.java).queryEvents(from, now)
        val events = mutableListOf<Event>()
        val e = UsageEvents.Event()
        while (raw.hasNextEvent()) {
            raw.getNextEvent(e)
            if (e.packageName in apps || e.eventType == SCREEN_OFF || e.eventType == KEYGUARD_SHOWN || e.eventType == SHUTDOWN) {
                events += Event(e.packageName ?: "", e.eventType, e.timeStamp, e.className ?: "")
            }
        }
        return split(sessions(events, now), zone)
    }
}
