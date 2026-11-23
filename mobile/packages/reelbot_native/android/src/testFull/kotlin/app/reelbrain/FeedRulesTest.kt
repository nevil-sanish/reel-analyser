package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedRulesTest {
    private fun n(id: String, visible: Boolean = true) = NodeSnap(id = id, bounds = Box(0, 0, 1080, 2400), visible = visible)

    @Test fun snapchatSpotlightNeedsItsContainerOnScreen() {
        assertTrue(DetectionRules.feedOn("snapchat", listOf(n("spotlight_container"))))
        assertFalse(DetectionRules.feedOn("snapchat", listOf(n("camera_view"))))
        assertFalse(DetectionRules.feedOn("snapchat", listOf(n("spotlight_container", visible = false))))
    }

    @Test fun tiktokIsAlwaysAFeed() {
        assertTrue(DetectionRules.feedOn("tiktok", emptyList()))
    }

    @Test fun allTiktokVariantsAreKnownAndNotCounted() {
        for (p in listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill", "com.ss.android.ugc.aweme", "com.zhiliaoapp.musically.go"))
            assertEquals("tiktok", DetectionRules.apps[p])
        assertEquals("snapchat", DetectionRules.apps["com.snapchat.android"])
        assertFalse("tiktok" in DetectionRules.counted)
    }

    @Test fun newSurfacesAreBlockableAndNamed() {
        assertTrue("snapchat" in BlockConfig.surfaces && "tiktok" in BlockConfig.surfaces)
        assertEquals("Snapchat Spotlight", BlockPolicy.name("snapchat"))
        assertEquals("Snapchat", BlockPolicy.name("snapchat", true))
        assertEquals("TikTok", BlockPolicy.name("tiktok"))
        val c = BlockConfig.parse("""{"mode":"separate","items":["tiktok","snapchat"],"wholeApp":["snapchat","tiktok"],"rules":{"tiktok":{"limitMin":10,"intervals":[]}}}""")!!
        assertEquals(setOf("snapchat"), c.wholeApp) // TikTok always counts whole, so it is not a choice
    }
}
