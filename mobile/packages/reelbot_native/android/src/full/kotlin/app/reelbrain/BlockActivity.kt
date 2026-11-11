package app.reelbrain

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Calendar

/** Face photos from before 1.2.0.0, when cancelling took one. Cancelling now takes a typed paragraph; old photos are deleted. */
object BlockPhotos {
    fun wipe(ctx: Context) { java.io.File(ctx.filesDir, "blocker").deleteRecursively() }
}

/**
 * The block screen: shown over a reel when the limit or schedule says no. Cancelling for the day is done in the app, with a
 * typed paragraph. Plain views: it must open at once, with no Flutter start-up, and it reads nothing from the screen.
 */
class BlockActivity : Activity() {
    companion object {
        const val SURFACE = "surface"
        const val REASON = "reason"
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

    private var surface = ""
    private var reason = ""
    private var unlocked = false
    private val quote get() = quotes[Calendar.getInstance().get(Calendar.DAY_OF_YEAR) % quotes.size]

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        surface = intent.getStringExtra(SURFACE) ?: ""
        reason = intent.getStringExtra(REASON) ?: ""
        showBlock()
        window.decorView.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
    }

    override fun onBackPressed() { if (unlocked) goHome() }

    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) finish() // a stale block screen must not wait in Recents
    }

    private fun goHome() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun text(t: String, size: Float, bold: Boolean = false, color: Int = Color.parseColor("#F6F1E4")) = TextView(this).apply {
        text = t; textSize = size; setTextColor(color); gravity = Gravity.CENTER
        // Titles and quotes in the system serif, to match the app's classic look.
        setTypeface(android.graphics.Typeface.create("serif", if (bold) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL))
        setLineSpacing(0f, 1.15f)
        setPadding(0, dp(8), 0, dp(8))
    }

    private fun button(t: String, filled: Boolean, onClick: () -> Unit) = Button(this).apply {
        text = t; isAllCaps = false; textSize = 16f
        setTextColor(if (filled) Color.parseColor("#0F0E0B") else Color.WHITE)
        background = GradientDrawable().apply {
            cornerRadius = dp(28).toFloat()
            if (filled) setColor(Color.parseColor("#C9A227")) else setStroke(dp(1), Color.parseColor("#99C9A227"))
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
            setBackgroundColor(Color.parseColor("#0F0E0B")); isFillViewport = true; addView(col)
        })
    }

    /** The block screen holds for [HOLD_MS] before Close works, so it can't be dismissed on reflex. */
    private fun showBlock() {
        val close = button("Close (3)", true) { goHome() }.apply { isEnabled = false; alpha = 0.5f }
        screen(
            text("Blocked for now", 28f, true),
            text(quote, 20f, color = Color.parseColor("#CFC6AE")),
            close,
        )
        val start = SystemClock.elapsedRealtime()
        val tick = object : Runnable {
            override fun run() {
                val left = HOLD_MS - (SystemClock.elapsedRealtime() - start)
                if (left <= 0) {
                    close.text = "Close"; close.isEnabled = true; close.alpha = 1f; unlocked = true
                    close.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                    return
                }
                close.text = "Close (${(left + 999) / 1000})"
                close.postDelayed(this, 200)
            }
        }
        close.post(tick)
    }
}
