package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FakeSink : TrackerSink {
    val items = linkedMapOf<Triple<String, String, String>, ItemText>()
    val dwell = mutableMapOf<String, Long>()
    val screen = mutableMapOf<String, Long>()
    val unknown = mutableMapOf<String, Int>()
    override fun commitItem(date: String, app: String, fp: String, firstSeen: Long, item: ItemText) {
        items.putIfAbsent(Triple(date, app, fp), item)
    }
    override fun addDwell(date: String, app: String, fp: String, ms: Long) { dwell.merge(fp, ms, Long::plus) }
    override fun addScreenTime(date: String, app: String, ms: Long) { screen.merge(app, ms, Long::plus) }
    override fun addUnknown(date: String, app: String) { unknown.merge(app, 1, Int::plus) }
}

class ReelTrackerTest {
    private val sink = FakeSink()
    private val t = ReelTracker(sink, dateOf = { "2026-11-06" })
    private var now = 1_000_000L

    /** Stay on [seen] for [ms], observed every 250 ms like the service. */
    private fun watch(seen: ItemText?, ms: Long, app: String = "instagram", inReels: Boolean = true) {
        val stop = now + ms
        while (now < stop) { t.observe(now, app, inReels, seen); now += 250 }
    }

    private fun reel(n: Int) = ItemText(author = "creator$n", caption = "caption number $n")

    // T-TRK-01
    @Test fun twentyReelsOfThreeSeconds() {
        for (i in 1..20) watch(reel(i), 3000)
        t.end(now)
        assertEquals(20, sink.items.size)
    }

    // T-TRK-02
    @Test fun halfSwipeSwipeBackAndRefreshFlickerCountOnce() {
        watch(reel(1), 3000)
        watch(reel(2), 500)
        watch(reel(1), 2000)
        watch(null, 750)
        watch(reel(1), 2000)
        t.end(now)
        assertEquals(1, sink.items.size)
        assertTrue(sink.unknown.isEmpty())
    }

    // T-TRK-03
    @Test fun rewatchLaterTheSameDayCountsOnce() {
        watch(reel(1), 3000); watch(reel(2), 3000); watch(reel(1), 3000)
        t.end(now)
        assertEquals(2, sink.items.size)
    }

    // T-TRK-04
    @Test fun countedLiveWhileStillOnTheReel() {
        watch(reel(1), 2000)
        assertEquals(1, sink.items.size)
    }

    // T-TRK-05
    @Test fun nothingReadableIsUnknown() {
        watch(ItemText(likes = "12K"), 3000)
        t.end(now)
        assertEquals(0, sink.items.size)
        assertEquals(1, sink.unknown["instagram"])
    }

    // T-TRK-06
    @Test fun dwellIsTimeOnTheReel() {
        watch(reel(1), 4000)
        watch(reel(2), 2000)
        val d = sink.dwell[Fingerprint.of("instagram", reel(1))]!!
        assertTrue("dwell $d", d in 3750..4250)
    }

    // T-TRK-07
    @Test fun sleepingGapIsNotScreenTime() {
        watch(reel(1), 10_000)
        now += 60_000
        watch(reel(2), 10_000)
        t.end(now)
        val s = sink.screen["instagram"]!!
        assertTrue("screen $s", s in 19_000..21_000)
    }

    // T-TRK-08
    @Test fun leavingReelsEndsTheSession() {
        watch(reel(1), 2000)
        assertTrue(t.active)
        t.observe(now, "instagram", false, null)
        assertFalse(t.active)
    }

    // T-TRK-09
    @Test fun sameReelOnBothAppsCountsTwice() {
        val same = ItemText(author = "x", title = "how to cook rice")
        watch(same, 2000, app = "instagram")
        watch(same, 2000, app = "youtube")
        t.end(now)
        assertEquals(2, sink.items.size)
    }
}

class FingerprintTest {
    // T-FP-01
    @Test fun truncatedAndExpandedCaptionMatch() {
        val long = "This is a long caption about making bread at home with only four ingredients and no knead"
        assertEquals(
            Fingerprint.of("instagram", ItemText("baker", long.take(50) + "… more")),
            Fingerprint.of("instagram", ItemText("baker", long)),
        )
    }

    // T-FP-02
    @Test fun normalizeStripsMoreAndLess() {
        assertEquals("hello world", Fingerprint.normalize("  Hello\n  World… more"))
        assertEquals("hello world", Fingerprint.normalize("Hello World...more"))
        assertEquals("hello world", Fingerprint.normalize("Hello World less"))
        assertEquals("hello world", Fingerprint.normalize("Hello World…"))
    }

    // T-FP-03
    @Test fun blankIsNull() {
        assertNull(Fingerprint.of("instagram", ItemText(likes = "5K")))
        assertNull(Fingerprint.of("instagram", null))
    }

    // T-FP-04
    @Test fun authorAndAppChangeTheId() {
        val a = Fingerprint.of("instagram", ItemText("a", "c"))
        assertNotEquals(a, Fingerprint.of("instagram", ItemText("b", "c")))
        assertNotEquals(a, Fingerprint.of("youtube", ItemText("a", "c")))
    }

    // T-FP-05
    @Test fun captionlessReelsFromOneCreatorSplitByLikes() {
        assertNotEquals(Fingerprint.of("instagram", ItemText("x", likes = "12K")), Fingerprint.of("instagram", ItemText("x", likes = "340")))
    }

    // T-FP-06
    @Test fun captionlessLikesTickingUpKeepTheId() {
        assertEquals(Fingerprint.of("instagram", ItemText("x", likes = "12.3K")), Fingerprint.of("instagram", ItemText("x", likes = "12.4K")))
    }

    // T-FP-07
    @Test fun captionedReelIgnoresLikes() {
        assertEquals(Fingerprint.of("instagram", ItemText("x", "cap", likes = "1")), Fingerprint.of("instagram", ItemText("x", "cap", likes = "9M")))
    }

    // T-FP-08
    @Test fun likeBuckets() {
        assertEquals("520", Fingerprint.likeBucket("523"))
        assertEquals("12000", Fingerprint.likeBucket("12.3K"))
        assertEquals("1200000", Fingerprint.likeBucket("1.2M"))
        assertEquals("1200", Fingerprint.likeBucket("1,234"))
        assertEquals("", Fingerprint.likeBucket("Like"))
    }
}
