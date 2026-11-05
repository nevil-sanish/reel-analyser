package app.reelbrain

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.work.testing.WorkManagerTestInitHelper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** CH-COUNTER through a real MethodChannel: calls go in and replies come back encoded, as from Dart. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CounterPluginTest {
    private class Messenger : BinaryMessenger {
        val handlers = HashMap<String, BinaryMessenger.BinaryMessageHandler>()
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }
    }

    private val ctx: Context = ApplicationProvider.getApplicationContext()
    private val messenger = Messenger()

    @Before fun attach() {
        WorkManagerTestInitHelper.initializeTestWorkManager(ctx) // onAttachedToEngine schedules the digest
        // The plugin only reads the context and messenger; reflection gets past the @NonNull engine parts.
        val binding = FlutterPlugin.FlutterPluginBinding::class.java.constructors.single()
            .newInstance(ctx, null, messenger, null, null, null, null) as FlutterPlugin.FlutterPluginBinding
        CounterPlugin().onAttachedToEngine(binding)
    }

    /** Sends one call and waits for its reply; off-main calls reply through the main looper. */
    private fun call(method: String, args: Map<String, Any?> = emptyMap()): Any? {
        val codec = StandardMethodCodec.INSTANCE
        var reply: ByteBuffer? = null
        messenger.handlers.getValue("reelbot/counter")
            .onMessage(codec.encodeMethodCall(MethodCall(method, args)).also { it.rewind() }) { reply = it }
        val until = System.currentTimeMillis() + 5_000
        while (reply == null && System.currentTimeMillis() < until) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        return codec.decodeEnvelope(reply!!.also { it.rewind() })
    }

    // T-CH-01
    @Test fun pendingItemsAndSetPendingStatusRoundTrip() {
        CounterDb.get(ctx).addShared(ShareUrls.extract("https://www.instagram.com/reel/ABC123/?igsh=x")!!, 1_000)
        @Suppress("UNCHECKED_CAST")
        val queued = call("pendingItems", mapOf("status" to "queued")) as List<Map<String, Any?>>
        val item = queued.single { it["url"] == "https://www.instagram.com/reel/ABC123/" }
        assertEquals("instagram", item["app"])
        assertEquals(1_000L, (item["createdAt"] as Number).toLong())

        // Dart sends ids as int when they fit; the plugin takes any Number.
        assertEquals(null, call("setPendingStatus", mapOf("id" to (item["id"] as Number).toInt(), "status" to "done", "title" to "Rice")))
        @Suppress("UNCHECKED_CAST")
        val done = call("pendingItems", mapOf("status" to "done")) as List<Map<String, Any?>>
        assertEquals(item["id"], done.single()["id"])
        assertTrue((call("pendingItems", mapOf("status" to "queued")) as List<*>).none { (it as Map<*, *>)["id"] == item["id"] })
        // The title written through the channel is what the digest reads.
        assertEquals(1 to listOf("Rice"), CounterDb.get(ctx).savedToday(1_000))
    }

    // T-CH-02 (Kotlin side): an exception off the main thread comes back as a "failed" error, not a crash.
    @Test fun fetchInstagramErrorBecomesFailedCode() {
        val e = runCatching { call("fetchInstagram", mapOf("url" to "https://example.com/x")) }.exceptionOrNull()
        assertTrue(e is FlutterException)
        assertEquals("failed", (e as FlutterException).code)
        assertTrue(e.message!!.contains("not an Instagram link"))
    }

    @Test fun unknownMethodIsNotImplemented() {
        // decodeEnvelope returns null for an empty (notImplemented) reply.
        val codec = StandardMethodCodec.INSTANCE
        var reply: ByteBuffer? = ByteBuffer.allocate(1)
        messenger.handlers.getValue("reelbot/counter")
            .onMessage(codec.encodeMethodCall(MethodCall("nope", null)).also { it.rewind() }) { reply = it }
        assertEquals(null, reply)
    }
}
