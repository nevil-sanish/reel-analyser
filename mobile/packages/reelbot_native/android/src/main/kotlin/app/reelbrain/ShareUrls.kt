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

    /**
     * A URL-less row from a bubble Save gets the next shared link if it is under 2 min old (IMPLEMENTATION §2.2).
     * v0.5.0: was 10 s, too short for a manual Share; the Dart runner waits the same 2 min before going text-only.
     */
    fun shouldAttach(newestUrl: String?, newestCreatedAt: Long?, now: Long): Boolean =
        newestCreatedAt != null && newestUrl.isNullOrEmpty() && now - newestCreatedAt in 0 until 120_000
}
