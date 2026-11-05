package app.reelbrain

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import app.reelbrain.core.R
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Runs Instagram cascade steps 1–6 (PLAN §3.2, ENDPOINTS §2) and downloads the video in the same call.
 * v0.6.2 added step 2 (the embed player), so the post page is 3, the GraphQL calls 4–5 and oEmbed 6.
 * Steps 2–5 run in a hidden WebView: it is real Chrome, so the logged-out endpoints answer it
 * without faking a TLS fingerprint, and its cookie jar is separate from the Instagram app's.
 * Step 7 (Apify) is in Dart. Never logs in.
 */
class InstagramFetcher private constructor(private val ctx: Context) {
    companion object {
        private const val IG_APP_ID = "936619743392459"
        private const val MAX_VIDEO = 100L * 1024 * 1024
        private const val TIMEOUT_MS = 20_000

        @Volatile private var instance: InstagramFetcher? = null
        fun get(ctx: Context): InstagramFetcher =
            instance ?: synchronized(this) { instance ?: InstagramFetcher(ctx.applicationContext).also { instance = it } }

        // Collects what steps 3–5 need from the loaded post page.
        private const val COLLECT_JS = """(function(){
  var s=[];document.querySelectorAll('script[data-sjs],script[type="application/json"]').forEach(function(e){s.push(e.textContent)});
  var m=document.documentElement.innerHTML.match(/\["LSD",\[\],\{"token":"([^"]+)"/);
  var b=[];document.querySelectorAll('script[src*="rsrc.php"]').forEach(function(e){b.push(e.src)});
  var v=document.querySelector('video');var vu=document.documentElement.innerHTML.match(/"video_url":"([^"]+)"/);
  function og(p){var e=document.querySelector('meta[property="og:'+p+'"]');return e?e.content:""}
  return JSON.stringify({path:location.pathname,scripts:s,lsd:m?m[1]:"",bundles:b,
    video:v?(v.currentSrc||v.src||""):"",videoUrl:vu?vu[1]:"",ogImage:og("image"),ogDescription:og("description")});
})()"""

        // Step 2: press play in the embed player, then wait up to 8 s for a real (non-blob) video link.
        private fun playerJs(id: String) = """(function(){
  function txt(s){var e=document.querySelector(s);return e?e.innerText.trim():""}
  var tries=0;function poll(){
    var v=document.querySelector('video');
    if(!v){var b=document.querySelector('.EmbedVideo,.VideoPlayButton,[aria-label*="Play"],.EmbeddedMedia');if(b)b.click();}
    var src=v?(v.currentSrc||v.src||""):"";
    if((src.indexOf("https://")===0)||++tries>16){
      var img=document.querySelector('img.EmbeddedMediaImage');
      ReelBot.done("$id",200,JSON.stringify({video:src,poster:(v&&v.poster)||(img?img.src:""),
        author:txt('.UsernameText')||txt('.Username'),caption:txt('.Caption')}));
    }else setTimeout(poll,500);
  }poll();})()"""
    }

    data class Result(val step: Int, val media: IgMedia, val videoPath: String?)

    private class ExpiredLink : Exception()

    private val cascade = IgCascade()
    private val main = Handler(Looper.getMainLooper())
    private val prefs = ctx.getSharedPreferences("ig_queries", Context.MODE_PRIVATE)
    private val ua: String by lazy { WebSettings.getDefaultUserAgent(ctx) }
    private val bundled: JSONObject by lazy {
        JSONObject(ctx.resources.openRawResource(R.raw.ig_queries).bufferedReader().use { it.readText() })
    }

    /** Only one WebView fetch at a time; the cascade's throttle spaces requests anyway. */
    private val webLock = Any()
    private var webView: WebView? = null
    private val jsResults = ConcurrentHashMap<String, CompletableFuture<Pair<Int, String>>>()

    fun fetch(url: String): Result {
        val code = ShareUrls.extract(url)?.takeIf { it.app == "instagram" }?.code
            ?: throw IllegalArgumentException("not an Instagram link: $url")
        repeat(2) { attempt ->
            val r = synchronized(webLock) {
                try { cascade.run(code, steps(code)) } finally { destroyWebView() }
            }
            if (!r.media.hasVideo) return Result(r.step, r.media, null)
            try {
                return Result(r.step, r.media, download(r.media.videoUrl, code)?.path)
            } catch (_: ExpiredLink) {
                // ENDPOINTS IG-CDN: a 403 means the signed link died; rerun the cascade once.
                if (attempt == 1) return Result(r.step, r.media, null)
            }
        }
        error("unreachable")
    }

    private fun steps(code: String): List<(String) -> StepResult> {
        val mediaId = IgParse.mediaId(code)
        var page: IgParse.Page? = null
        return listOf(
            { _ -> embedStep(code) },
            { _ -> playerStep(code) },
            { _ ->
                val p = loadPage(code)
                page = p
                when {
                    p == null -> StepResult.Empty
                    p.loginWall -> StepResult.LoginWall
                    else -> (IgParse.postPage(p.scripts, mediaId) ?: p.rendered)?.let { StepResult.Media(it) } ?: StepResult.Empty
                }
            },
            { _ -> page?.takeIf { !it.loginWall }?.let { gqlStep(it, "loggedOutPost", """{"media_id":"$mediaId"}""", web = false) } ?: StepResult.Empty },
            { _ ->
                page?.takeIf { !it.loginWall }?.let {
                    val vars = """{"shortcode":"$code","fetch_tagged_user_count":null,"hoisted_comment_id":null,"hoisted_reply_id":null}"""
                    gqlStep(it, "webPost", vars, web = true)
                } ?: StepResult.Empty
            },
            { _ -> oembedStep(code) },
        )
    }

    // --- step 1: IG-EMBED ---------------------------------------------------------------

    private fun embedStep(code: String): StepResult {
        var resp: Resp? = null
        for (i in 0 until 3) {
            try {
                resp = get("https://www.instagram.com/p/$code/embed/captioned/", mapOf("Accept" to "text/html", "Accept-Language" to "en-US,en;q=0.9"))
                break
            } catch (e: IOException) {
                if (i == 2) return StepResult.Empty
                Thread.sleep(1_000)
            }
        }
        val r = resp!!
        return when {
            r.code == 429 -> StepResult.Limited
            r.loginRedirect -> StepResult.LoginWall
            r.code == 404 -> StepResult.Gone
            r.code != 200 -> StepResult.Empty
            else -> IgParse.embed(r.body)?.let { StepResult.Media(it) } ?: StepResult.Empty
        }
    }

    // --- step 2: IG-EMBED-PLAYER --------------------------------------------------------

    /**
     * The embed page in a hidden WebView with autoplay allowed. Logged out, the embed player is the one
     * Instagram page that reliably plays the reel, so its `<video>` src (or any .mp4 it requests) is the file.
     */
    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    private fun playerStep(code: String): StepResult {
        cascade.throttle()
        val id = UUID.randomUUID().toString()
        val fut = CompletableFuture<Pair<Int, String>>()
        jsResults[id] = fut
        val seenMp4 = java.util.concurrent.atomic.AtomicReference("")
        main.post {
            webView?.destroy()
            val wv = WebView(ctx)
            webView = wv
            wv.settings.javaScriptEnabled = true
            wv.settings.mediaPlaybackRequiresUserGesture = false
            wv.settings.blockNetworkImage = false
            wv.addJavascriptInterface(JsBridge(), "ReelBot")
            wv.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, req: WebResourceRequest): WebResourceResponse? {
                    IgParse.progressiveMp4(req.url.toString())?.let { seenMp4.compareAndSet("", it) }
                    return null
                }
                override fun onPageFinished(view: WebView, url: String) { view.evaluateJavascript(playerJs(id), null) }
            }
            wv.loadUrl("https://www.instagram.com/reel/$code/embed/captioned/")
        }
        val (_, body) = try { fut.get(TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS) } catch (_: TimeoutException) {
            jsResults.remove(id); return StepResult.Empty
        }
        val o = runCatching { JSONObject(body) }.getOrNull() ?: return StepResult.Empty
        val media = IgParse.player(o.optString("video"), seenMp4.get(), o.optString("poster"), o.optString("author"), o.optString("caption"))
        return media?.let { StepResult.Media(it) } ?: StepResult.Empty
    }

    // --- step 6: IG-OEMBED --------------------------------------------------------------

    private fun oembedStep(code: String): StepResult {
        val target = URLEncoder.encode("https://www.instagram.com/reel/$code/", "UTF-8")
        val r = try { get("https://www.instagram.com/api/v1/oembed/?url=$target", mapOf("X-IG-App-ID" to IG_APP_ID)) } catch (_: IOException) { return StepResult.Empty }
        return when {
            r.code == 429 -> StepResult.Limited
            r.code != 200 -> StepResult.Empty
            else -> IgParse.oembed(r.body)?.let { StepResult.Media(it) } ?: StepResult.Empty
        }
    }

    // --- step 3: IG-POST-PAGE -----------------------------------------------------------

    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    private fun loadPage(code: String): IgParse.Page? {
        cascade.throttle()
        val done = CompletableFuture<String>()
        main.post {
            webView?.destroy() // step 2's player
            val wv = WebView(ctx)
            webView = wv
            wv.settings.javaScriptEnabled = true
            wv.settings.loadsImagesAutomatically = false
            wv.settings.blockNetworkImage = true
            wv.addJavascriptInterface(JsBridge(), "ReelBot")
            wv.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript(COLLECT_JS) { raw -> done.complete(raw) }
                }
            }
            wv.loadUrl("https://www.instagram.com/reel/$code/")
        }
        val raw = try { done.get(TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS) } catch (_: TimeoutException) { return null }
        // evaluateJavascript hands back the returned string JSON-encoded.
        return runCatching { JSONArray("[$raw]").getString(0) }.getOrNull()?.let(IgParse::page)
    }

    private inner class JsBridge {
        @JavascriptInterface
        fun done(id: String, status: Int, body: String) { jsResults.remove(id)?.complete(status to body) }
    }

    private fun destroyWebView() {
        main.post { webView?.destroy(); webView = null }
    }

    // --- steps 4–5: IG-GQL-LOGGEDOUT / IG-GQL-WEB, plus IG-JS-BUNDLE ---------------------

    private fun gqlStep(page: IgParse.Page, key: String, variables: String, web: Boolean): StepResult {
        var rediscovered = false
        while (true) {
            val (name, docId) = query(key)
            val endpoint = if (web) "https://www.instagram.com/graphql/query/" else "https://www.instagram.com/api/graphql"
            val form = listOf(
                "lsd" to page.lsd, "fb_api_caller_class" to "RelayModern", "fb_api_req_friendly_name" to name,
                "server_timestamps" to "true", "variables" to variables, "doc_id" to docId,
            ).joinToString("&") { (k, v) -> "$k=" + URLEncoder.encode(v, "UTF-8") }
            val (status, body) = jsFetch(endpoint, name, page.lsd, form) ?: return StepResult.Empty
            if (status == 429) return StepResult.Limited
            when (val g = IgParse.gql(body, web)) {
                is IgParse.Gql.Found -> return StepResult.Media(g.media)
                IgParse.Gql.RequireLogin -> return StepResult.LoginWall
                IgParse.Gql.Missing -> return StepResult.Empty
                IgParse.Gql.Stale -> {
                    prefs.edit().remove(key).apply()
                    if (rediscovered || !rediscover(key, name, page.bundles)) return StepResult.Empty
                    rediscovered = true
                }
            }
        }
    }

    private fun jsFetch(endpoint: String, name: String, lsd: String, form: String): Pair<Int, String>? {
        cascade.throttle()
        val id = UUID.randomUUID().toString()
        val fut = CompletableFuture<Pair<Int, String>>()
        jsResults[id] = fut
        val q = JSONObject::quote
        val js = """(function(){var t=(document.cookie.match(/csrftoken=([^;]+)/)||[])[1]||"";
fetch(${q(endpoint)},{method:"POST",credentials:"include",headers:{"Content-Type":"application/x-www-form-urlencoded",
"X-IG-App-ID":"$IG_APP_ID","X-FB-LSD":${q(lsd)},"X-CSRFToken":t,"X-FB-Friendly-Name":${q(name)},"X-ASBD-ID":"359341",
"X-Requested-With":"XMLHttpRequest"},body:${q(form)}})
.then(function(r){return r.text().then(function(x){ReelBot.done(${q(id)},r.status,x)})})
.catch(function(e){ReelBot.done(${q(id)},0,String(e))});})()"""
        main.post { webView?.evaluateJavascript(js, null) }
        return try { fut.get(TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS) } catch (_: TimeoutException) { jsResults.remove(id); null }
    }

    /** Bundled `res/raw/ig_queries.json`, unless a rediscovered id is cached. */
    private fun query(key: String): Pair<String, String> {
        val b = bundled.getJSONObject(key)
        return b.getString("name") to (prefs.getString(key, null) ?: b.getString("docId"))
    }

    /** IG-JS-BUNDLE, at most once a day per query. */
    private fun rediscover(key: String, name: String, bundles: List<String>): Boolean {
        val today = LocalDate.now().toString()
        if (prefs.getString("${key}_tried", null) == today) return false
        prefs.edit().putString("${key}_tried", today).apply()
        for (src in bundles.reversed()) {
            val js = try { get(src, emptyMap(), throttle = false).takeIf { it.code == 200 }?.body } catch (_: IOException) { null } ?: continue
            IgParse.docIdFromBundle(js, name)?.let {
                prefs.edit().putString(key, it).apply()
                return true
            }
        }
        return false
    }

    // --- IG-CDN --------------------------------------------------------------------------

    private fun download(videoUrl: String, code: String): File? {
        if (IgParse.isExpired(videoUrl, System.currentTimeMillis())) throw ExpiredLink()
        val c = (URL(videoUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS; readTimeout = 60_000
            setRequestProperty("User-Agent", ua)
            setRequestProperty("Referer", "https://www.instagram.com/")
        }
        try {
            if (c.responseCode == 403) throw ExpiredLink()
            if (c.responseCode != 200 || c.contentLengthLong > MAX_VIDEO) return null
            val f = File(ctx.cacheDir, "ig/$code.mp4").apply { parentFile!!.mkdirs() }
            val ok = c.inputStream.use { input -> f.outputStream().use { IgParse.copyCapped(input, it, MAX_VIDEO) } }
            if (!ok) f.delete()
            return f.takeIf { ok }
        } catch (_: IOException) {
            return null
        } finally {
            c.disconnect()
        }
    }

    // --- plain HTTPS ---------------------------------------------------------------------

    private class Resp(val code: Int, val body: String, val loginRedirect: Boolean)

    private fun get(url: String, headers: Map<String, String>, throttle: Boolean = true): Resp {
        if (throttle) cascade.throttle()
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = TIMEOUT_MS; readTimeout = TIMEOUT_MS
            setRequestProperty("User-Agent", ua)
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        try {
            val code = c.responseCode
            val body = (if (code < 400) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() }.orEmpty()
            return Resp(code, body, c.url.path.startsWith("/accounts/login"))
        } finally {
            c.disconnect()
        }
    }
}
