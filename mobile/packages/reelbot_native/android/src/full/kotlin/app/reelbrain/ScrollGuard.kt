package app.reelbrain

import org.json.JSONObject

/**
 * Scroll guard (full build). A swipe is one scroll through a short-video feed (Reels, Shorts, Spotlight, TikTok). The user sets a
 * most swipes a day and/or a burst rule ("[burstSwipes] swipes within [burstMinutes] minutes means a [pauseMinutes] minute pause").
 * A 0 turns that part off. Only swipe counts are kept, never what was scrolled past.
 */
data class ScrollRule(val maxPerDay: Int = 0, val burstSwipes: Int = 0, val burstMinutes: Int = 10, val pauseMinutes: Int = 5) {
    val on get() = maxPerDay > 0 || burstSwipes > 0

    fun toJson(): String = JSONObject().put("maxPerDay", maxPerDay).put("burstSwipes", burstSwipes)
        .put("burstMinutes", burstMinutes).put("pauseMinutes", pauseMinutes).toString()

    companion object {
        /** Null for anything malformed or out of range, so a damaged value never blocks. */
        fun parse(json: String?): ScrollRule? = try {
            val o = JSONObject(json ?: return null)
            val r = ScrollRule(o.getInt("maxPerDay"), o.getInt("burstSwipes"), o.getInt("burstMinutes"), o.getInt("pauseMinutes"))
            r.takeIf { it.maxPerDay in 0..5000 && it.burstSwipes in 0..500 && it.burstMinutes in 1..120 && it.pauseMinutes in 1..120 }
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

    /** [swipesToday] includes the swipe just made; [recent] holds the times of recent swipes, newest last. */
    fun verdict(rule: ScrollRule, swipesToday: Long, recent: List<Long>, now: Long): ScrollVerdict {
        if (rule.maxPerDay > 0 && swipesToday >= rule.maxPerDay) return ScrollVerdict.DayLimit
        if (rule.burstSwipes > 0 && recent.count { it > now - rule.burstMinutes * 60_000L } >= rule.burstSwipes) return ScrollVerdict.Pause(rule.pauseMinutes)
        return ScrollVerdict.Ok
    }

    fun message(v: ScrollVerdict, rule: ScrollRule, leftMin: Int = 0) = when (v) {
        is ScrollVerdict.DayLimit -> "You have scrolled your ${rule.maxPerDay} swipes for today."
        is ScrollVerdict.Pause -> "That was ${rule.burstSwipes} swipes in ${rule.burstMinutes} minutes. Take a break for ${maxOf(leftMin, 1)} more min."
        else -> ""
    }
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
