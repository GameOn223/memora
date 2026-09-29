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

    /** Waits for the shade to close, then captures the screen. */
    fun captureAfter(delayMillis: Long) {
        handler.postDelayed({ capture() }, delayMillis)
    }

    private fun capture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Notifications.captureFailed(this, getString(R.string.capture_failed_generic))
            return
        }
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                    val bitmap = toSoftwareBitmap(screenshot)
                    if (bitmap == null) {
                        Notifications.captureFailed(
                            this@CaptureAccessibilityService,
                            getString(R.string.capture_failed_generic),
                        )
                        return
                    }
                    save(bitmap)
                }

                override fun onFailure(errorCode: Int) {
                    Notifications.captureFailed(
                        this@CaptureAccessibilityService,
                        getString(R.string.capture_failed_generic),
                    )
                }
            },
        )
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
    }
}
