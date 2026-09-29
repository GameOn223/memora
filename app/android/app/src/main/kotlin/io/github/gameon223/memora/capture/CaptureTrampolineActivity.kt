package io.github.gameon223.memora.capture

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R

/**
 * Invisible activity the tile starts so the shade closes before a capture.
 *
 * With the accessibility service switched on, the screenshot needs no dialog.
 * Otherwise Android asks for MediaProjection consent every time.
 */
class CaptureTrampolineActivity : ComponentActivity() {
    private val projectionRequest =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            onProjectionResult(result)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return

        val service = CaptureAccessibilityService.instance
        if (service != null) {
            service.captureAfter(SHADE_CLOSE_DELAY_MILLIS)
            finish()
            return
        }
        requestProjection()
    }

    private fun requestProjection() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        if (manager == null) {
            Notifications.captureFailed(this, getString(R.string.capture_failed_generic))
            finish()
            return
        }
        try {
            projectionRequest.launch(manager.createScreenCaptureIntent())
        } catch (error: RuntimeException) {
            Notifications.captureFailed(this, getString(R.string.capture_failed_generic))
            finish()
        }
    }

    private fun onProjectionResult(result: ActivityResult) {
        val data = result.data
        if (result.resultCode != Activity.RESULT_OK || data == null) {
            Notifications.captureFailed(this, getString(R.string.capture_cancelled))
            finish()
            return
        }
        val size = screenSize()
        ContextCompat.startForegroundService(
            this,
            ProjectionCaptureService.intent(
                context = this,
                resultCode = result.resultCode,
                resultData = data,
                width = size.first,
                height = size.second,
                densityDpi = resources.displayMetrics.densityDpi,
            ),
        )
        finish()
    }

    /** The activity is a visual context, so it can measure the display. */
    private fun screenSize(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            return bounds.width() to bounds.height()
        }
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        return metrics.widthPixels to metrics.heightPixels
    }

    private companion object {
        /** Time for the Quick Settings shade to slide away. */
        const val SHADE_CLOSE_DELAY_MILLIS = 450L
    }
}
