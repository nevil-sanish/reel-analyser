package app.reelbrain

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings

/**
 * Daily time limits for apps and websites (full build), without reading the screen.
 *  - Apps: Android's usage events say which app is in front and for how long (Usage access); when its limit is used up the person is sent
 *    to the home screen (no block screen).
 *  - Websites: [DnsVpnService] reports which sites the phone looks up; the time they are in use is counted here, and at the limit
 *    their look-ups are refused (the page does not load).
 * Runs as a foreground service with a small notification, one check a second, and only while the screen is on.
 */
class LimitsService : Service() {
    companion object {
        private const val CHANNEL = "reelbot_limits"
        @Volatile var running = false

        fun overlayGranted(ctx: Context) = Settings.canDrawOverlays(ctx)

        /** Starts the service when there is a limit and Usage access, stops it otherwise; also starts or stops the website filter. */
        fun sync(ctx: Context) {
            CounterPlugin.io.execute {
                runCatching {
                    val l = CounterDb.get(ctx).currentLimits(System.currentTimeMillis())
                    val all = l.active + (l.pending ?: emptyList())
                    val i = Intent(ctx, LimitsService::class.java)
                    // Site limits need no Usage access (the website filter counts them); app limits do.
                    val needed = all.any { it.kind == "site" } || (all.isNotEmpty() && AppUsage.granted(ctx))
                    if (needed) ctx.startForegroundService(i) else ctx.stopService(i)
                    SiteFilterControl.sync(ctx, all.any { it.kind == "site" })
                }
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var db: CounterDb
    private lateinit var sink: CounterSink
    private var screenOn = true
    private var fg = ""
    private var seenTo = 0L
    private var lastBlock = 0L
    private var limitsAt = 0L
    private var limits: List<LimitItem> = emptyList()
    private var appUsed: Map<String, Long> = emptyMap()
    private var appUsedAt = 0L
    private var lastTick = 0L

    private val tick = object : Runnable {
        override fun run() {
            try { check() } catch (e: Exception) { /* next second */ }
            handler.postDelayed(this, 1000)
        }
    }

    private val screen = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            screenOn = i.action != Intent.ACTION_SCREEN_OFF
            if (!screenOn) fg = ""
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        db = CounterDb.get(this)
        sink = CounterSink(db)
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Time limits", NotificationManager.IMPORTANCE_MIN))
        val n = Notification.Builder(this, CHANNEL).setSmallIcon(applicationInfo.icon).setContentTitle("Time limits are on")
            .setContentText("Counting time in the apps and sites you limited.").setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(41, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(41, n)
        registerReceiver(screen, IntentFilter().apply { addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_SCREEN_ON) })
        seenTo = System.currentTimeMillis() - 3_600_000L
        running = true
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(tick)
        unregisterReceiver(screen)
        SiteFilter.sites = emptyList()
        SiteFilter.blocked = emptySet()
        super.onDestroy()
    }

    /** The app in front, from usage events since the last look: the last screen resumed, until it is paused or the screen goes off. */
    private fun foreground(now: Long) {
        val ev = getSystemService(UsageStatsManager::class.java).queryEvents(seenTo, now)
        val e = UsageEvents.Event()
        while (ev.hasNextEvent()) {
            ev.getNextEvent(e)
            when (e.eventType) {
                AppUsage.RESUMED -> fg = e.packageName ?: ""
                AppUsage.PAUSED, AppUsage.STOPPED -> if (e.packageName == fg) fg = ""
                AppUsage.SCREEN_OFF, AppUsage.KEYGUARD_SHOWN, AppUsage.SHUTDOWN -> fg = ""
            }
            seenTo = maxOf(seenTo, e.timeStamp)
        }
    }

    private fun check() {
        val now = System.currentTimeMillis()
        if (now - limitsAt > 2000) {
            limitsAt = now
            limits = db.currentLimits(now).active
            SiteFilter.sites = limits.filter { it.kind == "site" }
            if (limits.isEmpty()) { SiteFilterControl.sync(this, false); stopSelf(); return }
        }
        if (!screenOn) { lastTick = now; return }
        if (AppUsage.granted(this)) foreground(now)
        val date = localDate(now)
        val used = db.usedToday(date)
        // Sites: a site looked up in the last 30 s is in use; count the seconds since the last check.
        val step = (now - lastTick).coerceIn(0L, 2000L)
        lastTick = now
        if (step > 0) for (s in SiteFilter.active(now)) sink.addUse(date, s.key, step)
        SiteFilter.blocked = SiteFilter.sites.filter { AppLimits.isOver(it, used[it.key] ?: 0L) }.map { it.id }.toSet()
        if (now - lastBlock <= 4000) return
        // Apps: the one in front has a limit and it is used up.
        val app = limits.firstOrNull { it.kind == "app" && it.id == fg }
        if (app != null) {
            if (now - appUsedAt > 2000) { appUsed = AppUsage.todayMs(this, limits.filter { it.kind == "app" }.map { it.id }.toSet()); appUsedAt = now }
            if (AppLimits.isOver(app, appUsed[app.id] ?: 0L)) return show(app, now)
        }
        // Sites by VPN: a refused look-up is the whole block (the page fails to load). Nothing is drawn and nobody is sent home,
        // because a look-up can come from a prefetch or a background app the person never opened.
    }

    private fun show(item: LimitItem, now: Long) {
        lastBlock = now
        GoHome.now(this, AppLimits.message(item))
    }
}

class LimitsBootReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) { LimitsService.sync(c) }
}
