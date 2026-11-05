package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Fixture tests. The `-synthetic` fixtures follow the documented shapes; add real captures beside them. */
class IgParseTest {
    private fun fx(name: String) = javaClass.classLoader!!.getResource("ig/$name")!!.readText()

    // T-IG-U01
    @Test fun shortcodeDecodesToMediaId() {
        assertEquals("0", IgParse.mediaId("A"))
        assertEquals("1", IgParse.mediaId("B"))
        assertEquals("64", IgParse.mediaId("BA"))
        assertEquals("63", IgParse.mediaId("_"))
        for (code in listOf("Cuy8bLvo1Xa", "DBhq5oYyQ1-", "B_9xKq3hj4p")) {
            assertEquals(code, IgParse.shortcode(IgParse.mediaId(code)))
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidShortcodeCharacterFails() { IgParse.mediaId("abc!") }

    // T-IG-F01
    @Test fun embedWithContextJson() {
        val m = IgParse.embed(fx("ig-embed-video-synthetic.html"))!!
        assertTrue(m.videoUrl.startsWith("https://scontent.cdninstagram.com/v/reel.mp4"))
        assertEquals("How to cook rice", m.caption)
        assertEquals("chef.anna", m.author)
    }

    // T-IG-F02
    @Test fun embedWithoutGqlData() {
        assertNull(IgParse.embed(fx("ig-embed-nodata-synthetic.html")))
        assertNull(IgParse.embed("<html>nothing</html>"))
    }

    // T-IG-F03
    @Test fun postPageFindsItemByPkAndPicks480() {
        val m = IgParse.postPage(listOf("not json", fx("ig-postpage-sjs-synthetic.json")), "3141592653589793238")!!
        assertEquals("https://cdn/720.mp4", m.videoUrl)
        assertEquals("https://cdn/thumb.jpg", m.thumbnailUrl)
        assertEquals("Leg day tips", m.caption)
        assertEquals("gym.raj", m.author)
        assertNull(IgParse.postPage(listOf(fx("ig-postpage-sjs-synthetic.json")), "1"))
        assertEquals("AVq1-lsdTOKEN", IgParse.lsd(fx("ig-postpage-lsd-synthetic.html")))
    }

    // T-IG-F05, T-IG-F06
    @Test fun loggedOutQuery() {
        val r = IgParse.gql(fx("ig-gql-loggedout-video-synthetic.json"), web = false)
        assertEquals("https://cdn/720.mp4", (r as IgParse.Gql.Found).media.videoUrl)
        assertEquals(IgParse.Gql.Stale, IgParse.gql(fx("ig-gql-loggedout-stale-synthetic.json"), web = false))
        assertEquals(IgParse.Gql.RequireLogin, IgParse.gql("""{"require_login":true,"status":"fail"}""", web = false))
    }

    // T-IG-F07
    @Test fun webQuery() {
        val r = IgParse.gql(fx("ig-gql-web-video-synthetic.json"), web = true) as IgParse.Gql.Found
        assertEquals("chef.anna", r.media.author)
        assertTrue(r.media.hasVideo)
        assertEquals(IgParse.Gql.Missing, IgParse.gql(fx("ig-gql-web-null-synthetic.json"), web = true))
    }

    // T-IG-F08
    @Test fun oembedMetadata() {
        val m = IgParse.oembed(fx("ig-oembed-synthetic.json"))!!
        assertEquals("Leg day tips", m.caption)
        assertEquals("gym.raj", m.author)
        assertEquals("https://cdn/oe-thumb.jpg", m.thumbnailUrl)
        assertTrue(m.videoUrl.isEmpty())
    }

    // T-IG-F09
    @Test fun bundleDocIds() {
        val js = fx("ig-bundle-synthetic.js")
        assertEquals("27999999999999999", IgParse.docIdFromBundle(js, "PolarisLoggedOutDesktopWWWPostRootContentQuery"))
        assertEquals("25888888888888888", IgParse.docIdFromBundle(js, "PolarisPostActionLoadPostQueryQuery"))
        assertNull(IgParse.docIdFromBundle(js, "Missing"))
    }

    // T-IG-F10
    @Test fun carouselsGiveFirstVideo() {
        val a = IgParse.gql(fx("ig-gql-loggedout-carousel-synthetic.json"), web = false) as IgParse.Gql.Found
        assertEquals("https://cdn/c2.mp4", a.media.videoUrl)
        assertEquals("https://cdn/c1.jpg", a.media.thumbnailUrl)
        val b = IgParse.gql(fx("ig-gql-web-carousel-synthetic.json"), web = true) as IgParse.Gql.Found
        assertEquals("https://cdn/c2.mp4", b.media.videoUrl)
    }

    // T-IG-U03
    @Test fun cdnExpiryAndSizeCap() {
        assertEquals(0x6A000000L, IgParse.cdnExpiry("https://x/v.mp4?_nc=1&oe=6A000000&b=2"))
        assertNull(IgParse.cdnExpiry("https://x/v.mp4"))
        assertTrue(IgParse.isExpired("https://x/v.mp4?oe=10", 16_000))
        assertFalse(IgParse.isExpired("https://x/v.mp4?oe=10", 15_999))
        assertFalse(IgParse.isExpired("https://x/v.mp4", Long.MAX_VALUE))
        val out = java.io.ByteArrayOutputStream()
        assertTrue(IgParse.copyCapped(ByteArray(1000).inputStream(), out, 1000))
        assertEquals(1000, out.size())
        assertFalse(IgParse.copyCapped(ByteArray(1001).inputStream(), java.io.ByteArrayOutputStream(), 1000))
    }
}
