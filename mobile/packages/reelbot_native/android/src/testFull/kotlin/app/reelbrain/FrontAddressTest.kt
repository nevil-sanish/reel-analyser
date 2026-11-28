package app.reelbrain

import org.junit.Assert.*
import org.junit.Test

class FrontAddressTest {
    private val chrome = "com.android.chrome"

    @Test fun `typing a site in the address bar is not an open page`() {
        val f = FrontAddress()
        assertNull(f.read(chrome, "youtube.com", typing = true))
        assertEquals("youtube.com", f.read(chrome, "youtube.com", typing = false))
    }

    @Test fun `the page is kept while the address bar is scrolled away`() {
        val f = FrontAddress()
        f.read(chrome, "youtube.com", typing = false)
        assertEquals("youtube.com", f.read(chrome, null, typing = false))
        assertEquals("youtube.com", f.read(chrome, null, typing = false))
    }

    @Test fun `starting to type forgets the open page`() {
        val f = FrontAddress()
        f.read(chrome, "youtube.com", typing = false)
        assertNull(f.read(chrome, "wiki", typing = true))
        assertNull(f.read(chrome, null, typing = false))
    }

    @Test fun `a new address, another browser or clear replaces the page`() {
        val f = FrontAddress()
        f.read(chrome, "youtube.com", typing = false)
        assertEquals("wikipedia.org", f.read(chrome, "wikipedia.org", typing = false))
        assertNull(f.read("org.mozilla.firefox", null, typing = false))
        f.read(chrome, "youtube.com", typing = false)
        f.clear()
        assertNull(f.read(chrome, null, typing = false))
    }
}
