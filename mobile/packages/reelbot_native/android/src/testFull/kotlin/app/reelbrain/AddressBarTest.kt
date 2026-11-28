package app.reelbrain

import org.junit.Assert.*
import org.junit.Test

class AddressBarTest {
    @Test fun `firefox shows the address before the hint`() {
        assertEquals("m.youtube.com", FirefoxToolbar.shownAddress(" m.youtube.com. Search or enter address"))
        assertEquals("youtube.com/watch?v=x", FirefoxToolbar.shownAddress("YouTube youtube.com/watch?v=x. Search or enter address"))
    }

    @Test fun `firefox home screen has no address`() {
        assertNull(FirefoxToolbar.shownAddress("Search or enter address"))
        assertNull(FirefoxToolbar.shownAddress(null))
    }

    @Test fun `every known browser id list starts with chrome's`() {
        assertEquals("url_bar", Browsers.addressIds.first())
        assertTrue("org.mozilla.firefox" in Browsers.packages)
        assertTrue("com.brave.browser" in Browsers.packages)
    }
}
