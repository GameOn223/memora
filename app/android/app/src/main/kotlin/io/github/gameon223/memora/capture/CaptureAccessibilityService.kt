package io.github.gameon223.memora.capture

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import io.github.gameon223.memora.MemoraApplication
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R
import kotlinx.coroutines.launch

/**
 * Takes one screenshot when the Memora tile is tapped, and nothing else.
 *
 * The service declares no event types and can't retrieve window content, so
 * Android never sends it anything about what's on screen. See
 * res/xml/accessibility_capture.xml.
 */
class CaptureAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No event types are requested, so this never runs.
    }

    override fun onInterrupt() {
        // Nothing to interrupt: the service only reacts to the tile.
    }

    /**
     * Waits for the shade to close, then captures the screen. [onResult] is
     * false when this path can't deliver a screenshot, for example when the
     * system is still rate limiting the previous one, so the caller can fall
     * back to MediaProjection.
     */
    fun captureAfter(delayMillis: Long, onResult: (Boolean) -> Unit) {
        if (!canScreenshot) {
            onResult(false)
            return
        }
        handler.postDelayed({ capture(onResult) }, delayMillis)
    }

    private fun capture(onResult: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            onResult(false)
            return
        }
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        val bitmap = toSoftwareBitmap(screenshot)
                        if (bitmap == null) {
                            onResult(false)
                            return
                        }
                        onResult(true)
                        save(bitmap)
                    }

                    override fun onFailure(errorCode: Int) {
                        // Usually the one-per-second limit after a double tap.
                        onResult(false)
                    }
                },
            )
        } catch (error: RuntimeException) {
            onResult(false)
        }
    }

    private fun toSoftwareBitmap(screenshot: AccessibilityService.ScreenshotResult): Bitmap? = try {
        val hardware = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
        val software = hardware?.copy(Bitmap.Config.ARGB_8888, false)
        hardware?.recycle()
        software
    } catch (error: IllegalArgumentException) {
        null
    } finally {
        screenshot.hardwareBuffer.close()
    }

    private fun save(bitmap: Bitmap) {
        val app = MemoraApplication.from(this)
        app.appScope.launch {
            try {
                Inbox.writeBitmap(
                    context = applicationContext,
                    bitmap = bitmap,
                    source = CaptureSidecar.SOURCE_TILE,
                    capturedAtMillis = System.currentTimeMillis(),
                )
                Inbox.finishCapture(applicationContext, 1)
            } catch (error: java.io.IOException) {
                Notifications.captureFailed(
                    applicationContext,
                    applicationContext.getString(R.string.capture_failed_generic),
                )
            } finally {
                bitmap.recycle()
            }
        }
    }

    companion object {
        @Volatile
        var instance: CaptureAccessibilityService? = null
            private set

        /** Screenshots through accessibility need Android 11. */
        val canScreenshot: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        /** The service that can take a screenshot right now, if any. */
        fun screenshotService(): CaptureAccessibilityService? =
            if (canScreenshot) instance else null
    }
}
