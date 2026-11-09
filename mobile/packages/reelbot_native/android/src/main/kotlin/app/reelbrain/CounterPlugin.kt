package app.reelbrain

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Starts an activity from the app context: no activity here (the plugin also runs in the background engine). */
internal fun launchIntent(ctx: Context, i: Intent): Boolean = try {
    ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    true
} catch (e: Exception) {
    false
}

/**
 * CH-COUNTER. A real plugin (not a channel set up in MainActivity) so it is also attached to the
 * background engine `workmanager` starts; only pubspec plugins get registered there.
 * Only what both builds use is here; everything else goes to [FlavorMethods], which differs per build.
 */
class CounterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        /** The app's one SharedPreferences file (the full build keeps its flags in it). The name must not change. */
        const val PREFS = "reelbot"

        val io = Executors.newFixedThreadPool(4)
        private val main = Handler(Looper.getMainLooper())

        fun offMain(result: MethodChannel.Result, work: () -> Any?) {
            io.execute {
                try {
                    val v = work()
                    main.post { result.success(v) }
                } catch (e: RateLimitedException) {
                    main.post { result.error("rate_limited", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("failed", e.toString(), null) }
                }
            }
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "reelbot/counter")
        channel.setMethodCallHandler(this)
        FlavorMethods.onAttach(ctx)
        // Retention (Privacy Policy): finished queue entries go after 30 days.
        io.execute { runCatching { CounterDb.get(ctx).pruneQueue(System.currentTimeMillis()) } }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pendingItems" -> result.success(CounterDb.get(ctx).pending(call.argument<String>("status")))
            "setPendingStatus" -> {
                CounterDb.get(ctx).setStatus(
                    call.argument<Number>("id")!!.toLong(), call.argument<String>("status")!!, call.argument<String>("title") ?: "")
                result.success(null)
            }
            "fetchInstagram" -> offMain(result) {
                val r = InstagramFetcher.get(ctx).fetch(call.argument<String>("url")!!)
                mapOf(
                    "step" to r.step, "author" to r.media.author, "caption" to r.media.caption,
                    "thumbnailUrl" to r.media.thumbnailUrl, "videoPath" to r.videoPath,
                    "images" to r.media.images.take(10),
                )
            }
            "seal" -> offMain(result) { SecretBox.seal(call.argument<String>("text")!!) }
            "unseal" -> offMain(result) { SecretBox.unseal(call.argument<String>("text")!!) }
            "sweepPhotos" -> offMain(result) {
                val keep = call.argument<List<String>>("keep").orEmpty().toSet()
                java.io.File(ctx.filesDir, "photos").listFiles()?.filter { it.path !in keep }?.forEach { it.delete() }
                null
            }
            "videoFrames" -> offMain(result) { videoFrames(call.argument<String>("path")!!, call.argument<Int>("count") ?: 6) }
            "saveDownload" -> offMain(result) {
                saveDownload(call.argument<String>("name")!!, call.argument<String>("text")!!)
                null
            }
            "armWatchdog" -> { AnalyseKick.arm(ctx); result.success(null) }
            "disarmWatchdog" -> { AnalyseKick.disarm(ctx); result.success(null) }
            "eraseAll" -> offMain(result) {
                CounterDb.get(ctx).eraseAll()
                java.io.File(ctx.filesDir, "photos").deleteRecursively()
                FlavorMethods.onErase(ctx)
                ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
                (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).cancelAll()
                null
            }
            "openUrl" -> result.success(launchIntent(ctx, Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!))))
            else -> if (!FlavorMethods.handle(ctx, call, result)) result.notImplemented()
        }
    }

    /** Evenly spaced 512 px JPEG frames, for providers that take images but not video (OpenAI, Claude). */
    private fun videoFrames(path: String, count: Int): List<ByteArray> {
        val r = android.media.MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val durUs = (r.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) * 1000
            return (0 until count).mapNotNull { i ->
                val f = r.getScaledFrameAtTime(durUs * (2 * i + 1) / (2 * count),
                    android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 512, 512) ?: return@mapNotNull null
                java.io.ByteArrayOutputStream().also { f.compress(android.graphics.Bitmap.CompressFormat.JPEG, 70, it) }.toByteArray()
            }
        } finally {
            r.release()
        }
    }

    /** Export: `Downloads/ReelBot/<name>` via MediaStore (minSdk 29, so no storage permission). */
    private fun saveDownload(name: String, text: String) {
        val resolver = ctx.contentResolver
        val dir = Environment.DIRECTORY_DOWNLOADS + "/ReelBot"
        // Replace an earlier export of the same file rather than piling up "name (1)" copies.
        resolver.delete(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(name, "$dir/"),
        )
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, if (name.endsWith(".json")) "application/json" else "text/markdown")
            put(MediaStore.MediaColumns.RELATIVE_PATH, dir)
        }) ?: error("could not create $name")
        resolver.openOutputStream(uri)!!.use { it.write(text.toByteArray()) }
    }
}
