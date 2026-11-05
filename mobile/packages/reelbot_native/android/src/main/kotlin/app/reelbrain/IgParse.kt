package app.reelbrain

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigInteger

/** What any Instagram step could read about a post. Empty strings mean "not found". */
data class IgMedia(
    val videoUrl: String = "",
    val thumbnailUrl: String = "",
    val caption: String = "",
    val author: String = "",
) {
    val hasVideo get() = videoUrl.isNotEmpty()
    val hasMeta get() = thumbnailUrl.isNotEmpty() || caption.isNotEmpty() || author.isNotEmpty()

    /** Keeps this media's fields and fills the blanks from [other]. */
    fun fill(other: IgMedia) = IgMedia(
        videoUrl.ifEmpty { other.videoUrl },
        thumbnailUrl.ifEmpty { other.thumbnailUrl },
        caption.ifEmpty { other.caption },
        author.ifEmpty { other.author },
    )
}

/** Parsers for every IG-* response (ENDPOINTS §2). Pure, so fixtures can drive them on the JVM. */
object IgParse {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    /** Shortcode → media id: base-64, most-significant first. Too big for a Long on long codes. */
    fun mediaId(code: String): String {
        var n = BigInteger.ZERO
        for (c in code) {
            val v = ALPHABET.indexOf(c)
            require(v >= 0) { "bad shortcode character '$c'" }
            n = n.shiftLeft(6).add(BigInteger.valueOf(v.toLong()))
        }
        return n.toString()
    }

    fun shortcode(mediaId: String): String {
        var n = BigInteger(mediaId)
        if (n.signum() == 0) return "A"
        val sb = StringBuilder()
        val b64 = BigInteger.valueOf(64)
        while (n.signum() > 0) {
            sb.append(ALPHABET[n.mod(b64).toInt()])
            n = n.shiftRight(6)
        }
        return sb.reverse().toString()
    }

    private val embedInit = Regex(""""init",\[\],\[(.*?)\]\],""")

    /** IG-EMBED: `contextJSON` → `gql_data.shortcode_media`. Null when Instagram left the data out. */
    fun embed(html: String): IgMedia? {
        for (m in embedInit.findAll(html)) {
            val obj = runCatching { JSONObject(m.groupValues[1]) }.getOrNull() ?: continue
            val ctx = obj.optString("contextJSON").ifEmpty { continue }
            val gql = runCatching { JSONObject(ctx) }.getOrNull()?.optJSONObject("gql_data") ?: return null
            val media = gql.optJSONObject("shortcode_media") ?: gql.optJSONObject("xdt_shortcode_media") ?: return null
            return shortcodeMedia(media)
        }
        return null
    }

    /** The `shortcode_media` shape used by the embed page and the web GraphQL query. */
    fun shortcodeMedia(m: JSONObject): IgMedia {
        var video = m.optString("video_url")
        if (video.isEmpty()) {
            val kids = m.optJSONObject("edge_sidecar_to_children")?.optJSONArray("edges")
            video = firstOf(kids) { it.optJSONObject("node")?.optString("video_url").orEmpty() }
        }
        val caption = m.optJSONObject("edge_media_to_caption")?.optJSONArray("edges")
            ?.optJSONObject(0)?.optJSONObject("node")?.optString("text").orEmpty()
        return IgMedia(
            videoUrl = video,
            thumbnailUrl = m.optString("display_url"),
            caption = caption,
            author = m.optJSONObject("owner")?.optString("username").orEmpty(),
        )
    }

    /** The `xig_polaris_media` item shape used by the post page and the logged-out query. */
    fun polarisItem(item: JSONObject): IgMedia {
        var video = pickVideo(item.optJSONArray("video_versions"))
        var thumb = item.optJSONObject("image_versions2")?.optJSONArray("candidates")
            ?.optJSONObject(0)?.optString("url").orEmpty()
        val carousel = item.optJSONArray("carousel_media")
        if (video.isEmpty()) video = firstOf(carousel) { pickVideo(it.optJSONArray("video_versions")) }
        if (thumb.isEmpty()) thumb = firstOf(carousel) {
            it.optJSONObject("image_versions2")?.optJSONArray("candidates")?.optJSONObject(0)?.optString("url").orEmpty()
        }
        return IgMedia(
            videoUrl = video,
            thumbnailUrl = thumb,
            caption = item.optJSONObject("caption")?.optString("text").orEmpty(),
            author = item.optJSONObject("user")?.optString("username").orEmpty(),
        )
    }

    /** Smallest rendition at least 480 px wide, else the widest one. */
    fun pickVideo(versions: JSONArray?): String {
        if (versions == null || versions.length() == 0) return ""
        val all = (0 until versions.length()).mapNotNull { versions.optJSONObject(it) }.filter { it.optString("url").isNotEmpty() }
        val ok = all.filter { it.optInt("width") >= 480 }.minByOrNull { it.optInt("width") }
        return (ok ?: all.maxByOrNull { it.optInt("width") })?.optString("url").orEmpty()
    }

    /** IG-POST-PAGE: walks each `data-sjs` script's JSON for the item whose `pk`/`id` is [mediaId]. */
    private val mp4 = Regex("""^https://[^/]*(cdninstagram\.com|fbcdn\.net)/.*\.mp4""")
    private val rangeParams = Regex("""[&?](bytestart|byteend)=\d+""")

    /**
     * A video request seen by the player WebView, as a whole-file link: Instagram fetches ranges
     * (`bytestart`/`byteend`), and the same URL without them returns the full file.
     */
    fun progressiveMp4(url: String): String? =
        url.takeIf { mp4.containsMatchIn(it) }?.replace(rangeParams, "")?.replace(".mp4&", ".mp4?")

    /** Step 2: what the embed player showed. The caption block starts with the username; that is dropped. */
    fun player(videoSrc: String, interceptedMp4: String, poster: String, author: String, caption: String): IgMedia? {
        val video = videoSrc.takeIf { it.startsWith("https://") } ?: interceptedMp4
        val a = author.trim().removePrefix("@")
        val c = caption.trim().removePrefix(a).trim().substringBefore("\nView all").trim()
        return IgMedia(video, poster, c, a).takeIf { it.hasVideo || it.hasMeta }
    }

    private val ogDesc = Regex("""- ([\w.]+) on [^:]*: ["“](.*)["”]\.?$""", RegexOption.DOT_MATCHES_ALL)

    /**
     * Step 2 fallback: what the page actually rendered. The `<video>` element's src (when it isn't a blob:),
     * else a `"video_url"` left in the HTML, plus the og: tags for the caption and thumbnail.
     */
    fun rendered(videoSrc: String, videoUrlRaw: String, ogImage: String, ogDescription: String): IgMedia? {
        val video = videoSrc.takeIf { it.startsWith("https://") }
            ?: videoUrlRaw.replace("\\u0026", "&").replace("\\/", "/").takeIf { it.startsWith("https://") } ?: ""
        val m = ogDesc.find(ogDescription.trim())
        val media = IgMedia(video, ogImage, m?.groupValues?.get(2) ?: "", m?.groupValues?.get(1) ?: "")
        return media.takeIf { it.hasVideo || it.hasMeta }
    }

    fun postPage(scripts: List<String>, mediaId: String): IgMedia? {
        for (s in scripts) {
            val root = runCatching { JSONObject(s) }.getOrNull() ?: runCatching { JSONArray(s) }.getOrNull() ?: continue
            findItem(root, mediaId)?.let { return polarisItem(it) }
        }
        return null
    }

    private fun findItem(node: Any?, mediaId: String): JSONObject? {
        when (node) {
            is JSONObject -> {
                val id = node.opt("pk")?.toString() ?: node.opt("id")?.toString()
                val idMatches = id == mediaId || id?.substringBefore('_') == mediaId
                if (idMatches && (node.has("video_versions") || node.has("carousel_media") || node.has("image_versions2"))) return node
                for (k in node.keys()) findItem(node.opt(k), mediaId)?.let { return it }
            }
            is JSONArray -> for (i in 0 until node.length()) findItem(node.opt(i), mediaId)?.let { return it }
        }
        return null
    }

    sealed interface Gql {
        data class Found(val media: IgMedia) : Gql
        object Missing : Gql
        object Stale : Gql
        object RequireLogin : Gql
    }

    /** IG-GQL-LOGGEDOUT and IG-GQL-WEB responses. */
    fun gql(body: String, web: Boolean): Gql {
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return Gql.Stale
        if (o.optBoolean("require_login")) return Gql.RequireLogin
        // ENDPOINTS: "no `data` or an error mentioning the document" both mean the doc_id rotated.
        val data = o.optJSONObject("data") ?: return Gql.Stale
        if (web) {
            val m = data.optJSONObject("xdt_shortcode_media") ?: data.optJSONObject("shortcode_media") ?: return Gql.Missing
            return Gql.Found(shortcodeMedia(m))
        }
        val item = data.optJSONObject("xig_polaris_media")?.optJSONObject("if_not_gated_logged_out") ?: return Gql.Missing
        return Gql.Found(polarisItem(item))
    }

    /** IG-OEMBED: metadata only. */
    fun oembed(body: String): IgMedia? {
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return null
        return IgMedia(
            thumbnailUrl = o.optString("thumbnail_url"),
            caption = o.optString("title"),
            author = o.optString("author_name"),
        ).takeIf { it.hasMeta }
    }

    private val lsdRe = Regex("""\["LSD",\[\],\{"token":"([^"]+)"""")
    fun lsd(html: String): String = lsdRe.find(html)?.groupValues?.get(1).orEmpty()

    /** IG-JS-BUNDLE: the `doc_id` a bundle assigns to the [name] query, or null. */
    fun docIdFromBundle(js: String, name: String): String? =
        Regex(""""${Regex.escape(name)}_instagramRelayOperation",\[\],\(function\([^)]*\)\{\w+\.exports="(\d+)"""")
            .find(js)?.groupValues?.get(1)

    /** `oe=` is the CDN link's expiry as hex Unix seconds. */
    fun cdnExpiry(url: String): Long? =
        Regex("""[?&]oe=([0-9A-Fa-f]+)""").find(url)?.groupValues?.get(1)?.toLongOrNull(16)

    fun isExpired(url: String, nowMs: Long): Boolean = cdnExpiry(url)?.let { it * 1000 <= nowMs } ?: false

    /** IG-CDN: copies at most [max] bytes; false (stop) when the stream is bigger. */
    fun copyCapped(input: java.io.InputStream, output: java.io.OutputStream, max: Long): Boolean {
        val buf = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buf)
            if (n < 0) return true
            total += n
            if (total > max) return false
            output.write(buf, 0, n)
        }
    }

    private inline fun firstOf(arr: JSONArray?, pick: (JSONObject) -> String): String {
        if (arr == null) return ""
        for (i in 0 until arr.length()) {
            val v = arr.optJSONObject(i)?.let(pick).orEmpty()
            if (v.isNotEmpty()) return v
        }
        return ""
    }
}
