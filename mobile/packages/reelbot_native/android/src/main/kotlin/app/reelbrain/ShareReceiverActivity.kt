package app.reelbrain

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import java.io.File

/** Transparent, no Flutter: queue the shared link or photo and drop you straight back where you were. */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val i = intent?.takeIf { it.action == Intent.ACTION_SEND || it.action == Intent.ACTION_SEND_MULTIPLE }
        // The typed getParcelable*Extra calls are Android 13+; minSdk is 29.
        @Suppress("DEPRECATION")
        val images: List<Uri> = when {
            i?.type?.startsWith("image/") != true -> emptyList()
            i.action == Intent.ACTION_SEND_MULTIPLE -> i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
            else -> listOfNotNull(i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        val text = i?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val now = System.currentTimeMillis()
        // Decoding several photos can take seconds, so it runs off the main thread; we finish once it's done.
        Thread {
            val message = when {
                images.isNotEmpty() -> {
                    // One note per image; `now + n` keeps file names unique and the queue in share order.
                    val saved = images.withIndex().count { (n, uri) -> savePhoto(uri, text, now + n) }
                    when {
                        saved == 0 -> "Couldn't read that photo"
                        images.size == 1 -> "Saved ✓"
                        saved == images.size -> "Saved $saved photos ✓"
                        else -> "Saved $saved of ${images.size} photos"
                    }
                }
                else -> ShareUrls.extract(text)?.let { CounterDb.get(this).addShared(it, now); "Saved ✓" } ?: "Not a reel link"
            }
            if (message.startsWith("Saved")) AnalyseKick.enqueue(applicationContext) // analyse now, app open or not
            runOnUiThread {
                Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
                finish()
            }
        }.start()
    }

    /**
     * v0.8: a shared photo or screenshot is copied into the app (the sender's URI stops working once we finish),
     * shrunk to at most 1280 px as JPEG to keep the AI request small, and queued as `photo:<path>`.
     */
    private fun savePhoto(uri: Uri, caption: String, now: Long): Boolean = try {
        val bmp = ImageDecoder.decodeBitmap(ImageDecoder.createSource(contentResolver, uri)) { d, info, _ ->
            val s = info.size
            val scale = minOf(1f, 1280f / maxOf(s.width, s.height))
            d.setTargetSize((s.width * scale).toInt().coerceAtLeast(1), (s.height * scale).toInt().coerceAtLeast(1))
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        val f = File(filesDir, "photos/$now.jpg").apply { parentFile!!.mkdirs() }
        f.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 82, it) }
        CounterDb.get(this).addPhoto(f.path, caption.take(2000), now)
        true
    } catch (e: Exception) {
        false
    }
}
