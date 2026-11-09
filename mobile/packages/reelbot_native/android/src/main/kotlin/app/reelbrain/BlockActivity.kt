package app.reelbrain

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.drawable.GradientDrawable
import android.media.ExifInterface
import android.media.FaceDetector
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.FileProvider
import java.io.File
import java.util.Calendar

/** Today's face photo for cancelling the block. It is kept for the day only. */
object BlockPhotos {
    fun dir(ctx: Context) = File(ctx.filesDir, "blocker").apply { mkdirs() }
    fun today(ctx: Context, date: String) = File(dir(ctx), "$date.jpg")

    /** Deletes every photo that isn't today's. */
    fun sweep(ctx: Context, date: String) {
        File(ctx.filesDir, "blocker").listFiles()?.filter { it.name != "$date.jpg" }?.forEach { it.delete() }
    }

    fun wipe(ctx: Context) { File(ctx.filesDir, "blocker").deleteRecursively() }
}

/** Is there a face in the photo? Android's own detector, on the device. Camera files are often saved sideways, so turn them first. */
object FaceCheck {
    fun hasFace(path: String): Boolean = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }.also { BitmapFactory.decodeFile(path, it) }
        val opts = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 800) }
        var bmp = BitmapFactory.decodeFile(path, opts)!!
        val deg = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f; ExifInterface.ORIENTATION_ROTATE_180 -> 180f; ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (deg != 0f) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(deg) }, true)
        val w = bmp.width and 1.inv()
        val small = Bitmap.createBitmap(bmp, 0, 0, w, bmp.height).copy(Bitmap.Config.RGB_565, false)
        val faces = arrayOfNulls<FaceDetector.Face>(3)
        FaceDetector(small.width, small.height, 3).findFaces(small, faces) > 0
    } catch (e: Exception) {
        false
    }
}

/**
 * The block screen: shown over a reel when the limit or schedule says no. It offers to cancel the block for the day, which
 * takes a photo of a face, shows it on a card with a quote, and asks once more. Plain views: it must open at once, with no
 * Flutter start-up, and it reads nothing from the screen.
 */
class BlockActivity : Activity() {
    companion object {
        const val SURFACE = "surface"
        const val REASON = "reason"
        const val MODE = "mode" // "block" or "cancel" (straight to the photo, from the app)
        private const val REQ_PHOTO = 41
        private const val HOLD_MS = 3000L
        val quotes = listOf(
            "Small choices today become the person you are tomorrow.",
            "You don't have to be perfect. You just have to come back to your goal.",
            "Every minute you keep is a minute for something that matters to you.",
            "Discipline is choosing what you want most over what you want now.",
            "You set this limit for a reason. Remember it.",
            "Progress is quiet. Keep going.",
            "The urge passes. Your goals stay.",
        )
    }

    private lateinit var db: CounterDb
    private val now get() = System.currentTimeMillis()
    private val date get() = localDate(now)
    private var surface = ""
    private var reason = ""
    private var inCamera = false
    private var unlocked = true
    private val quote get() = quotes[Calendar.getInstance().get(Calendar.DAY_OF_YEAR) % quotes.size]

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        db = CounterDb.get(this)
        surface = intent.getStringExtra(SURFACE) ?: ""
        reason = intent.getStringExtra(REASON) ?: ""
        BlockPhotos.sweep(this, date)
        if (intent.getStringExtra(MODE) == "cancel") startCancel() else { unlocked = false; showBlock() }
    }

    override fun onBackPressed() { if (unlocked) goHome() }

    override fun onStop() {
        super.onStop()
        if (!inCamera && !isChangingConfigurations) finish() // a stale block screen must not wait in Recents
    }

    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun text(t: String, size: Float, bold: Boolean = false, color: Int = Color.WHITE) = TextView(this).apply {
        text = t; textSize = size; setTextColor(color); gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun button(t: String, filled: Boolean, onClick: () -> Unit) = Button(this).apply {
        text = t; isAllCaps = false; textSize = 16f
        setTextColor(if (filled) Color.parseColor("#0B2B22") else Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = dp(28).toFloat()
            if (filled) setColor(Color.parseColor("#7BE0A8")) else setStroke(dp(1), Color.parseColor("#88FFFFFF"))
            if (!filled) setColor(Color.TRANSPARENT)
        }
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(54)).apply { topMargin = dp(12) }
        setOnClickListener { onClick() }
    }

    private fun screen(vararg views: View) {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(56), dp(28), dp(32))
            views.forEach(::addView)
        }
        setContentView(ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#0B2B22")); isFillViewport = true; addView(col)
        })
    }

    /** The block screen holds for [HOLD_MS] before Close works, so it can't be dismissed on reflex. */
    private fun showBlock() {
        val close = button("Close (3)", true) { goHome() }.apply { isEnabled = false; alpha = 0.5f }
        screen(
            text("Blocked for now", 28f, true),
            text(quote, 20f, color = Color.parseColor("#B8D8C8")),
            close,
        )
        val start = SystemClock.elapsedRealtime()
        val tick = object : Runnable {
            override fun run() {
                val left = HOLD_MS - (SystemClock.elapsedRealtime() - start)
                if (left <= 0) { close.text = "Close"; close.isEnabled = true; close.alpha = 1f; unlocked = true; return }
                close.text = "Close (${(left + 999) / 1000})"
                close.postDelayed(this, 200)
            }
        }
        close.post(tick)
    }

    private fun startCancel() {
        db.addEvent(now, "cancel_try", surface)
        val file = BlockPhotos.today(this, date).apply { delete() }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        val i = Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri)
            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .putExtra("android.intent.extras.CAMERA_FACING", 1)
            .putExtra("android.intent.extras.LENS_FACING_FRONT", 1)
            .putExtra("android.intent.extra.USE_FRONT_CAMERA", true)
        try {
            inCamera = true
            startActivityForResult(i, REQ_PHOTO)
        } catch (e: Exception) {
            inCamera = false
            screen(text("No camera app found", 24f, true), text("Cancelling needs a photo of your face.", 16f), button("Close", true) { goHome() })
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        inCamera = false
        if (requestCode != REQ_PHOTO) return
        val f = BlockPhotos.today(this, date)
        when {
            resultCode != RESULT_OK || f.length() == 0L -> noFace("No photo taken.")
            !FaceCheck.hasFace(f.path) -> { f.delete(); noFace("No face found in the photo.") }
            else -> showCard(f)
        }
    }

    private fun noFace(msg: String) = screen(
        text(msg, 22f, true), text("Take a photo of your face to cancel the block.", 16f),
        button("Try again", true) { startCancel() }, button("Keep the block", false) { db.addEvent(now, "kept", surface); showKept() },
    )

    private fun showCard(photo: File) {
        val img = ImageView(this).apply {
            setImageBitmap(BitmapFactory.decodeFile(photo.path, BitmapFactory.Options().apply { inSampleSize = 2 }))
            adjustViewBounds = true; scaleType = ImageView.ScaleType.CENTER_CROP
            layoutParams = LinearLayout.LayoutParams(dp(220), dp(220)).apply { bottomMargin = dp(12) }
            clipToOutline = true
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(v: View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, dp(28).toFloat())
            }
        }
        screen(
            img, text(quote, 18f), text("Do you really want to cancel the block for today?", 20f, true),
            button("Yes, cancel it for today", false) {
                db.saveBlockState(db.currentBlockState(now).copy(suspendedDate = date))
                db.addEvent(now, "cancelled", surface)
                screen(text("Block cancelled for today", 26f, true), text("It comes back at midnight.", 16f), button("Continue", true) { finish() })
            },
            button("No, keep the block", true) { db.addEvent(now, "kept", surface); showKept() },
        )
    }

    private fun showKept() {
        BlockPhotos.today(this, date).delete()
        screen(
            text("Well done", 28f, true), text("Choosing to keep your limit takes strength. I'm proud of you for it.", 18f),
            text(quote, 16f, color = Color.parseColor("#B8D8C8")), button("Close", true) { goHome() },
        )
    }
}
