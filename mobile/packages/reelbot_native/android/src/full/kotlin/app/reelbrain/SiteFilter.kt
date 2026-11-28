package app.reelbrain

import java.util.concurrent.ConcurrentHashMap

/**
 * What the website filter and the limits service share inside the app's process. The filter reports the names the phone looks up;
 * the service decides which limited sites are used up. No page address or content is ever seen, only names being looked up.
 */
object SiteFilter {
    /** How long after the last look-up of a site it still counts as being used. */
    const val ACTIVE_MS = 30_000L

    @Volatile var sites: List<LimitItem> = emptyList()
    /** Hosts (ids) of the sites whose time is used up, or that are blocked all day. */
    @Volatile var blocked: Set<String> = emptySet()
    @Volatile var lastBlocked: Pair<LimitItem, Long>? = null
    private val seen = ConcurrentHashMap<String, Long>()
    /** Sites whose address was in a browser's address bar (the Accessibility method), by last time seen. */
    private val front = ConcurrentHashMap<String, Long>()
    /** The address bar is read about once a second, so a site is in use for a few seconds after the last read. */
    const val FRONT_MS = 6_000L

    /** True when the look-up of [name] must be refused. */
    fun onQuery(name: String, now: Long): Boolean {
        val item = sites.firstOrNull { AppLimits.siteMatches(it.id, name) } ?: return false
        if (item.id in blocked) {
            lastBlocked = item to now
            return true
        }
        seen[item.id] = now
        return false
    }

    /** The Accessibility method: [address] is what a browser's address bar shows. Returns the limited site when it is used up. */
    fun onFront(address: String, now: Long): LimitItem? {
        val item = sites.firstOrNull { AppLimits.siteMatches(it.id, address) } ?: return null
        front[item.id] = now
        return item.takeIf { it.id in blocked }
    }

    /** Sites in use: looked up within the last [ACTIVE_MS], or in front within the last [FRONT_MS]. */
    fun active(now: Long): List<LimitItem> = sites.filter { (seen[it.id] ?: 0L) > now - ACTIVE_MS || (front[it.id] ?: 0L) > now - FRONT_MS }
}

/**
 * The page a browser in front shows, from its address bar. While the bar has focus it holds what is being typed, so nothing
 * counts until the page is opened. Chrome hides the bar once a page scrolls; then the last page read is kept, until the bar is
 * read again, another browser or app comes to the front, or [clear].
 */
class FrontAddress {
    private var pkg: String? = null
    private var last: String? = null

    /** [text] is the bar's text, null when no bar is on screen; [typing] when the bar has focus. Returns the open page, if known. */
    fun read(pkg: String, text: String?, typing: Boolean): String? {
        if (pkg != this.pkg) { this.pkg = pkg; last = null }
        if (typing) last = null else if (text != null) last = text
        return last
    }

    fun clear() { pkg = null; last = null }
}

/** How limited websites are blocked: `vpn` (a local filter on DNS look-ups, all apps) or `access` (the browser's address bar, read with Accessibility). */
object SiteMethod {
    const val KEY = "site_method"
    fun get(ctx: android.content.Context) =
        if (ctx.getSharedPreferences(CounterPlugin.PREFS, android.content.Context.MODE_PRIVATE).getString(KEY, "vpn") == "access") "access" else "vpn"
    fun set(ctx: android.content.Context, m: String) {
        ctx.getSharedPreferences(CounterPlugin.PREFS, android.content.Context.MODE_PRIVATE).edit().putString(KEY, if (m == "access") "access" else "vpn").apply()
    }
}
