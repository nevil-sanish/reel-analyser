package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DigestTest {
    // T-DIG-01 (rule and text)
    @Test fun notOpenedTodayWithTitles() {
        assertTrue(Digest.shouldPost(openedToday = false, postedToday = false, hour = 21))
        assertEquals("37 reels · 52 min · 3 saved: Bread, Rice, Knots",
            Digest.text(37, 52 * 60000 + 59000, 3, listOf("Bread", "Rice", "Knots", "Extra")))
    }

    // T-DIG-02 (rule and text)
    @Test fun countsOnlyAndWhenNotToPost() {
        assertEquals("5 reels · 2 min · 1 saved", Digest.text(5, 120000, 1, emptyList()))
        assertTrue(Digest.text(0, 0, 0, emptyList()).startsWith("Nothing saved today"))
        assertFalse(Digest.shouldPost(openedToday = true, postedToday = false, hour = 22))
        assertFalse(Digest.shouldPost(openedToday = false, postedToday = true, hour = 22))
        assertFalse(Digest.shouldPost(openedToday = false, postedToday = false, hour = 20))
    }

    // T-DIG-03: only what is tracked; no "0 reels" when the optional counter is off.
    @Test fun untrackedPartsAreLeftOut() {
        assertEquals("42 min · 2 saved: Rice", Digest.text(null, 42 * 60000, 2, listOf("Rice")))
        assertEquals("1 saved", Digest.text(null, null, 1, emptyList()))
        assertEquals("42 min · 0 saved", Digest.text(null, 42 * 60000, 0, emptyList()))
        assertTrue(Digest.text(null, null, 0, emptyList()).startsWith("Nothing saved today"))
    }
}
