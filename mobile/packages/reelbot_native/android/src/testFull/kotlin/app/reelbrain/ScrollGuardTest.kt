package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrollGuardTest {
    @Test fun dayLimitBlocksAtTheLimit() {
        val r = ScrollRule(maxPerDay = 100)
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(r, 99, 1))
        assertEquals(ScrollVerdict.DayLimit, ScrollGuard.verdict(r, 100, 1))
    }

    @Test fun aRunPausesAtItsLength() {
        val r = ScrollRule(runSwipes = 5, quietSec = 30, pauseMinutes = 3)
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(r, 4, 4))
        assertEquals(ScrollVerdict.Pause(3), ScrollGuard.verdict(r, 5, 5))
    }

    @Test fun aRunEndsAfterAQuietGap() {
        val run = SwipeRun()
        assertEquals(1, run.onSwipe(0, 30_000))
        assertEquals(2, run.onSwipe(20_000, 30_000)) // keeps coming
        assertEquals(3, run.onSwipe(49_000, 30_000))
        assertEquals(1, run.onSwipe(100_000, 30_000)) // a quiet gap: a new run
        run.reset()
        assertEquals(1, run.onSwipe(101_000, 30_000))
    }

    @Test fun zeroTurnsAPartOff() {
        assertFalse(ScrollRule().on)
        assertEquals(ScrollVerdict.Ok, ScrollGuard.verdict(ScrollRule(), 99999, 500))
    }

    @Test fun parseRejectsDamagedValues() {
        assertNull(ScrollRule.parse(null))
        assertNull(ScrollRule.parse("{}"))
        assertNull(ScrollRule.parse(ScrollRule(maxPerDay = -1).toJson()))
        assertNull(ScrollRule.parse(ScrollRule(runSwipes = 5, quietSec = 1).toJson()))
        val r = ScrollRule(200, 20, 30, 5)
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
