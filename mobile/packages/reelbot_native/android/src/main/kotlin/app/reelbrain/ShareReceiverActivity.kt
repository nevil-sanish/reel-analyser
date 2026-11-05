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
        val i = intent?.takeIf { it.action == Intent.ACTION_SEND }
        // The typed getParcelableExtra is Android 13+; minSdk is 29.
        @Suppress("DEPRECATION")
        val image = if (i?.type?.startsWith("image/") == true) i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) else null
        val text = i?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val now = System.currentTimeMillis()
        val message = when {
            image != null -> if (savePhoto(image, text, now)) "Saved ✓" else "Couldn't read that photo"
            else -> ShareUrls.extract(text)?.let { CounterDb.get(this).addShared(it, now); "Saved ✓" } ?: "Not a reel link"
        }
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
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
