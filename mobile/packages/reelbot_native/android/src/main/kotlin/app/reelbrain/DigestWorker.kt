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
import java.util.Calendar
import java.util.concurrent.TimeUnit

object Digest {
    const val LAST_OPENED = "last_opened"
    const val POSTED = "digest_posted"

    /** After 21:00, once a day, and only if you didn't open the app today. */
    fun shouldPost(openedToday: Boolean, postedToday: Boolean, hour: Int) = !openedToday && !postedToday && hour >= 21

    /** "37 reels · 52 min · 3 saved: A, B, C"; without titles when nothing has been analysed yet. */
    fun text(reels: Long, ms: Long, saved: Int, titles: List<String>): String {
        val counts = "$reels reels · ${ms / 60000} min · $saved saved"
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
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Daily digest", NotificationManager.IMPORTANCE_DEFAULT))
        val text = Digest.text(day.sumOf { it["reels"] as Long }, day.sumOf { it["ms"] as Long }, saved, titles)
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        nm.notify(2, Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("Today on Reels and Shorts")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open?.let { PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_IMMUTABLE) })
            .setAutoCancel(true)
            .build())
        prefs.edit().putString(Digest.POSTED, today).apply()
        return Result.success()
    }
}
