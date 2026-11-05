package app.reelbrain

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/** Transparent, no Flutter: queue the shared link and drop you straight back in Instagram/YouTube. */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.takeIf { it.action == Intent.ACTION_SEND }?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val link = ShareUrls.extract(text)
        if (link == null) {
            Toast.makeText(this, "Not a reel link", Toast.LENGTH_SHORT).show()
        } else {
            CounterDb.get(this).addShared(link, System.currentTimeMillis())
            Toast.makeText(this, "Saved ✓", Toast.LENGTH_SHORT).show()
        }
        finish()
    }
}
