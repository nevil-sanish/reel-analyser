package app.reelbrain

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import app.reelbrain.core.R
import java.util.Calendar
import java.util.concurrent.TimeUnit

object Digest {
    const val LAST_OPENED = "last_opened"
    const val POSTED = "digest_posted"

    /** After 21:00, once a day, and only if you didn't open the app today. */
    fun shouldPost(openedToday: Boolean, postedToday: Boolean, hour: Int) = !openedToday && !postedToday && hour >= 21

    /**
     * "37 reels · 52 min · 3 saved: A, B, C". [reels] is null when the optional counter is off and [ms] when no time
     * is tracked (neither Usage access nor the counter), so the digest never shows a made-up 0. A nudge on an empty day.
     */
    fun text(reels: Long?, ms: Long?, saved: Int, titles: List<String>): String {
        if ((reels ?: 0L) == 0L && (ms ?: 0L) < 60000 && saved == 0) {
            return "Nothing saved today. Saw a reel worth keeping? Share it to Reel Bot for the key points."
        }
        val counts = listOfNotNull(reels?.let { "$it reels" }, ms?.let { "${it / 60000} min" }, "$saved saved").joinToString(" · ")
        return if (titles.isEmpty()) counts else "$counts: ${titles.take(3).joinToString(", ")}"
    }
}

/**
 * WM-DIGEST (IMPLEMENTATION §7). Runs hourly rather than once at 21:30: a 24 h period drifts, and
 * [Digest.shouldPost] keeps it to one notification per evening.
 */
class DigestWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    companion object {
        private const val CHANNEL = "reelbot_digest"

        /** Notifications that open the app when tapped: the digest, and "note ready" after a background run. */
        fun post(ctx: Context, id: Int, channel: String, channelName: String, title: String, text: String) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(channel, channelName, NotificationManager.IMPORTANCE_DEFAULT))
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            nm.notify(id, Notification.Builder(ctx, channel)
                .setSmallIcon(R.drawable.ic_stat_reelbot)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(open?.let { PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_IMMUTABLE) })
                .setAutoCancel(true)
                .build())
        }

        fun schedule(ctx: Context) {
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                "reelbot_digest", ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequest.Builder(DigestWorker::class.java, 1, TimeUnit.HOURS).build(),
            )
        }
    }

    override fun doWork(): Result {
        val ctx = applicationContext
        val prefs = ctx.getSharedPreferences(ReelCounterService.PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val today = localDate(now)
        val openedToday = localDate(prefs.getLong(Digest.LAST_OPENED, 0)) == today
        val postedToday = prefs.getString(Digest.POSTED, null) == today
        if (!Digest.shouldPost(openedToday, postedToday, Calendar.getInstance().get(Calendar.HOUR_OF_DAY))) return Result.success()

        val db = CounterDb.get(ctx)
        val day = db.daily(1, today)
        val (saved, titles) = db.savedToday(now)
        val counting = ReelCounterService.running || day.isNotEmpty()
        // Time in the apps when Usage access is on (as Insights shows it), else the counter's Reels/Shorts time.
        val appMs = AppUsage.load(ctx, 1)?.first?.values?.sum()
        val text = Digest.text(if (counting) day.sumOf { it["reels"] as Long } else null,
            appMs ?: if (counting) day.sumOf { it["ms"] as Long } else null, saved, titles)
        post(ctx, 2, CHANNEL, "Daily digest", "Today on Reels and Shorts", text)
        prefs.edit().putString(Digest.POSTED, today).apply()
        return Result.success()
    }
}
