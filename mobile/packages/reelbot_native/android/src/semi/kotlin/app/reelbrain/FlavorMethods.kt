package app.reelbrain

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The semi build has no counter, blocker, notifications or installer: it has nothing to add to the shared channel. */
object FlavorMethods {
    /** An earlier full install on this phone may have scheduled a daily digest; this build has no such worker. */
    fun onAttach(ctx: Context) {
        androidx.work.WorkManager.getInstance(ctx).cancelUniqueWork("reelbot_digest")
    }

    fun onErase(ctx: Context) {}

    fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result): Boolean = false
}
