package app.reelbrain

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager

/**
 * Starts an analysis run right now, even when the app is closed. The periodic task only fires every 15 minutes or so, so a
 * freshly shared reel used to wait that long. This queues one expedited run of the same Dart task the periodic job uses
 * (workmanager's BackgroundWorker, which starts a headless engine); Dart then works through the queue.
 * The class is reached by name so this module needs no compile-time link to the workmanager plugin, and a failure here
 * only means the next periodic run does the work instead.
 */
object AnalyseKick {
    private const val TASK_KEY = "dev.fluttercommunity.workmanager.DART_TASK"
    private const val UNIQUE_KEY = "dev.fluttercommunity.workmanager.UNIQUE_NAME"
    const val NAME = "analyse-now"

    private const val WATCHDOG = "analyse-watchdog"

    /**
     * A dead-man's switch for a run inside the app: armed ~100 s ahead and pushed back by every heartbeat, cancelled when the
     * run ends. If the app is killed mid-run the heartbeats stop, and the watchdog restarts the analysis in the background.
     */
    fun arm(ctx: Context, delaySeconds: Long = 100) {
        try {
            WorkManager.getInstance(ctx).enqueueUniqueWork(WATCHDOG, ExistingWorkPolicy.REPLACE, request(delaySeconds, expedited = false))
        } catch (e: Throwable) {
            Log.w("ReelBot", "could not arm the analysis watchdog: $e")
        }
    }

    fun disarm(ctx: Context) {
        try {
            WorkManager.getInstance(ctx).cancelUniqueWork(WATCHDOG)
        } catch (e: Throwable) {
            Log.w("ReelBot", "could not disarm the analysis watchdog: $e")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun request(delaySeconds: Long, expedited: Boolean): OneTimeWorkRequest {
        val worker = Class.forName("dev.fluttercommunity.workmanager.BackgroundWorker") as Class<out ListenableWorker>
        return OneTimeWorkRequest.Builder(worker)
            .setInputData(Data.Builder().putString(TASK_KEY, "analyse").putString(UNIQUE_KEY, if (expedited) NAME else WATCHDOG).build())
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .apply {
                if (delaySeconds > 0) setInitialDelay(delaySeconds, java.util.concurrent.TimeUnit.SECONDS)
                if (expedited) setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }
            .build()
    }

    fun enqueue(ctx: Context) {
        try {
            // A share that arrives while a run is going is queued behind it, so it is never missed.
            WorkManager.getInstance(ctx).enqueueUniqueWork(NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request(0, expedited = true))
        } catch (e: Throwable) {
            Log.w("ReelBot", "could not start analysis now: $e")
        }
    }
}
