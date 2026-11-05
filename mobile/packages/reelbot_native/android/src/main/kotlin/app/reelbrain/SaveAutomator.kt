package app.reelbrain

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale

/**
 * Experimental auto-Save (IMPLEMENTATION §6): Share → (Share to… / More) → Reel Bot, each step within 1.5 s.
 * Off by default. If it stays under 90% on real phones, delete this file; manual Share stays.
 */
object SavePicker {
    private val shareIds = mapOf(
        "instagram" to setOf("clips_share_button", "direct_share_button", "row_feed_button_share"),
        "youtube" to setOf("reel_dyn_share", "share_button", "reel_share_button"),
    )
    private val shareLabels = setOf("share", "send", "send post", "share video")
    private val moreLabels = setOf("share to…", "share to...", "share to", "more", "share via", "more options")

    private fun lower(n: NodeSnap) = n.label.lowercase(Locale.ROOT)

    /** The reel's Share button: known ids first, then the button's description. */
    fun share(app: String, nodes: List<NodeSnap>): Int? {
        val ids = shareIds[app].orEmpty()
        return nodes.indexOfFirst { it.visible && it.id in ids }.takeIf { it >= 0 }
            ?: nodes.indexOfFirst { it.visible && lower(it) in shareLabels }.takeIf { it >= 0 }
    }

    fun reelBot(nodes: List<NodeSnap>) = nodes.indexOfFirst { it.visible && it.label == "Reel Bot" }.takeIf { it >= 0 }

    /** Instagram's own sheet (and some YouTube ones) need "Share to…" / "More" to reach the system sheet. */
    fun more(nodes: List<NodeSnap>) = nodes.indexOfFirst { it.visible && lower(it) in moreLabels }.takeIf { it >= 0 }
}

class SaveAutomator(
    private val service: AccessibilityService,
    private val collect: () -> List<Pair<NodeSnap, AccessibilityNodeInfo>>,
    private val done: (ok: Boolean, step: String) -> Unit,
) {
    private enum class Stage { SHARE, PICK }

    private val handler = Handler(Looper.getMainLooper())
    private var stage = Stage.SHARE
    private var app = ""
    private var deadline = 0L
    private var triedMore = false
    private var scrolled = false
    var running = false
        private set

    fun start(app: String) {
        if (running) return
        running = true
        this.app = app
        stage = Stage.SHARE
        triedMore = false
        scrolled = false
        next()
    }

    private fun next() {
        deadline = System.currentTimeMillis() + 1500
        handler.postDelayed(::poll, 150)
    }

    private fun poll() {
        if (!running) return
        val found = collect()
        val snaps = found.map { it.first }
        fun click(i: Int?): Boolean = i != null && clickable(found[i].second)?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true

        when (stage) {
            Stage.SHARE -> if (click(SavePicker.share(app, snaps))) { stage = Stage.PICK; return next() }
            Stage.PICK -> {
                if (click(SavePicker.reelBot(snaps))) return finish(true, "picked")
                if (!triedMore && click(SavePicker.more(snaps))) { triedMore = true; return next() }
                if (!scrolled && System.currentTimeMillis() > deadline - 500) {
                    scrolled = true
                    found.map { it.second }.firstOrNull { it.isScrollable }?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                    return next()
                }
            }
        }
        if (System.currentTimeMillis() > deadline) {
            service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            return finish(false, if (stage == Stage.SHARE) "no share button" else "no Reel Bot in the share sheet")
        }
        handler.postDelayed(::poll, 150)
    }

    private fun finish(ok: Boolean, step: String) {
        running = false
        done(ok, step)
    }

    /** Labels often sit inside the clickable row, not on it. */
    private fun clickable(n: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var c: AccessibilityNodeInfo? = n
        while (c != null && !c.isClickable) c = c.parent
        return c
    }
}
