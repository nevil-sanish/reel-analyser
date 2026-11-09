package app.reelbrain

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertFalse
import org.junit.Test

/** The semi build has nothing behind the Full-only channel methods: they are handed back as "not implemented". */
class SemiSeamTest {
    @Test fun fullOnlyMethodsAreNotHandled() {
        val ctx = null as android.content.Context? ?: android.content.ContextWrapper(null)
        for (m in listOf("punishSet", "blockSave", "daily", "appUsage", "installApk", "setDetectionConsent", "notifyNotes", "status")) {
            assertFalse(m, FlavorMethods.handle(ctx, MethodCall(m, null), object : MethodChannel.Result {
                override fun success(r: Any?) {}
                override fun error(c: String, m: String?, d: Any?) {}
                override fun notImplemented() {}
            }))
        }
    }
}
