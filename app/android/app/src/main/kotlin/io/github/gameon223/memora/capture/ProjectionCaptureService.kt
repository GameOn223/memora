package io.github.gameon223.memora.capture

import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import androidx.core.content.IntentCompat
import io.github.gameon223.memora.MemoraApplication
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R
import io.github.gameon223.memora.gallery.ImageMath
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.launch

/**
 * Grabs a single frame with MediaProjection and stops. Used when the
 * accessibility capture isn't switched on, which means Android shows a
 * consent dialog for every capture.
 */
class ProjectionCaptureService : Service() {
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private val finished = AtomicBoolean(false)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            ?: Activity.RESULT_CANCELED
        val data = intent?.let { IntentCompat.getParcelableExtra(it, EXTRA_RESULT_DATA, Intent::class.java) }
        val width = intent?.getIntExtra(EXTRA_WIDTH, 0) ?: 0
        val height = intent?.getIntExtra(EXTRA_HEIGHT, 0) ?: 0
        val dpi = intent?.getIntExtra(EXTRA_DPI, 0) ?: 0
        if (resultCode != Activity.RESULT_OK || data == null || width <= 0 || height <= 0) {
            fail()
            return START_NOT_STICKY
        }
        try {
            start(resultCode, data, width, height, if (dpi > 0) dpi else DEFAULT_DPI)
        } catch (error: RuntimeException) {
            fail()
        }
        return START_NOT_STICKY
    }

    private fun start(resultCode: Int, data: Intent, width: Int, height: Int, dpi: Int) {
        val manager = getSystemService(MediaProjectionManager::class.java) ?: run {
            fail()
            return
        }
        val worker = HandlerThread("memora-capture").apply { start() }
        thread = worker
        val workerHandler = Handler(worker.looper)
        handler = workerHandler

        val media = manager.getMediaProjection(resultCode, data)
        if (media == null) {
            fail()
            return
        }
        projection = media
        media.registerCallback(
            object : MediaProjection.Callback() {
                override fun onStop() {
                    if (finished.compareAndSet(false, true)) stopEverything()
                }
            },
            workerHandler,
        )

        val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, FRAME_BUFFERS)
        reader = imageReader
        imageReader.setOnImageAvailableListener({ ready ->
            // Give the screen a moment to settle after the consent dialog.
            workerHandler.postDelayed({ grabFrame(ready) }, SETTLE_DELAY_MILLIS)
        }, workerHandler)

        virtualDisplay = media.createVirtualDisplay(
            "memora-capture",
            width,
            height,
            dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader.surface,
            null,
            workerHandler,
        )

        workerHandler.postDelayed({
            if (!finished.get()) fail()
        }, CAPTURE_TIMEOUT_MILLIS)
    }

    private fun grabFrame(source: ImageReader) {
        if (!finished.compareAndSet(false, true)) return
        val bitmap = try {
            source.acquireLatestImage()?.use { image ->
                val plane = image.planes[0]
                val padded = ImageMath.paddedBitmapWidth(image.width, plane.rowStride, plane.pixelStride)
                val full = Bitmap.createBitmap(padded, image.height, Bitmap.Config.ARGB_8888)
                full.copyPixelsFromBuffer(plane.buffer)
                if (padded == image.width) {
                    full
                } else {
                    Bitmap.createBitmap(full, 0, 0, image.width, image.height).also { full.recycle() }
                }
            }
        } catch (error: IllegalStateException) {
            null
        } catch (error: IllegalArgumentException) {
            null
        }
        stopEverything()
        if (bitmap == null) {
            Notifications.captureFailed(this, getString(R.string.capture_failed_generic))
            stopSelfCompat()
            return
        }
        MemoraApplication.from(this).appScope.launch {
            try {
                Inbox.writeBitmap(
                    context = applicationContext,
                    bitmap = bitmap,
                    source = CaptureSidecar.SOURCE_TILE,
                    capturedAtMillis = System.currentTimeMillis(),
                )
                Inbox.finishCapture(applicationContext, 1)
            } catch (error: IOException) {
                Notifications.captureFailed(
                    applicationContext,
                    applicationContext.getString(R.string.capture_failed_generic),
                )
            } finally {
                bitmap.recycle()
            }
        }
        stopSelfCompat()
    }

    private fun fail() {
        if (!finished.compareAndSet(false, true)) return
        stopEverything()
        Notifications.captureFailed(this, getString(R.string.capture_cancelled))
        stopSelfCompat()
    }

    private fun stopEverything() {
        virtualDisplay?.release()
        virtualDisplay = null
        reader?.close()
        reader = null
        projection?.stop()
        projection = null
        thread?.quitSafely()
        thread = null
    }

    private fun stopSelfCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun startForegroundCompat() {
        val notification = Notifications.capturing(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                Notifications.ID_PROJECTION,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(Notifications.ID_PROJECTION, notification)
        }
    }

    override fun onDestroy() {
        stopEverything()
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_RESULT_CODE = "result_code"
        private const val EXTRA_RESULT_DATA = "result_data"
        private const val EXTRA_WIDTH = "width"
        private const val EXTRA_HEIGHT = "height"
        private const val EXTRA_DPI = "dpi"
        private const val FRAME_BUFFERS = 2
        private const val DEFAULT_DPI = 320
        private const val SETTLE_DELAY_MILLIS = 300L
        private const val CAPTURE_TIMEOUT_MILLIS = 6000L

        fun intent(
            context: Context,
            resultCode: Int,
            resultData: Intent,
            width: Int,
            height: Int,
            densityDpi: Int,
        ): Intent = Intent(context, ProjectionCaptureService::class.java)
            .putExtra(EXTRA_RESULT_CODE, resultCode)
            .putExtra(EXTRA_RESULT_DATA, resultData)
            .putExtra(EXTRA_WIDTH, width)
            .putExtra(EXTRA_HEIGHT, height)
            .putExtra(EXTRA_DPI, densityDpi)
    }
}
