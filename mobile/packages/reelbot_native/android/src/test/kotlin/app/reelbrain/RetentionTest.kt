package app.reelbrain

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The Privacy Policy's retention promises: Insights 90 days, finished queue entries 30 days, erase removes everything. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RetentionTest {
    private val ctx: Context = ApplicationProvider.getApplicationContext()
    private val day = 24L * 3600 * 1000

    @Test fun oldCountsAndFinishedQueueEntriesAreDeleted() {
        val db = CounterDb.get(ctx)
        db.eraseAll()
        db.addScreenTime("2026-06-01", "instagram", 1000) // 159 days before 2026-11-07
        db.addScreenTime("2026-10-01", "instagram", 1000)
        val now = 1_800_000_000_000L
        db.addShared(ShareUrls.Link("https://www.instagram.com/reel/old/", "instagram", "old"), now - 40 * day)
        db.addShared(ShareUrls.Link("https://www.instagram.com/reel/new/", "instagram", "new"), now - 2 * day)
        db.addShared(ShareUrls.Link("https://www.instagram.com/reel/waiting/", "instagram", "waiting"), now - 40 * day)
        for (r in db.pending(null)) if (!(r["url"] as String).endsWith("waiting/")) db.setStatus((r["id"] as Number).toLong(), "done")

        db.prune("2026-11-07", now)

        assertEquals(listOf("2026-10-01"), db.daily(400, "2026-11-07").map { it["date"] })
        // The old finished entry goes; the recent one stays; an old entry still waiting is never dropped.
        assertEquals(setOf("new/", "waiting/"), db.pending(null).map { (it["url"] as String).substringAfter("reel/") }.toSet())
    }

    @Test fun eraseAllLeavesNothing() {
        val db = CounterDb.get(ctx)
        db.addScreenTime("2026-11-07", "youtube", 5)
        db.addShared(ShareUrls.Link("https://youtu.be/abcdefg", "youtube", "abcdefg"), 1L)
        db.eraseAll()
        assertEquals(0, db.pending(null).size)
        assertEquals(0, db.daily(400, "2026-11-07").size)
    }
}
