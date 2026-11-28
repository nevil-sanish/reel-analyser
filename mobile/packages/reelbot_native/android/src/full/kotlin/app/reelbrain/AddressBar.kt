package app.reelbrain

import android.view.accessibility.AccessibilityNodeInfo

/** What a browser's address bar shows: [text] and whether the person is typing in it ([typing]). */
data class BarReading(val text: String, val typing: Boolean)

/**
 * Reads a browser's address bar, and only that. Every known address-bar id is tried for every browser, so a browser that is
 * not on the list but uses a common id still works; the id that worked last is tried first. Firefox 152 and later draw the
 * bar with Compose and have no such id: see [FirefoxToolbar].
 */
class AddressBar {
    private val hit = HashMap<String, String>()

    fun read(root: AccessibilityNodeInfo, pkg: String): BarReading? {
        val ids = hit[pkg]?.let { listOf(it) + (Browsers.addressIds - it) } ?: Browsers.addressIds
        for (id in ids) {
            val n = runCatching { root.findAccessibilityNodeInfosByViewId("$pkg:id/$id") }.getOrNull()
                ?.firstOrNull { it.text != null } ?: continue
            hit[pkg] = id
            return BarReading(n.text.toString(), n.isFocused)
        }
        return FirefoxToolbar.read(root, pkg)
    }
}

/**
 * Firefox's Compose toolbar. The address is a Compose node tagged `ADDRESSBAR_URL_BOX` (shown page, the address only in its
 * description, `"$title $url. $hint"`) or `ADDRESSBAR_SEARCH_BOX` (the field being typed in). The walk starts at the view that
 * hosts the toolbar, never at the window, so no part of the page is read, and stops after [MAX_NODES].
 *
 * Adapted from expo-accessibility-service by amehmeto (MIT, FirefoxComposeToolbar.kt); see NOTICE.md.
 */
object FirefoxToolbar {
    private val hosts = listOf("composable_toolbar", "homepageView")
    private const val SHOWN = "ADDRESSBAR_URL_BOX"
    private const val TYPED = "ADDRESSBAR_SEARCH_BOX"
    /** The home feed and the search suggestions: large, and never the address. */
    private val skipped = setOf("homepage.view", "mozac.awesomebar")
    private const val MAX_NODES = 40

    fun read(root: AccessibilityNodeInfo, pkg: String): BarReading? {
        for (h in hosts) {
            val host = runCatching { root.findAccessibilityNodeInfosByViewId("$pkg:id/$h") }.getOrNull()?.firstOrNull() ?: continue
            val n = Walk().find(host) ?: continue
            return if (n.viewIdResourceName == TYPED) BarReading(n.text?.toString().orEmpty(), true)
            else shownAddress(n.contentDescription?.toString())?.let { BarReading(it, n.isFocused) }
        }
        return null
    }

    /** The address in `"$title $url. $hint"`: the last word before the last ". ". Null when it is the hint alone (home screen). */
    fun shownAddress(desc: String?): String? =
        desc?.substringBeforeLast(". ", missingDelimiterValue = "")?.substringAfterLast(' ')?.ifEmpty { null }

    private class Walk {
        private var left = MAX_NODES

        fun find(parent: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            for (i in 0 until parent.childCount) {
                if (left-- <= 0) return null
                val c = parent.getChild(i) ?: continue
                val tag = c.viewIdResourceName
                if (tag == SHOWN || tag == TYPED) return c
                if (tag !in skipped) find(c)?.let { return it }
            }
            return null
        }
    }
}
