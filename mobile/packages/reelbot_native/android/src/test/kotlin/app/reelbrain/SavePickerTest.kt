package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SavePickerTest {
    private fun n(id: String = "", text: String = "", desc: String = "", visible: Boolean = true) =
        NodeSnap(id = id, text = text, desc = desc, bounds = Box(0, 0, 10, 10), visible = visible)

    // T-SAVE-03
    @Test fun shareButtonByIdThenDescription() {
        assertEquals(1, SavePicker.share("instagram", listOf(n(desc = "Like"), n(id = "clips_share_button"), n(desc = "Share"))))
        assertEquals(2, SavePicker.share("youtube", listOf(n(desc = "Like"), n(desc = "Share", visible = false), n(desc = "Share"))))
        assertNull(SavePicker.share("youtube", listOf(n(desc = "Comment"))))
    }

    @Test fun sheetFindsReelBotOrMore() {
        val sheet = listOf(n(text = "Copy link"), n(text = "Share to…"), n(text = "Reel Bot"))
        assertEquals(2, SavePicker.reelBot(sheet))
        assertEquals(1, SavePicker.more(sheet))
        assertNull(SavePicker.reelBot(listOf(n(text = "Reel Bot", visible = false))))
    }
}
