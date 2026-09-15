package io.github.gameon223.memora

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/** Notification channels and the few notifications Memora posts. */
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
        val id = nextCaptureId(context)
        val text = if (count == 1) {
            context.getString(R.string.capture_saved)
        } else {
            context.getString(R.string.share_saved_many, count)
        }
        post(context, id, captureBuilder(context, text).build())
        rememberPending(context, id)
    }

    /** Replaces pending "Saved" notifications once the inbox is filed. */
    fun captureFiled(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(KEY_PENDING, emptySet()).orEmpty()
        for (id in ids) {
            val value = id.toIntOrNull() ?: continue
            post(
                context,
                value,
                captureBuilder(context, context.getString(R.string.capture_filed))
                    .setTimeoutAfter(FILED_TIMEOUT_MILLIS)
                    .build(),
            )
        }
        prefs.edit().remove(KEY_PENDING).apply()
    }

    fun captureFailed(context: Context, message: String) {
        post(
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
    }

    fun capturing(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_CAPTURE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.capturing))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
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

    @SuppressLint("MissingPermission")
    private fun post(context: Context, id: Int, notification: Notification) {
        if (!canPost(context)) return
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (ignored: SecurityException) {
            // Permission was revoked between the check and the call.
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
        val next = prefs.getInt(KEY_NEXT, FIRST_CAPTURE_ID)
        val following = if (next >= FIRST_CAPTURE_ID + CAPTURE_ID_RANGE) FIRST_CAPTURE_ID else next + 1
        prefs.edit().putInt(KEY_NEXT, following).apply()
        return next
    }

    @Synchronized
    private fun rememberPending(context: Context, id: Int) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(KEY_PENDING, emptySet()).orEmpty().toMutableSet()
        ids.add(id.toString())
        prefs.edit().putStringSet(KEY_PENDING, ids).apply()
    }

    private const val CAPTURE_ID_RANGE = 1000
    private const val FILED_TIMEOUT_MILLIS = 60_000L
}
