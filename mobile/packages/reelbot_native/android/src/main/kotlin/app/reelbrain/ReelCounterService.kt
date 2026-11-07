package app.reelbrain

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import app.reelbrain.core.R
import org.json.JSONObject

/**
 * Counts reels and shorts by reading the screen (IMPLEMENTATION §3.4). Read-only: no taps, no gestures.
 * v0.9.0 removed the bubble and auto-Save; saving is only Share → Reel Analyser.
 */
class ReelCounterService : AccessibilityService() {
    companion object {
        @Volatile var running = false
        const val PREFS = "reelbot"
        const val CAPTURE = "debug_capture"
        private const val CHANNEL = "reelbot_alerts"
    }

    private lateinit var db: CounterDb
    private lateinit var tracker: ReelTracker
    private val handler = Handler(Looper.getMainLooper())
    private var lastEval = 0L
    private var lastTree = 0L
    private var ticking = false

    // Keeps dwell, leaving and screen time right while a video plays with no accessibility events.
    private val tick = object : Runnable {
        override fun run() {
            evaluate()
            if (tracker.active) handler.postDelayed(this, 1000) else ticking = false
        }
    }

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = tracker.end(System.currentTimeMillis())
    }

    /** CounterDb, plus the unknown alert after each unknown item. */
    private inner class AlertingSink : TrackerSink by db {
        override fun addUnknown(date: String, app: String) {
            db.addUnknown(date, app)
            val (reels, unknown) = db.totals(date, app)
            val key = "alerted_$date"
            if (UnknownAlert.shouldAlert(reels, unknown, db.debug(key) != null)) {
                db.setDebug(key, app, System.currentTimeMillis())
                postAlert(app)
            }
        }
    }

    override fun onServiceConnected() {
        db = CounterDb.get(this)
        tracker = ReelTracker(AlertingSink())
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        running = true
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (running) {
            tracker.end(System.currentTimeMillis())
            handler.removeCallbacks(tick)
            unregisterReceiver(screenOff)
            running = false
        }
        return super.onUnbind(intent)
    }

    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        val pkg = e.packageName?.toString() ?: return
        if (pkg in DetectionRules.ignored) return
        if (pkg !in DetectionRules.apps && !tracker.active) return
        val now = System.currentTimeMillis()
        if (now - lastEval >= 250) evaluate()
        if (tracker.active && !ticking) {
            ticking = true
            handler.postDelayed(tick, 1000)
        }
    }

    private fun evaluate() {
        val now = System.currentTimeMillis()
        lastEval = now
        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString() ?: return
        if (pkg in DetectionRules.ignored) return // neither leaving nor watching
        val app = DetectionRules.apps[pkg]
        if (app == null) {
            tracker.observe(now, null, false, null)
            return
        }
        val nodes = collect(root)
        val r = Rect().also(root::getBoundsInScreen)
        val obs = DetectionRules.read(app, nodes, Box(r.left, r.top, r.right, r.bottom))
        tracker.observe(now, app, obs.inReels, obs.item)
        if (getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(CAPTURE, false)) capture(now, app, obs, nodes)
    }

    /** At most 1,500 nodes and depth 40, so a huge tree can't stall the service. */
    private fun collect(root: AccessibilityNodeInfo): List<NodeSnap> {
        val out = ArrayList<NodeSnap>()
        val stack = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>().apply { add(root to 0) }
        val r = Rect()
        while (stack.isNotEmpty() && out.size < 1500) {
            val (n, depth) = stack.removeLast()
            n.getBoundsInScreen(r)
            out += NodeSnap(
                id = n.viewIdResourceName?.substringAfter(":id/") ?: "", cls = n.className?.toString() ?: "",
                text = n.text?.toString() ?: "", desc = n.contentDescription?.toString() ?: "",
                bounds = Box(r.left, r.top, r.right, r.bottom), visible = n.isVisibleToUser,
            )
            if (depth < 40) for (i in n.childCount - 1 downTo 0) n.getChild(i)?.let { stack.add(it to depth + 1) }
        }
        return out
    }

    private fun capture(now: Long, app: String, obs: Observation, nodes: List<NodeSnap>) {
        val i = obs.item ?: ItemText()
        db.setDebug("now", JSONObject(mapOf(
            "app" to app, "inReels" to obs.inReels, "fp" to (Fingerprint.of(app, obs.item) ?: ""),
            "author" to i.author, "caption" to i.caption, "audio" to i.audio, "title" to i.title, "likes" to i.likes,
        )).toString(), now)
        if (now - lastTree < 3000) return
        lastTree = now
        val tree = nodes.take(400).joinToString("\n") { n ->
            val b = n.bounds
            "${if (n.visible) "V" else "-"} ${n.id.ifEmpty { "-" }} ${n.cls.substringAfterLast('.')} [${b.left},${b.top},${b.right},${b.bottom}] ${n.label.replace('\n', ' ').take(80)}"
        }
        db.setDebug("tree_$app", tree, now)
    }

    private fun postAlert(app: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Counter problems", NotificationManager.IMPORTANCE_DEFAULT))
        val open = packageManager.getLaunchIntentForPackage(packageName)
        val name = if (app == "youtube") "YouTube" else "Instagram"
        nm.notify(1, Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reelbot)
            .setContentTitle("Reel Analyser can't read $name any more")
            .setStyle(Notification.BigTextStyle().bigText(
                "An app update probably changed the screen. Open Reel Analyser → Today → Debug to capture the new layout."))
            .setContentIntent(open?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE) })
            .setAutoCancel(true)
            .build())
    }
}
