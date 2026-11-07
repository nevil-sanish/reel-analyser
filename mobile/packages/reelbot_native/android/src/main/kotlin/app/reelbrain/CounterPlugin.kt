package app.reelbrain

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.accessibility.AccessibilityManager
import app.reelbrain.core.R
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
        private val io = Executors.newFixedThreadPool(4)
        private val main = Handler(Looper.getMainLooper())
    }

    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "reelbot/counter")
        channel.setMethodCallHandler(this)
        if (semiBuild) {
            // The semi build posts no notifications: drop a digest an earlier (full) install had scheduled.
            androidx.work.WorkManager.getInstance(ctx).cancelUniqueWork("reelbot_digest")
        } else {
            DigestWorker.schedule(ctx)
        }
    }

    private val semiBuild get() = ctx.resources.getBoolean(R.bool.reelbot_semi)

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
            "daily" -> result.success(CounterDb.get(ctx).daily(call.argument<Int>("days") ?: 14, localDate(System.currentTimeMillis())))
            "hourly" -> result.success(CounterDb.get(ctx).hourly(call.argument<Int>("days") ?: 7, localDate(System.currentTimeMillis())))
            "appUsage" -> offMain(result) { appUsage(call.argument<Int>("days") ?: 7) }
            "seenItems" -> result.success(CounterDb.get(ctx).seenItems(call.argument<String>("date")!!))
            "debugState" -> result.success(CounterDb.get(ctx).debugState())
            "setCapture" -> {
                val on = call.argument<Boolean>("on") == true
                prefs().edit().putBoolean(ReelCounterService.CAPTURE, on).apply()
                if (!on) CounterDb.get(ctx).clearCapture()
                result.success(null)
            }
            "notifyNotes" -> {
                if (!semiBuild) DigestWorker.post(ctx, 3, "reelbot_notes", "Notes ready",
                    call.argument<String>("title")!!, call.argument<String>("text")!!)
                result.success(null)
            }
            "markOpened" -> {
                prefs().edit().putLong(Digest.LAST_OPENED, System.currentTimeMillis()).apply()
                val now = System.currentTimeMillis()
                io.execute { runCatching { CounterDb.get(ctx).prune(localDate(now), now) } } // retention: see the Privacy Policy
                result.success(null)
            }
            "armWatchdog" -> { AnalyseKick.arm(ctx); result.success(null) }
            "disarmWatchdog" -> { AnalyseKick.disarm(ctx); result.success(null) }
            "eraseAll" -> offMain(result) {
                CounterDb.get(ctx).eraseAll()
                java.io.File(ctx.filesDir, "photos").deleteRecursively()
                prefs().edit().clear().apply()
                (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).cancelAll()
                null
            }
            "status" -> result.success(status())
            "updateDir" -> result.success(java.io.File(ctx.cacheDir, "update").apply { mkdirs() }.path)
            "installApk" -> result.success(installApk(call.argument<String>("path")!!))
            "openUrl" -> result.success(launch(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!))))
            "openUsageAccess" -> result.success(
                launch(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${ctx.packageName}")))
                    || launch(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)))
            "openAccessibilitySettings" -> result.success(launch(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)))
            "openAppInfo" -> result.success(launch(appInfo()))
            "openNotificationSettings" -> result.success(launch(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)))
            "requestBatteryExemption" -> result.success(
                launch(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}")))
                    || launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)))
            "openAutostart" -> result.success(autostart.any { (p, a) -> launch(Intent().setComponent(ComponentName(p, a))) } || launch(appInfo()))
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

    private fun prefs() = ctx.getSharedPreferences(ReelCounterService.PREFS, Context.MODE_PRIVATE)

    private fun status(): Map<String, Any?> {
        val ours = ComponentName(ctx, ReelCounterService::class.java)
        // The AccessibilityManager list, not the raw ENABLED_ACCESSIBILITY_SERVICES setting: on a Nothing phone with
        // Android 16 the setting read back without our service while it was on and bound, so setup said "off".
        val enabled = ReelCounterService.running || ctx.getSystemService(AccessibilityManager::class.java)
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { ComponentName(it.resolveInfo.serviceInfo.packageName, it.resolveInfo.serviceInfo.name) == ours }
        return mapOf(
            "serviceEnabled" to enabled,
            "serviceRunning" to ReelCounterService.running,
            "batteryExempt" to ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName),
            "notificationsAllowed" to ctx.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "capture" to prefs().getBoolean(ReelCounterService.CAPTURE, false),
            "usageAccess" to AppUsage.granted(ctx),
        )
    }

    /** Time in Instagram and YouTube for the last [days] days (today included), by day and by hour of day. */
    private fun appUsage(days: Int): Map<String, Any?> {
        val (daily, hourly) = AppUsage.load(ctx, days)
            ?: return mapOf("granted" to false, "daily" to emptyList<Any>(), "hourly" to emptyList<Any>())
        return mapOf(
            "granted" to true,
            "daily" to daily.map { (k, ms) -> mapOf("date" to k.first, "app" to k.second, "ms" to ms) },
            "hourly" to hourly.map { (k, ms) -> mapOf("hour" to k.first, "app" to k.second, "ms" to ms) },
        )
    }

    private fun appInfo() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}"))

    /** No activity here (the plugin also runs in the background engine), so start from the app context. */
    /** Hands a downloaded update to Android's installer. Only a file in the app's own update folder is accepted. */
    private fun installApk(path: String): String {
        val dir = java.io.File(ctx.cacheDir, "update").canonicalFile
        val f = java.io.File(path).canonicalFile
        if (f.parentFile != dir) return "failed: the file is not in the update folder ($f)"
        if (!f.isFile) return "failed: the downloaded file is missing"
        if (!ctx.packageManager.canRequestPackageInstalls()) {
            launch(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")))
            return "needs_permission"
        }
        return try {
            val uri = androidx.core.content.FileProvider.getUriForFile(ctx, "${ctx.packageName}.updates", f)
            val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(i)
            "started"
        } catch (e: Exception) {
            "failed: ${e.javaClass.simpleName} ${e.message}"
        }
    }

    private fun launch(i: Intent): Boolean = try {
        ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    /** OEM autostart screens (IMPLEMENTATION §3.5), tried in order. */
    private val autostart = listOf(
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
        "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
        "com.asus.mobilemanager" to "com.asus.mobilemanager.powersaver.PowerSaverSettings",
    )

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
