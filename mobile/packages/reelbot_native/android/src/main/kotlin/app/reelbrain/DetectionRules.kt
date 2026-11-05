package app.reelbrain

import java.util.Locale

data class Box(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val height get() = bottom - top
    val centerY get() = (top + bottom) / 2
    fun intersects(o: Box) = left < o.right && o.left < right && top < o.bottom && o.top < bottom
    fun contains(o: Box) = o.left >= left && o.right <= right && o.top >= top && o.bottom <= bottom
}

/** One accessibility node, without Android types. `id` is the part after `:id/`. */
data class NodeSnap(
    val id: String = "", val cls: String = "", val text: String = "", val desc: String = "",
    val bounds: Box, val visible: Boolean = true,
) {
    val label get() = text.ifBlank { desc }.trim()
}

data class Observation(val inReels: Boolean, val item: ItemText?)

/**
 * Everything that depends on Instagram/YouTube layouts (IMPLEMENTATION §3.2).
 * The id lists are the doc's starting guesses: replace them with ids from the debug screen's capture (§3.0).
 */
object DetectionRules {
    val apps = mapOf("com.instagram.android" to "instagram", "com.google.android.youtube" to "youtube")

    /** They briefly cover a reel without you leaving it. */
    val ignored = setOf(
        "com.android.systemui", "app.reelbrain",
        "com.google.android.inputmethod.latin", "com.samsung.android.honeyboard", "com.touchtype.swiftkey",
    )

    private class Ids(
        val screen: Set<String>, val page: Set<String>, val author: List<String>, val caption: List<String>,
        val audio: List<String>, val title: List<String>, val likes: List<String>,
    )

    private val ids = mapOf(
        "instagram" to Ids(
            screen = setOf("clips_viewer_view_pager", "clips_viewer_root", "clips_viewer_root_layout", "clips_video_container",
                "clips_swipe_refresh_container", "clips_tab"),
            page = setOf("clips_viewer_page", "clips_item_container", "clips_media_component", "clips_video_container"),
            author = listOf("clips_author_username", "clips_author_info_component", "row_feed_photo_profile_name", "username"),
            caption = listOf("clips_caption_component", "clips_caption", "clips_caption_text", "caption_text"),
            audio = listOf("clips_audio_attribution", "clips_music_attribution", "audio_attribution", "music_attribution_text"),
            title = emptyList(),
            likes = listOf("like_count", "clips_like_count", "likes_count"),
        ),
        "youtube" to Ids(
            screen = setOf("reel_recycler", "reel_player_page_container", "reel_watch_player", "reel_watch_fragment_root", "shorts_container"),
            page = setOf("reel_player_page_container", "reel_watch_player"),
            author = listOf("reel_channel_name", "channel_name", "reel_channel_bar_inner_container"),
            caption = emptyList(),
            audio = listOf("reel_sound_metadata", "reel_music_metadata"),
            title = listOf("reel_multi_format_title", "reel_title", "shorts_video_title"),
            likes = listOf("like_button", "reel_like_button"),
        ),
    )

    private val noiseWords = setOf(
        "like", "liked", "comment", "comments", "share", "send", "save", "saved", "remix", "follow", "following",
        "subscribe", "subscribed", "more", "less", "original audio", "home", "reels", "search", "explore", "profile",
        "shorts", "subscriptions", "you", "create", "dislike", "audio",
    )
    private val count = Regex("^[0-9][0-9,]*(\\.[0-9]+)?\\s*[KkMmBb]?$")
    private val age = Regex("^\\d+\\s*(s|m|h|d|w|y|mo|sec|min|hr|day|days|week|weeks|year|years)( ago)?$", RegexOption.IGNORE_CASE)
    private val handle = Regex("^[\\w.]{2,30}$")

    fun isNoise(label: String): Boolean {
        val l = label.trim()
        return l.isEmpty() || l.lowercase(Locale.ROOT) in noiseWords || count.matches(l) || age.matches(l)
    }

    fun read(app: String, nodes: List<NodeSnap>, screen: Box): Observation {
        val r = ids[app] ?: return Observation(false, null)
        if (nodes.none { it.id in r.screen }) return Observation(false, null)
        var seen = nodes.filter { it.visible && it.bounds.intersects(screen) }
        // Mid-swipe two pages are on screen; the one covering the centre is the reel being watched.
        seen.firstOrNull { it.id in r.page && it.bounds.height * 2 >= screen.height && screen.centerY in it.bounds.top..it.bounds.bottom }
            ?.let { page -> seen = seen.filter { page.bounds.contains(it.bounds) } }

        fun first(list: List<String>) = list.firstNotNullOfOrNull { id ->
            seen.firstOrNull { it.id == id && !isNoise(it.label) }?.label
        } ?: ""
        val likes = r.likes.firstNotNullOfOrNull { id ->
            seen.firstOrNull { it.id == id && Fingerprint.likeBucket(it.label).isNotEmpty() }?.label
        } ?: ""
        val item = ItemText(first(r.author).removePrefix("@"), first(r.caption), first(r.audio), first(r.title), likes)
        if (item.author.isBlank() && item.caption.isBlank() && item.title.isBlank()) {
            return Observation(true, fallbackItem(seen, screen).copy(audio = item.audio, likes = likes))
        }
        return Observation(true, item)
    }

    /** No known ids matched: guess from the text in the bottom half, where both apps put author and caption. */
    private fun fallbackItem(nodes: List<NodeSnap>, screen: Box): ItemText {
        val labels = nodes.filter { it.bounds.centerY >= screen.centerY && !isNoise(it.label) }
            .sortedBy { it.bounds.top }.map { it.label }.distinct()
        val author = labels.firstOrNull { it.startsWith("@") || handle.matches(it) }
        return ItemText(author = author?.removePrefix("@") ?: "", caption = labels.filter { it != author }.joinToString(" "))
    }
}
