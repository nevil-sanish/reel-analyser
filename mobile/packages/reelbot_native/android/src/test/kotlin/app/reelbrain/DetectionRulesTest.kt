package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DetectionRulesTest {
    private val screen = Box(0, 0, 1080, 2400)
    private fun n(id: String, text: String, top: Int, bottom: Int = top + 60, visible: Boolean = true) =
        NodeSnap(id = id, text = text, bounds = Box(0, top, 1080, bottom), visible = visible)
    private val root = n("clips_viewer_root", "", 0, 2400)

    // T-RULE-01
    @Test fun notOnReels() {
        assertFalse(DetectionRules.read("instagram", listOf(n("feed_list", "", 0, 2400)), screen).inReels)
    }

    // The Reels button of the bottom bar is on screen in the feed too: it must not count as being on Reels (1.0.9.0: the blocker blocked the whole app).
    @Test fun reelsTabButtonAloneIsNotReels() {
        val feed = listOf(n("tab_bar", "", 2200, 2400), n("feed_tab", "", 2200, 2400), n("clips_tab", "", 2200, 2400), n("row_feed_photo_profile_name", "someone", 300))
        assertFalse(DetectionRules.read("instagram", feed, screen).inReels)
    }

    // T-RULE-02
    @Test fun knownIdsAreRead() {
        val o = DetectionRules.read("instagram", listOf(
            root, n("clips_author_username", "chef.anna", 1900), n("clips_caption_text", "Five minute pasta… more", 2000),
            n("like_count", "12.3K", 1200), n("like_count", "Like", 1100),
        ), screen)
        assertTrue(o.inReels)
        assertEquals(ItemText("chef.anna", "Five minute pasta… more", likes = "12.3K"), o.item)
    }

    // T-RULE-03
    @Test fun fallbackSkipsCountsAndButtons() {
        val o = DetectionRules.read("youtube", listOf(
            n("reel_recycler", "", 0, 2400), n("", "Top text", 300), n("", "12.3K", 1500), n("", "Subscribe", 1800),
            n("", "@cooking.daily", 1900), n("", "Rice in 3 steps", 2000),
        ), screen)
        assertEquals("cooking.daily", o.item!!.author)
        assertEquals("Rice in 3 steps", o.item!!.caption)
    }

    // T-RULE-04
    @Test fun midSwipePageCoveringTheCentreWins() {
        val o = DetectionRules.read("instagram", listOf(
            root,
            n("clips_viewer_page", "", -1800, 600), n("clips_author_username", "leaving", 500),
            n("clips_viewer_page", "", 600, 3000), n("clips_author_username", "arriving", 2000),
        ), screen)
        assertEquals("arriving", o.item!!.author)
    }

    // T-RULE-05
    @Test fun invisibleNodesIgnored() {
        val o = DetectionRules.read("instagram", listOf(
            root, n("clips_author_username", "ghost", 1900, visible = false), n("clips_author_username", "real", 1950),
        ), screen)
        assertEquals("real", o.item!!.author)
    }
}
