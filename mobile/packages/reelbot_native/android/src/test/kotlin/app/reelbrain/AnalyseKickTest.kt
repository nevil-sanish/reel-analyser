package app.reelbrain

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.testing.WorkManagerTestInitHelper
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The kick reaches the workmanager plugin by name; where that plugin is absent (these tests) it must do nothing, not crash. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnalyseKickTest {
    @Test fun enqueueNeverThrows() {
        val ctx: Context = ApplicationProvider.getApplicationContext()
        WorkManagerTestInitHelper.initializeTestWorkManager(ctx)
        AnalyseKick.enqueue(ctx)
        AnalyseKick.enqueue(ctx)
    }
}
