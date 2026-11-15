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

    /** Sites looked up within the last [ACTIVE_MS]. */
    fun active(now: Long): List<LimitItem> = sites.filter { (seen[it.id] ?: 0L) > now - ACTIVE_MS }
}
