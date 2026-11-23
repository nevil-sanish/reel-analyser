package app.reelbrain

import org.json.JSONObject

/**
 * Scroll guard (full build). A swipe is one scroll through a short-video feed (Reels, Shorts, Spotlight, TikTok). A run is swipes that
 * keep coming: it ends when you stop for [quietSec] seconds. The user sets a most swipes a day and/or a most swipes in a run. Past
 * either, the app is closed and the phone goes to the home screen; after a run the feeds stay closed for [pauseMinutes] minutes.
 * A 0 turns that part off. Only swipe counts are kept, never what was scrolled past.
 */
data class ScrollRule(val maxPerDay: Int = 0, val runSwipes: Int = 0, val quietSec: Int = 30, val pauseMinutes: Int = 5) {
    val on get() = maxPerDay > 0 || runSwipes > 0

    fun toJson(): String = JSONObject().put("maxPerDay", maxPerDay).put("runSwipes", runSwipes)
        .put("quietSec", quietSec).put("pauseMinutes", pauseMinutes).toString()

    companion object {
        /** Null for anything malformed or out of range, so a damaged value never blocks. */
        fun parse(json: String?): ScrollRule? = try {
            val o = JSONObject(json ?: return null)
            val r = ScrollRule(o.getInt("maxPerDay"), o.getInt("runSwipes"), o.getInt("quietSec"), o.getInt("pauseMinutes"))
            r.takeIf { it.maxPerDay in 0..5000 && it.runSwipes in 0..500 && it.quietSec in 5..300 && it.pauseMinutes in 1..120 }
        } catch (e: Exception) {
            null
        }
    }
}

sealed class ScrollVerdict {
    object Ok : ScrollVerdict()
    object DayLimit : ScrollVerdict()
    data class Pause(val minutes: Int) : ScrollVerdict()
}

object ScrollGuard {
    /** Scroll events come in bursts for one swipe; events closer than this are the same swipe. */
    const val SWIPE_GAP_MS = 500L

    /** [swipesToday] and [run] include the swipe just made. */
    fun verdict(rule: ScrollRule, swipesToday: Long, run: Int): ScrollVerdict {
        if (rule.maxPerDay > 0 && swipesToday >= rule.maxPerDay) return ScrollVerdict.DayLimit
        if (rule.runSwipes > 0 && run >= rule.runSwipes) return ScrollVerdict.Pause(rule.pauseMinutes)
        return ScrollVerdict.Ok
    }

    fun message(v: ScrollVerdict, rule: ScrollRule, leftMin: Int = 0) = when (v) {
        is ScrollVerdict.DayLimit -> "You have scrolled your ${rule.maxPerDay} swipes for today."
        is ScrollVerdict.Pause -> "${rule.runSwipes} swipes in a row. Take a break for ${maxOf(leftMin, 1)} min."
        else -> ""
    }
}

/** The length of the run of swipes that keep coming: it starts over after a quiet gap. */
class SwipeRun {
    private var last = 0L
    private var n = 0

    /** Records a swipe at [now]; returns how many swipes the run has. */
    fun onSwipe(now: Long, quietMs: Long): Int {
        if (now - last > quietMs) n = 0
        last = now
        return ++n
    }

    fun reset() { n = 0 }
}

/** Turns a stream of scroll events into swipes: a new swipe starts after a quiet gap. */
class SwipeCounter(private val gapMs: Long = ScrollGuard.SWIPE_GAP_MS) {
    private var last = 0L

    /** True when this event starts a new swipe. */
    fun onScroll(now: Long): Boolean {
        val fresh = now - last >= gapMs
        last = now
        return fresh
    }
}
