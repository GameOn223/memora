package io.github.gameon223.memora

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Notification channels and the few notifications Memora posts.
 *
 * With notifications turned off there is still feedback: every message
 * falls back to a toast, so a capture is never silent.
 */
object Notifications {
    const val CHANNEL_CAPTURE = "capture"
    const val CHANNEL_PROCESSING = "processing"

    const val ID_PROCESSING = 1001
    const val ID_INGEST = 1002
    const val ID_PROJECTION = 1003
    private const val ID_CAPTURE_FAILED = 1004

    private const val PREFS = "memora_capture_notifications"
    private const val KEY_PENDING = "pending_ids"
    private const val KEY_NEXT = "next_id"
    private const val FIRST_CAPTURE_ID = 2000
    private const val CAPTURE_ID_RANGE = 1000
    private const val MAX_PENDING = 20
    private const val FILED_TIMEOUT_MILLIS = 60_000L

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CAPTURE,
                context.getString(R.string.channel_capture),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = context.getString(R.string.channel_capture_description) },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_PROCESSING,
                context.getString(R.string.channel_processing),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = context.getString(R.string.channel_processing_description) },
        )
    }

    fun canPost(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** "Saved to Memora", posted as soon as a capture is on disk. */
    fun captureSaved(context: Context, count: Int = 1) {
        val text = if (count == 1) {
            context.getString(R.string.capture_saved)
        } else {
            context.getString(R.string.share_saved_many, count)
        }
        val id = nextCaptureId(context)
        if (post(context, id, captureBuilder(context, text).build())) {
            rememberPending(context, id)
        } else {
            toast(context, text)
        }
    }

    /** Replaces pending "Saved" notifications once the inbox is filed. */
    fun captureFiled(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = pendingIds(prefs)
        prefs.edit().remove(KEY_PENDING).apply()
        if (ids.isEmpty()) return
        val text = context.getString(R.string.capture_filed)
        for (id in ids) {
            post(
                context,
                id,
                captureBuilder(context, text)
                    .setTimeoutAfter(FILED_TIMEOUT_MILLIS)
                    .build(),
            )
        }
    }

    fun captureFailed(context: Context, message: String) {
        val posted = post(
            context,
            ID_CAPTURE_FAILED,
            NotificationCompat.Builder(context, CHANNEL_CAPTURE)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.capture_failed_title))
                .setContentText(message)
                .setContentIntent(openApp(context))
                .setAutoCancel(true)
                .build(),
        )
        if (!posted) toast(context, message)
    }

    /** Ongoing, quiet: the MediaProjection service has to show something. */
    fun capturing(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_PROCESSING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.capturing))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()

    fun processing(context: Context, textRes: Int = R.string.processing): Notification =
        NotificationCompat.Builder(context, CHANNEL_PROCESSING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(textRes))
            .setContentIntent(openApp(context))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()

    /** Keeps at most [MAX_PENDING] ids, oldest dropped first. */
    fun trimPending(ids: List<Int>, newest: Int, max: Int = MAX_PENDING): List<Int> {
        val kept = (ids + newest).distinct()
        return if (kept.size <= max) kept else kept.takeLast(max)
    }

    /** Capture notification ids cycle through a small range. */
    fun nextCaptureId(current: Int, first: Int = FIRST_CAPTURE_ID, range: Int = CAPTURE_ID_RANGE): Int =
        if (current < first || current >= first + range - 1) first else current + 1

    @SuppressLint("MissingPermission")
    private fun post(context: Context, id: Int, notification: Notification): Boolean {
        if (!canPost(context)) return false
        return try {
            NotificationManagerCompat.from(context).notify(id, notification)
            true
        } catch (error: SecurityException) {
            // Permission was revoked between the check and the call.
            false
        }
    }

    private fun toast(context: Context, text: CharSequence) {
        val app = context.applicationContext
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(app, text, Toast.LENGTH_SHORT).show()
        }
    }

    private fun captureBuilder(context: Context, text: String) =
        NotificationCompat.Builder(context, CHANNEL_CAPTURE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(text)
            .setContentIntent(openApp(context))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    @Synchronized
    private fun nextCaptureId(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = prefs.getInt(KEY_NEXT, FIRST_CAPTURE_ID)
        prefs.edit().putInt(KEY_NEXT, nextCaptureId(current)).apply()
        return current
    }

    @Synchronized
    private fun rememberPending(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kept = trimPending(pendingIds(prefs), id)
        prefs.edit().putString(KEY_PENDING, kept.joinToString(",")).apply()
    }

    private fun pendingIds(prefs: android.content.SharedPreferences): List<Int> =
        prefs.getString(KEY_PENDING, "").orEmpty()
            .split(',')
            .mapNotNull { it.trim().toIntOrNull() }
}
