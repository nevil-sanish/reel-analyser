package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrollGuardTest {
    private val min = 60_000L

    @Test fun dayLimitBlocksAtTheLimit() {
        val r = ScrollRule(maxPerDay = 100)
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(r, 99, emptyList(), 0))
        assertEquals(ScrollVerdict.DayLimit, ScrollGuard.verdict(r, 100, emptyList(), 0))
    }

    @Test fun burstPausesOnlyWithinTheWindow() {
        val r = ScrollRule(burstSwipes = 5, burstMinutes = 10, pauseMinutes = 3)
        val now = 100 * min
        assertEquals(ScrollVerdict.Pause(3), ScrollGuard.verdict(r, 5, List(5) { now - it * min }, now))
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(r, 5, listOf(now - 30 * min, now - 20 * min, now - 11 * min, now - min, now), now))
    }

    @Test fun zeroTurnsAPartOff() {
        assertFalse(ScrollRule().on)
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(ScrollRule(), 99999, List(500) { it.toLong() }, 1000))
    }

    @Test fun parseRejectsDamagedValues() {
        assertNull(ScrollRule.parse(null))
        assertNull(ScrollRule.parse("{}"))
        assertNull(ScrollRule.parse(ScrollRule(maxPerDay = -1).toJson()))
        assertNull(ScrollRule.parse(ScrollRule(burstSwipes = 5, burstMinutes = 0).toJson()))
        val r = ScrollRule(200, 20, 10, 5)
        assertEquals(r, ScrollRule.parse(r.toJson()))
    }

    @Test fun eventsInOneSwipeCountOnce() {
        val c = SwipeCounter(500)
        assertTrue(c.onScroll(1000))
        assertFalse(c.onScroll(1100)) // the same swipe
        assertFalse(c.onScroll(1400))
        assertTrue(c.onScroll(2000))
    }
}
