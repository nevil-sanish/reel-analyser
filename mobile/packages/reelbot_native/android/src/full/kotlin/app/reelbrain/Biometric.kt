package app.reelbrain

import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

/** Fingerprint or face unlock for the app lock (full build only), through Android's own prompt. The app only learns yes or no. */
object Biometric {
    fun available(ctx: Context): Boolean {
        val m = ctx.getSystemService(BiometricManager::class.java) ?: return false
        val r = if (Build.VERSION.SDK_INT >= 30) m.canAuthenticate(android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG)
        else @Suppress("DEPRECATION") m.canAuthenticate()
        return r == BiometricManager.BIOMETRIC_SUCCESS
    }

    /** Calls [done] once, on the main thread: true only when the person passed the prompt. */
    fun check(ctx: Context, reason: String, done: (Boolean) -> Unit) {
        var finished = false
        fun end(ok: Boolean) { if (!finished) { finished = true; done(ok) } }
        try {
            val prompt = BiometricPrompt.Builder(ctx)
                .setTitle("Reel Analyser + Blocker")
                .setDescription(reason)
                .setNegativeButton("Use passcode", ctx.mainExecutor) { _, _ -> end(false) }
                .build()
            prompt.authenticate(CancellationSignal(), ctx.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) = end(true)
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) = end(false)
            })
        } catch (e: Exception) {
            end(false)
        }
    }
}
