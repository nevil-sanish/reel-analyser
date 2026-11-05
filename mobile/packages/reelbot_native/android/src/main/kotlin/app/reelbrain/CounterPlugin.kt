package app.reelbrain

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * CH-COUNTER. A real plugin (not a channel set up in MainActivity) so it is also attached to the
 * background engine `workmanager` starts; only pubspec plugins get registered there.
 */
class CounterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private val io = Executors.newFixedThreadPool(2)
        private val main = Handler(Looper.getMainLooper())
    }

    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "reelbot/counter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pendingItems" -> result.success(CounterDb.get(ctx).pending(call.argument<String>("status")))
            "setPendingStatus" -> {
                CounterDb.get(ctx).setStatus(call.argument<Number>("id")!!.toLong(), call.argument<String>("status")!!)
                result.success(null)
            }
            "fetchInstagram" -> offMain(result) {
                val r = InstagramFetcher.get(ctx).fetch(call.argument<String>("url")!!)
                mapOf(
                    "step" to r.step, "author" to r.media.author, "caption" to r.media.caption,
                    "thumbnailUrl" to r.media.thumbnailUrl, "videoPath" to r.videoPath,
                )
            }
            "saveDownload" -> offMain(result) {
                saveDownload(call.argument<String>("name")!!, call.argument<String>("text")!!)
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun offMain(result: MethodChannel.Result, work: () -> Any?) {
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
