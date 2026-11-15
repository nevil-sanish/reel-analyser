package app.reelbrain

import org.json.JSONArray
import org.json.JSONObject

/** One app (`kind` app, `id` the package) or website (`kind` site, `id` the host, e.g. youtube.com) with its daily time in minutes. */
data class LimitItem(val kind: String, val id: String, val label: String, val limitMin: Int) {
    /** The key the time is counted under in `block_use`. */
    val key get() = "$kind:$id"
}

/** The time limits in force, a change waiting for the next midnight, and when it starts. Same rule as the reel limits. */
data class LimitsState(val active: List<LimitItem> = emptyList(), val pending: List<LimitItem>? = null, val pendingFrom: Long = 0)

/** Daily time limits for any app or website (1.2.2.0, full build). Past the time the app or site is covered by the block screen. */
object AppLimits {
    /** Never blockable, so a limit can't lock the user out of this app, calls or Settings. */
    private val protectedPackages = setOf(
        "com.android.settings", "com.android.systemui", "com.android.dialer", "com.google.android.dialer", "com.android.phone",
        "com.samsung.android.dialer", "com.android.emergency", "com.android.server.telecom", "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    fun isProtected(pkg: String) = pkg == "app.reelbrain" || pkg.startsWith("app.reelbrain.") || pkg in protectedPackages

    /** The host of an address as a browser shows it ("https://www.Example.com:8080/a?b" and "example.com/a" both give example.com). */
    fun host(address: String): String? {
        var a = address.trim().lowercase()
        if (a.isEmpty() || a.any { it.isWhitespace() }) return null
        a = a.substringAfter("://", a).substringBefore('/').substringBefore('?').substringBefore('#').substringAfterLast('@').substringBefore(':')
        a = a.removePrefix("www.").trimEnd('.')
        return a.takeIf { Regex("[a-z0-9-]+(\\.[a-z0-9-]+)+").matches(it) }
    }

    /** The address bar shows the site [id], or any page below it (`x.com` matches `m.x.com` but not `box.com`). */
    fun siteMatches(id: String, address: String): Boolean {
        val h = host(address) ?: return false
        return h == id || h.endsWith(".$id")
    }

    fun isOver(item: LimitItem, usedMs: Long) = usedMs >= item.limitMin * 60_000L

    fun message(item: LimitItem): String {
        val m = item.limitMin
        val t = if (m % 60 == 0) "${m / 60} h" else if (m > 60) "${m / 60} h ${m % 60} min" else "$m min"
        return "You have used your $t a day of ${item.label}."
    }

    fun toJson(list: List<LimitItem>): String = JSONArray(list.map {
        JSONObject().put("kind", it.kind).put("id", it.id).put("label", it.label).put("limitMin", it.limitMin)
    }).toString()

    /** Null for anything malformed. Entries that are not allowed (protected apps, bad hosts, a limit outside 1 to 1440) are dropped. */
    fun parse(json: String?): List<LimitItem>? = try {
        val a = JSONArray(json ?: return null)
        (0 until minOf(a.length(), 60)).mapNotNull { i ->
            val o = a.getJSONObject(i)
            val kind = o.getString("kind")
            val raw = o.getString("id")
            val id = when (kind) {
                "app" -> raw.takeIf { Regex("[A-Za-z0-9_.]+").matches(it) && !isProtected(it) }
                "site" -> host(raw)
                else -> null
            } ?: return@mapNotNull null
            val limit = o.getInt("limitMin").takeIf { it in 1..1440 } ?: return@mapNotNull null
            LimitItem(kind, id, o.optString("label", id).take(60).ifBlank { id }, limit)
        }.distinctBy { it.key }
    } catch (e: Exception) {
        null
    }

    fun effective(s: LimitsState, now: Long) =
        if (s.pending != null && now >= s.pendingFrom) s.copy(active = s.pending, pending = null, pendingFrom = 0) else s

    /** The first set-up, and a change the app says is stricter, apply at once; any other change waits for the next midnight. */
    fun save(s: LimitsState, list: List<LimitItem>, immediate: Boolean, now: Long) =
        if (immediate || s.active.isEmpty()) LimitsState(list) else s.copy(pending = list, pendingFrom = BlockPolicy.nextMidnight(now))
}
