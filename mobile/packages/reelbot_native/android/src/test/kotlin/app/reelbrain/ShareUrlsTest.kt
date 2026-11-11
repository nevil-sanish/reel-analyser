package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareUrlsTest {
    // T-SHARE-01, T-IG-U02
    @Test fun instagramLinkInsideTextLosesTrackingParams() {
        val l = ShareUrls.extract("Check this out! https://www.instagram.com/reel/Cuy8bLvo1Xa/?igsh=MWQ1ZGUx wow")!!
        assertEquals("https://www.instagram.com/reel/Cuy8bLvo1Xa/", l.url)
        assertEquals("instagram", l.app)
        assertEquals("Cuy8bLvo1Xa", l.code)
    }

    @Test fun everyInstagramPathGivesTheSameCode() {
        for (p in listOf("reel", "reels", "p", "tv")) {
            assertEquals("Cuy8bLvo1Xa", ShareUrls.extract("https://instagram.com/$p/Cuy8bLvo1Xa?igsh=x")!!.code)
        }
        assertEquals("https://www.instagram.com/reel/abc/", ShareUrls.extract("https://instagram.com/reels/abc/")!!.url)
    }

    // T-SHARE-02
    @Test fun youtubeLinksBecomeCanonicalShorts() {
        assertEquals("https://www.youtube.com/shorts/dQw4w9WgXcQ", ShareUrls.extract("https://youtube.com/shorts/dQw4w9WgXcQ?si=abc123")!!.url)
        val b = ShareUrls.extract("https://youtu.be/dQw4w9WgXcQ?si=z")!!
        assertEquals("https://www.youtube.com/shorts/dQw4w9WgXcQ", b.url)
        assertEquals("youtube", b.app)
    }

    // T-SHARE-03
    @Test fun nonReelTextIsRejected() {
        assertNull(ShareUrls.extract("hello there"))
        assertNull(ShareUrls.extract("https://www.instagram.com/someuser/"))
        assertNull(ShareUrls.extract("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test fun `linkedin posts lose the tracking query`() {
        val l = ShareUrls.extract("Look https://www.linkedin.com/posts/jasonhaider_when-confronted-ugcPost-7221657670615719939-vqwI?utm_source=social_share_send&rcm=ACoAAE8J now")!!
        assertEquals("https://www.linkedin.com/posts/jasonhaider_when-confronted-ugcPost-7221657670615719939-vqwI", l.url)
        assertEquals("linkedin", l.app)
        assertEquals("7221657670615719939", l.code)
        assertEquals("linkedin", ShareUrls.extract("https://in.linkedin.com/feed/update/urn:li:activity:7525935221964451840/")!!.app)
        assertEquals("https://lnkd.in/gAbC12", ShareUrls.extract("see https://lnkd.in/gAbC12")!!.url)
        assertNull(ShareUrls.extract("https://www.linkedin.com/in/someone"))
    }
}
