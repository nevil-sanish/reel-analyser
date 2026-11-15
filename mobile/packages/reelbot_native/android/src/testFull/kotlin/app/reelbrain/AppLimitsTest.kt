package app.reelbrain

import org.junit.Assert.*
import org.junit.Test

class AppLimitsTest {
    @Test fun `host reads addresses as a browser shows them`() {
        assertEquals("example.com", AppLimits.host("https://www.Example.com:8080/a?b=1"))
        assertEquals("example.com", AppLimits.host("example.com/a"))
        assertEquals("m.youtube.com", AppLimits.host("m.youtube.com"))
        assertNull(AppLimits.host("not a site"))
        assertNull(AppLimits.host("localhost"))
    }

    @Test fun `a site matches itself and its subdomains only`() {
        assertTrue(AppLimits.siteMatches("x.com", "https://x.com/home"))
        assertTrue(AppLimits.siteMatches("x.com", "m.x.com/a"))
        assertFalse(AppLimits.siteMatches("x.com", "box.com"))
        assertFalse(AppLimits.siteMatches("x.com", "x.com.evil.org"))
    }

    @Test fun `parse drops protected apps, bad hosts and bad limits`() {
        val json = """[{"kind":"app","id":"com.android.settings","label":"S","limitMin":5},
            {"kind":"app","id":"app.reelbrain","label":"Me","limitMin":5},
            {"kind":"app","id":"com.chrome","label":"C","limitMin":30},
            {"kind":"site","id":"https://www.Reddit.com/r/x","label":"R","limitMin":45},
            {"kind":"site","id":"nodot","label":"N","limitMin":5},
            {"kind":"app","id":"com.a","label":"A","limitMin":0}]"""
        val l = AppLimits.parse(json)!!
        assertEquals(listOf("app:com.chrome", "site:reddit.com"), l.map { it.key })
        assertNull(AppLimits.parse("garbage"))
    }

    @Test fun `limit is reached at the minute count`() {
        val i = LimitItem("app", "com.a", "A", 10)
        assertFalse(AppLimits.isOver(i, 10 * 60_000L - 1))
        assertTrue(AppLimits.isOver(i, 10 * 60_000L))
    }

    @Test fun `first set-up and stricter changes apply at once, others wait for midnight`() {
        val a = listOf(LimitItem("app", "com.a", "A", 10))
        val b = listOf(LimitItem("app", "com.a", "A", 20))
        assertEquals(a, AppLimits.save(LimitsState(), a, false, 0).active)
        val s = AppLimits.save(LimitsState(a), b, false, 1_000_000L)
        assertEquals(a, s.active); assertEquals(b, s.pending)
        assertEquals(b, AppLimits.effective(s, s.pendingFrom).active)
        assertEquals(b, AppLimits.save(LimitsState(a), b, true, 0).active)
    }
}
