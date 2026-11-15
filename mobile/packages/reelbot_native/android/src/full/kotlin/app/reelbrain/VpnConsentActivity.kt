package app.reelbrain

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

/** Shows Android's own "allow this app to set up a VPN" box, then starts the website filter. Has no screen of its own. */
class VpnConsentActivity : Activity() {
    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val i = VpnService.prepare(this)
        if (i == null) done() else startActivityForResult(i, 7)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resultCode == RESULT_OK) done() else finish()
    }

    private fun done() {
        LimitsService.sync(this)
        finish()
    }
}
