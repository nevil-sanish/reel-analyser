package app.reelbrain

/** SHARE-IN: finds the reel/short link in shared text and canonicalises it (ENDPOINTS §4). */
object ShareUrls {
    data class Link(val url: String, val app: String, val code: String)

    private val ig = Regex("""https?://(?:www\.)?instagram\.com/(reel|reels|p|tv)/([A-Za-z0-9_-]+)""")
    private val ytShorts = Regex("""https?://(?:www\.|m\.)?youtube\.com/shorts/([A-Za-z0-9_-]{6,})""")
    private val ytBe = Regex("""https?://youtu\.be/([A-Za-z0-9_-]{6,})""")

    /** Rebuilding the URL from its parts drops tracking params (`igsh`, `si`). */
    fun extract(text: String): Link? {
        ig.find(text)?.let { m ->
            val kind = if (m.groupValues[1] == "reels") "reel" else m.groupValues[1]
            val code = m.groupValues[2]
            return Link("https://www.instagram.com/$kind/$code/", "instagram", code)
        }
        (ytShorts.find(text) ?: ytBe.find(text))?.let { m ->
            val id = m.groupValues[1]
            return Link("https://www.youtube.com/shorts/$id", "youtube", id)
        }
        return null
    }
}
