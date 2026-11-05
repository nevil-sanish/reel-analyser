package app.reelbrain

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/** A draggable bubble shown while you're on Reels/Shorts; tap it for [Today: N] and [Save] (IMPLEMENTATION §6). */
class OverlayBubble(private val ctx: Context, private val onSave: () -> Unit) {
    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val dp = ctx.resources.displayMetrics.density
    private var root: LinearLayout? = null
    private lateinit var chip: TextView
    private lateinit var panel: LinearLayout
    private lateinit var today: TextView
    private val lp = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.START; x = (12 * dp).toInt(); y = (220 * dp).toInt() }

    val shown get() = root != null

    fun show(count: Long) {
        if (root == null) build()
        chip.text = count.toString()
        today.text = "Today: $count"
    }

    fun hide() {
        root?.let(wm::removeView)
        root = null
    }

    private fun round(color: Int, radius: Float) = GradientDrawable().apply { setColor(color); cornerRadius = radius * dp }

    private fun build() {
        val pad = (10 * dp).toInt()
        chip = TextView(ctx).apply {
            setTextColor(Color.WHITE); textSize = 15f; gravity = Gravity.CENTER
            minWidth = (44 * dp).toInt(); minHeight = (44 * dp).toInt()
            background = round(0xCC5E35B1.toInt(), 22f)
        }
        today = TextView(ctx).apply { setTextColor(Color.WHITE); textSize = 14f; setPadding(pad, 0, pad, 0) }
        val save = Button(ctx).apply {
            text = "Save"
            setOnClickListener { panel.visibility = View.GONE; onSave() }
        }
        panel = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; visibility = View.GONE
            background = round(0xCC212121.toInt(), 12f); setPadding(pad / 2, 0, pad / 2, 0)
            addView(today); addView(save)
        }
        root = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            addView(chip); addView(panel)
        }
        chip.setOnTouchListener(Drag())
        wm.addView(root, lp)
    }

    /** Drag moves the bubble; a tap without moving toggles the panel. */
    private inner class Drag : View.OnTouchListener {
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var moved = false

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; moved = false }
                MotionEvent.ACTION_MOVE -> {
                    if (abs(e.rawX - downX) + abs(e.rawY - downY) > 12 * dp) moved = true
                    if (moved) {
                        lp.x = startX + (e.rawX - downX).toInt(); lp.y = startY + (e.rawY - downY).toInt()
                        root?.let { wm.updateViewLayout(it, lp) }
                    }
                }
                MotionEvent.ACTION_UP -> if (!moved) panel.visibility = if (panel.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            }
            return true
        }
    }
}
