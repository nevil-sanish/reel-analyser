package app.reelbrain

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The full build's side of the channel: the counter, the blocker and goals penalty, Usage access, notifications and the installer. */
object FlavorMethods {
    fun onAttach(ctx: Context) = DigestWorker.schedule(ctx)

    /** Erase all my data: the blocker photos too. */
    fun onErase(ctx: Context) = BlockPhotos.wipe(ctx)

    /** True when the call was handled here. */
    fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result): Boolean = Full(ctx).handle(call, result)

    private class Full(val ctx: Context) {
        fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
            when (call.method) {
                "daily" -> result.success(CounterDb.get(ctx).daily(call.argument<Int>("days") ?: 14, localDate(System.currentTimeMillis())))
                "hourly" -> result.success(CounterDb.get(ctx).hourly(call.argument<Int>("days") ?: 7, localDate(System.currentTimeMillis())))
                "appUsage" -> CounterPlugin.offMain(result) { appUsage(call.argument<Int>("days") ?: 7) }
                "seenItems" -> result.success(CounterDb.get(ctx).seenItems(call.argument<String>("date")!!))
                "debugState" -> result.success(CounterDb.get(ctx).debugState())
                "setCapture" -> {
                    val on = call.argument<Boolean>("on") == true
                    prefs().edit().putBoolean(ReelCounterService.CAPTURE, on).apply()
                    if (!on) CounterDb.get(ctx).clearCapture()
                    result.success(null)
                }
                "notifyNotes" -> {
                    DigestWorker.post(ctx, 3, "reelbot_notes", "Notes ready",
                        call.argument<String>("title")!!, call.argument<String>("text")!!)
                    result.success(null)
                }
                "markOpened" -> {
                    prefs().edit().putLong(Digest.LAST_OPENED, System.currentTimeMillis()).apply()
                    val now = System.currentTimeMillis()
                    CounterPlugin.io.execute { runCatching { CounterDb.get(ctx).prune(localDate(now), now); BlockPhotos.wipe(ctx) } } // retention: see the Privacy Policy
                    result.success(null)
                }
                "blockState" -> result.success(blockState())
                "blockSave" -> result.success(blockSave(call.argument<String>("config")!!))
                "blockRemove" -> {
                    val db = CounterDb.get(ctx)
                    db.saveBlockState(BlockState())
                    db.addEvent(System.currentTimeMillis(), "removed")
                    BlockPhotos.wipe(ctx)
                    result.success(null)
                }
                "blockCancel" -> { // the app has already taken the typed paragraph
                    val db = CounterDb.get(ctx)
                    val now = System.currentTimeMillis()
                    db.saveBlockState(db.currentBlockState(now).copy(suspendedDate = localDate(now)))
                    db.addEvent(now, "cancelled")
                    result.success(null)
                }
                "punishSet" -> {
                    val apps = call.argument<List<String>>("apps").orEmpty().filter { it == "instagram" || it == "youtube" }.toSet()
                    CounterDb.get(ctx).setPunish(Punish(call.argument<String>("until"), apps, call.argument<Int>("streak") ?: 0))
                    result.success(null)
                }
                "blockHistory" -> result.success(CounterDb.get(ctx).events(200))
                "detectionConsent" -> result.success(prefs().getBoolean(ReelCounterService.CONSENT, false))
                "setDetectionConsent" -> {
                    val on = call.argument<Boolean>("on") == true
                    prefs().edit().putBoolean(ReelCounterService.CONSENT, on).apply()
                    if (!on) { // withdrawing the opt-in also stops and clears the debug capture
                        prefs().edit().putBoolean(ReelCounterService.CAPTURE, false).apply()
                        CounterDb.get(ctx).clearCapture()
                    }
                    result.success(null)
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
                else -> return false
            }
            return true
        }

        private fun launch(i: Intent) = launchIntent(ctx, i)

        private fun prefs() = ctx.getSharedPreferences(ReelCounterService.PREFS, Context.MODE_PRIVATE)

        /** The blocker for the Blocker screen: the rules in force, any waiting change, today's reel time, and whether editing is open. */
        private fun blockState(): Map<String, Any?> {
            val now = System.currentTimeMillis()
            val db = CounterDb.get(ctx)
            val s = db.currentBlockState(now)
            val date = localDate(now)
            return mapOf(
                "active" to s.active?.toJson(), "pending" to s.pending?.toJson(), "pendingFrom" to s.pendingFrom,
                "suspendedToday" to (s.suspendedDate == date),
                "nextEdit" to BlockPolicy.nextMidnight(now),
                "used" to db.usedToday(date), "now" to now,
            )
        }

        /** "ok" or "invalid". */
        private fun blockSave(json: String): String {
            val cfg = BlockConfig.parse(json)?.takeIf { it.items.isNotEmpty() } ?: return "invalid"
            val now = System.currentTimeMillis()
            val db = CounterDb.get(ctx)
            val before = db.currentBlockState(now)
            val after = BlockPolicy.save(before, cfg, now)
            db.saveBlockState(after)
            db.addEvent(now, if (before.active == null) "set" else "changed")
            return "ok"
        }
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
    }
}
