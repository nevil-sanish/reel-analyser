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
import java.util.Calendar
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import app.reelbrain.core.R
import org.json.JSONObject

/**
 * Counts reels and shorts by reading the screen (IMPLEMENTATION §3.4), and blocks them past the limit or outside the schedule
 * the user set (1.0.9.0). It never taps, types or scrolls: to block, it opens the block screen over the reel. The blocker uses
 * only whether a reel or short is on screen, and, in a browser, the address bar.
 * v0.9.0 removed the bubble and auto-Save; saving is only Share → Reel Analyser.
 */
class ReelCounterService : AccessibilityService() {
    companion object {
        @Volatile var running = false
        @Volatile private var instance: ReelCounterService? = null
        /** Settings changed: narrow or widen the apps the service may see. */
        fun rescope() { instance?.let { s -> s.handler.post { s.applyScope() } } }
        const val PREFS = CounterPlugin.PREFS
        const val CAPTURE = "debug_capture"
        /** The user's opt-in to reading the reel screens. Until it is on, the service reads nothing, even if Accessibility is on. */
        const val CONSENT = "detect_consent"
        const val SCROLL_RULE = "scroll_rule"
        private const val CHANNEL = "reelbot_alerts"
    }

    private lateinit var db: CounterDb
    private lateinit var sink: CounterSink
    private lateinit var tracker: ReelTracker
    private lateinit var meter: BlockMeter
    private var scopeAt = 0L
    private var stateAt = 0L
    private var state = BlockState()
    private var usedAt = 0L
    private var used: Map<String, Long> = emptyMap()
    private var lastBlock = 0L
    private val handler = Handler(Looper.getMainLooper())
    private var lastEval = 0L
    private var nullSince = 0L
    private var lastTree = 0L
    private var ticking = false
    private val swipes = SwipeCounter()
    private val run = SwipeRun()
    private var feedNow = false
    private var pausedUntil = 0L
    private var ruleAt = 0L
    private var rule: ScrollRule? = null

    // Keeps dwell, leaving and screen time right while a video plays with no accessibility events.
    private val tick = object : Runnable {
        override fun run() {
            evaluate()
            if (tracker.active || meter.active || System.currentTimeMillis() - frontAt < SiteFilter.FRONT_MS) handler.postDelayed(this, 1000) else ticking = false
        }
    }

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) { tracker.end(System.currentTimeMillis()); meter.stop() }
    }

    /** CounterDb, plus the unknown alert after each unknown item. */
    private inner class AlertingSink : TrackerSink by sink {
        override fun addUnknown(date: String, app: String) {
            sink.addUnknown(date, app)
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
        sink = CounterSink(db)
        tracker = ReelTracker(AlertingSink())
        meter = BlockMeter(sink)
        BlockPhotos.wipe(this)
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        instance = this
        applyScope()
        running = true
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (running) {
            tracker.end(System.currentTimeMillis())
            meter.stop()
            handler.removeCallbacks(tick)
            unregisterReceiver(screenOff)
            running = false
            instance = null
        }
        return super.onUnbind(intent)
    }

    override fun onInterrupt() = Unit

    /**
     * Tells Android which apps this service gets events and screen content from, so every other app (a payment app, a bank,
     * the keyboard) is never seen at all. Before the user's opt-in that is only this app. After it: Instagram and YouTube,
     * the browsers only when a browser reel block is set. App and website limits do not use this service at all (see LimitsService).
     */
    private fun applyScope() {
        val info = serviceInfo ?: return
        val pk = LinkedHashSet<String>()
        if (consented()) {
            val now = System.currentTimeMillis()
            val cfg = db.currentBlockState(now).active
            pk += DetectionRules.apps.filter { (_, a) -> a in DetectionRules.counted || cfg?.items?.contains(a) == true || scrollOn(now) }.keys
            if (db.currentBlockState(now).active?.items?.contains("browser") == true || siteByAddressBar(now)) pk += Browsers.packages
        }
        if (pk.isEmpty()) pk += packageName
        val arr = pk.toTypedArray()
        if (!arr.contentEquals(info.packageNames)) {
            info.packageNames = arr
            serviceInfo = info
        }
    }

    /** The user chose Accessibility for websites and has a website limit: the browsers' address bars are read, nothing else. */
    private fun siteByAddressBar(now: Long) =
        SiteMethod.get(this) == "access" && db.currentLimits(now).active.any { it.kind == "site" }

    private fun scrollRule(now: Long): ScrollRule? {
        if (now - ruleAt > 2000) {
            ruleAt = now
            rule = ScrollRule.parse(getSharedPreferences(PREFS, MODE_PRIVATE).getString(SCROLL_RULE, null))?.takeIf { it.on }
        }
        return rule
    }

    private fun scrollOn(now: Long) = scrollRule(now) != null

    /** In a short-video feed: while a pause runs, or the day's swipes are used up, the app is closed and the phone goes home. */
    private fun scrollCheck(now: Long) {
        val r = scrollRule(now) ?: return
        if (now < pausedUntil) {
            goHome(now, ScrollGuard.message(ScrollVerdict.Pause(r.pauseMinutes), r, ((pausedUntil - now) / 60_000L).toInt() + 1))
            return
        }
        if (r.maxPerDay > 0 && (db.usedToday(localDate(now))["swipes:all"] ?: 0L) >= r.maxPerDay) goHome(now, ScrollGuard.message(ScrollVerdict.DayLimit, r))
    }

    /** A new swipe in a feed: counted, and the run and day rules checked. */
    private fun onSwipe(now: Long) {
        val r = scrollRule(now) ?: return
        val date = localDate(now)
        sink.addUse(date, "swipes:all", 1)
        val n = run.onSwipe(now, r.quietSec * 1000L)
        val v = ScrollGuard.verdict(r, db.usedToday(date)["swipes:all"] ?: 0L, n)
        if (v is ScrollVerdict.Pause) { pausedUntil = now + v.minutes * 60_000L; run.reset() }
        if (v !is ScrollVerdict.Ok) goHome(now, ScrollGuard.message(v, r, r.pauseMinutes))
    }

    /** Closes the feed the way a person would: the Home action, then a short note. At most every 4 seconds. */
    private fun goHome(now: Long, text: String) {
        if (now - lastBlock <= 4000) return
        lastBlock = now
        meter.stop()
        performGlobalAction(GLOBAL_ACTION_HOME)
        handler.post { android.widget.Toast.makeText(this, text, android.widget.Toast.LENGTH_LONG).show() }
    }

    private fun consented() = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(CONSENT, false)

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        if (!consented()) {
            if (tracker.active || meter.active) { tracker.end(System.currentTimeMillis()); meter.stop() }
            return
        }
        val pkg = e.packageName?.toString() ?: return
        if (pkg in DetectionRules.ignored) return
        val now = System.currentTimeMillis()
        if (e.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED && pkg in DetectionRules.apps && feedNow && swipes.onScroll(now)) onSwipe(now)
        if (pkg !in DetectionRules.apps && pkg !in Browsers.packages && !tracker.active && !meter.active) return
        if (now - lastEval >= 250) evaluate()
        if ((tracker.active || meter.active || now - frontAt < SiteFilter.FRONT_MS) && !ticking) {
            ticking = true
            handler.postDelayed(tick, 1000)
        }
    }

    private fun evaluate() {
        if (!consented()) return
        val now = System.currentTimeMillis()
        lastEval = now
        // Apps the service may not see give no window at all: after a moment that means the watched app was left.
        val root = rootInActiveWindow ?: run {
            if (nullSince == 0L) nullSince = now
            if (now - nullSince >= 1500) {
                feedNow = false
                tracker.observe(now, null, false, null)
                val date = localDate(now)
                meter.observe(now, null, date)
            }
            return
        }
        nullSince = 0L
        val pkg = root.packageName?.toString() ?: return
        if (pkg in DetectionRules.ignored) return // neither leaving nor watching
        val app = DetectionRules.apps[pkg]
        if (app == null) {
            tracker.observe(now, null, false, null)
            feedNow = false
            enforce(now, if (pkg in Browsers.packages) browserReel(root, pkg) else null)
            if (pkg in Browsers.packages) siteInFront(root, pkg, now)
            return
        }
        // Missed daily goals: the whole app is blocked, so nothing on its screen is read at all.
        if (punished(app, now)) {
            tracker.observe(now, null, false, null)
            blockNow(app, "commit", now)
            return
        }
        if (app !in DetectionRules.counted) return feedApp(root, app, now)
        val nodes = collect(root)
        val r = Rect().also(root::getBoundsInScreen)
        val obs = DetectionRules.read(app, nodes, Box(r.left, r.top, r.right, r.bottom))
        tracker.observe(now, app, obs.inReels, obs.item)
        feedNow = obs.inReels
        if (obs.inReels) scrollCheck(now)
        // Whole-app time: anywhere in the app counts, and past the rule the app itself is blocked, not just its reels.
        val whole = app in (currentState(now).active?.wholeApp ?: emptySet())
        enforce(now, if (obs.inReels || whole) app else null)
        if (getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(CAPTURE, false)) capture(now, app, obs, nodes)
    }

    /** Snapchat and TikTok: no counting, only the blocker and the scroll guard. */
    private fun feedApp(root: AccessibilityNodeInfo, app: String, now: Long) {
        tracker.observe(now, null, false, null)
        val on = DetectionRules.feedOn(app, collect(root))
        feedNow = on
        val whole = app == "tiktok" || app in (currentState(now).active?.wholeApp ?: emptySet())
        enforce(now, if (on || whole) app else null)
        if (on) scrollCheck(now)
    }

    private var siteAt = 0L
    private var siteMethodOn = false
    private var frontAt = 0L

    /** Accessibility method for websites: the address bar tells which limited site is open; at its limit the block screen opens. */
    private fun siteInFront(root: AccessibilityNodeInfo, pkg: String, now: Long) {
        if (now - siteAt > 2000) { siteAt = now; siteMethodOn = siteByAddressBar(now) }
        if (!siteMethodOn) return
        val text = addressText(root, pkg) ?: return
        val item = SiteFilter.onFront(text, now)
        if (SiteFilter.active(now).any { AppLimits.siteMatches(it.id, text) }) frontAt = now
        if (item != null) blockNow(item.key, "applimit", now, item)
    }

    private fun addressText(root: AccessibilityNodeInfo, pkg: String): String? {
        for (id in Browsers.addressIds) {
            val t = root.findAccessibilityNodeInfosByViewId("$pkg:id/$id").firstNotNullOfOrNull { it.text?.toString() }
            if (t != null) return t
        }
        return null
    }

    /** `browser` when the address bar shows a reel or a short. Only the address bar is read, and only when the browser is blocked. */
    private fun browserReel(root: AccessibilityNodeInfo, pkg: String): String? {
        if ("browser" !in (currentState(System.currentTimeMillis()).active?.items ?: return null)) return null
        val t = addressText(root, pkg) ?: return null
        return if (BlockPolicy.browserSurface(t)) "browser" else null
    }

                private var punishAt = 0L
    private var punish: Punish? = null

    private fun punished(app: String, now: Long): Boolean {
        if (now - punishAt > 1000) { punish = db.punish(); punishAt = now }
        return punish?.blocks(app, localDate(now)) == true
    }

    private fun currentState(now: Long): BlockState {
        if (now - stateAt > 1000) { state = db.currentBlockState(now); stateAt = now }
        return state
    }

    /** Counts reel time for the item on screen and, past the limit or outside the schedule, opens the block screen. */
    private fun enforce(now: Long, surface: String?) {
        val date = localDate(now)
        val st = currentState(now)
        val cfg = st.active
        if (cfg == null || st.suspendedDate == date && surface == null) { meter.observe(now, null, date); return }
        meter.observe(now, if (surface in cfg.items) surface else null, date)
        if (surface == null) return
        if (now - usedAt > 1000) { used = db.usedToday(date); usedAt = now }
        val withPending = used + (surface to (used[surface] ?: 0L) + meter.pending(surface))
        val v = BlockPolicy.verdict(cfg, surface, BlockPolicy.minuteOfDay(now), withPending, st.suspendedDate == date)
        if (v is Verdict.Block) blockNow(surface, v.reason, now)
    }

    /** Opens the block screen over what is on screen, at most every 4 seconds, and notes it once a day in the history. */
    private fun blockNow(surface: String, reason: String, now: Long, item: LimitItem? = null, text: String = "") {
        if (now - lastBlock <= 4000) return
        lastBlock = now
        meter.stop()
        startActivity(Intent(this, BlockActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(BlockActivity.SURFACE, surface).putExtra(BlockActivity.REASON, reason)
            .putExtra(BlockActivity.TEXT, item?.let { AppLimits.message(it) } ?: text))
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
            // Only what was found, never what it said: no author, caption, title or any other text from the screen.
            "app" to app, "inReels" to obs.inReels, "fp" to (Fingerprint.of(app, obs.item) ?: ""),
            "hasAuthor" to i.author.isNotBlank(), "hasCaption" to i.caption.isNotBlank(), "hasAudio" to i.audio.isNotBlank(),
            "hasTitle" to i.title.isNotBlank(), "hasLikes" to i.likes.isNotBlank(),
        )).toString(), now)
        if (now - lastTree < 3000) return
        lastTree = now
        val tree = nodes.take(400).joinToString("\n") { n ->
            val b = n.bounds
            "${if (n.visible) "V" else "-"} ${n.id.ifEmpty { "-" }} ${n.cls.substringAfterLast('.')} [${b.left},${b.top},${b.right},${b.bottom}]"
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
