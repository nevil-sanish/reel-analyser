package app.reelbrain

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/** Face photos from before 1.2.0.0, when cancelling took one; old photos are deleted. */
object BlockPhotos {
    fun wipe(ctx: Context) { java.io.File(ctx.filesDir, "blocker").deleteRecursively() }
}

/**
 * What a block does: no screen is drawn. The person is sent to the home screen, with a one-line note. The Accessibility Home
 * action is used when that service is on; otherwise the Home screen is started (which needs "Display over other apps").
 */
object GoHome {
    fun now(ctx: Context, note: String) {
        val done = ReelCounterService.home()
        if (!done && LimitsService.overlayGranted(ctx)) {
            runCatching {
                ctx.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
        if (note.isNotBlank()) Handler(Looper.getMainLooper()).post { Toast.makeText(ctx.applicationContext, note, Toast.LENGTH_LONG).show() }
    }
}
