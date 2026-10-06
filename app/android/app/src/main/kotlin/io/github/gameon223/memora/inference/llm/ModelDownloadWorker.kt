package io.github.gameon223.memora.inference.llm

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.bridge.ModelDownloadEvent
import io.github.gameon223.memora.secure.KeystoreSecretStore
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Downloads a model file with Memora in the background.
 *
 * A model runs from half a gigabyte to three, so this takes minutes and
 * nobody is going to sit and watch it. Done in the app's own process it would
 * be killed the moment Android wanted the memory. As a foreground worker it
 * survives, and the notification it has to show anyway is the thing that says
 * how far it has got.
 *
 * The access token is not in [inputData]. It is read from the secret store
 * here, so it never lands in WorkManager's database, which is a plain file
 * on disk that outlives the download.
 */
class ModelDownloadWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    private val modelId = inputData.getString(KEY_MODEL_ID).orEmpty()
    private val displayName = inputData.getString(KEY_DISPLAY_NAME).orEmpty()

    override suspend fun getForegroundInfo(): ForegroundInfo = info(0, 0)

    override suspend fun doWork(): Result {
        val url = inputData.getString(KEY_URL)
        val fileName = inputData.getString(KEY_FILE_NAME)
        if (modelId.isEmpty() || url == null || fileName == null) {
            return Result.failure()
        }
        val token = KeystoreSecretStore.get(applicationContext).read(TOKEN_KEY)
        if (token.isNullOrEmpty()) return finish(ERROR_NO_TOKEN)

        setForegroundQuietly(info(0, 0))
        return try {
            download(url, fileName, token)
        } catch (error: CancellationException) {
            // Cancelled, by the notification action or by a new download.
            // The part file is already gone; say nothing more.
            clearOngoing()
            throw error
        } catch (error: Exception) {
            finish(error.message ?: ERROR_FAILED)
        }
    }

    private suspend fun download(url: String, fileName: String, token: String): Result =
        withContext(Dispatchers.IO) {
            val dir = File(applicationContext.filesDir, ModelFileNames.IMPORTED_DIR)
            if (!dir.isDirectory && !dir.mkdirs()) return@withContext finish(ERROR_FAILED)
            val target = File(dir, fileName)
            val part = File(dir, "$fileName.part")

            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                setRequestProperty("Authorization", "Bearer $token")
                instanceFollowRedirects = true
                connectTimeout = TIMEOUT_MILLIS
                readTimeout = TIMEOUT_MILLIS
            }
            try {
                val status = connection.responseCode
                if (status != HttpURLConnection.HTTP_OK) {
                    return@withContext finish(errorForStatus(status))
                }
                val declared = connection.contentLengthLong.coerceAtLeast(0L)
                if (declared > 0 && declared > dir.usableSpace) {
                    return@withContext finish(ERROR_NO_SPACE)
                }
                var copied = 0L
                connection.inputStream.use { input ->
                    part.outputStream().use { output ->
                        copied = ModelCopy.copy(input, output, declared) { soFar ->
                            if (isStopped) throw CancellationException("stopped")
                            report(soFar, declared)
                        }
                    }
                }
                if (copied <= 0L) return@withContext finish(ERROR_EMPTY)
                if (declared > 0 && copied != declared) {
                    return@withContext finish(ERROR_SHORT)
                }
                if (!part.renameTo(target)) return@withContext finish(ERROR_FAILED)
                ModelDownloads.send(
                    ModelDownloadEvent(
                        modelId = modelId,
                        copiedBytes = copied,
                        totalBytes = if (declared > 0) declared else copied,
                        done = true,
                    ),
                )
                clearOngoing()
                Notifications.downloadEnded(applicationContext, displayName, failed = false)
                Result.success()
            } finally {
                connection.disconnect()
                if (part.exists()) part.delete()
            }
        }

    /**
     * Posts progress to whoever is listening, and to the notification.
     *
     * Not suspending: the copy reports from a plain callback. The worker is
     * already in the foreground by now, so the notification is refreshed in
     * place rather than through setForeground.
     */
    private fun report(copied: Long, total: Long) {
        ModelDownloads.send(
            ModelDownloadEvent(
                modelId = modelId,
                copiedBytes = copied,
                totalBytes = total,
                done = false,
            ),
        )
        Notifications.postDownloading(
            applicationContext,
            displayName,
            copied,
            total,
            cancelIntent(),
        )
    }

    /** Ends the download badly: one event, one notification, no file. */
    private fun finish(error: String): Result {
        ModelDownloads.send(
            ModelDownloadEvent(
                modelId = modelId,
                copiedBytes = 0,
                totalBytes = 0,
                done = true,
                error = error,
            ),
        )
        clearOngoing()
        Notifications.downloadEnded(applicationContext, displayName, failed = true)
        // Not a retry. Every one of these needs the user to settle something.
        return Result.failure()
    }

    private fun info(copied: Long, total: Long): ForegroundInfo {
        val notification = Notifications.downloading(
            applicationContext,
            displayName,
            copied,
            total,
            cancelIntent(),
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                Notifications.ID_DOWNLOAD,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(Notifications.ID_DOWNLOAD, notification)
        }
    }

    private fun cancelIntent(): PendingIntent = PendingIntent.getBroadcast(
        applicationContext,
        0,
        Intent(applicationContext, ModelDownloadCancelReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private suspend fun setForegroundQuietly(info: ForegroundInfo) {
        try {
            setForeground(info)
        } catch (error: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException extends this. The
            // download carries on as an ordinary job.
        } catch (error: SecurityException) {
            // Missing foreground service permission on an unusual build.
        }
    }

    private fun clearOngoing() {
        NotificationManagerCompat.from(applicationContext).cancel(Notifications.ID_DOWNLOAD)
    }

    companion object {
        const val KEY_MODEL_ID = "modelId"
        const val KEY_URL = "url"
        const val KEY_FILE_NAME = "fileName"
        const val KEY_DISPLAY_NAME = "displayName"

        /** Secret store key holding the Hugging Face read token. */
        const val TOKEN_KEY = "huggingface.token"

        const val ERROR_NO_TOKEN = "no_token"
        const val ERROR_UNAUTHORIZED = "unauthorized"
        const val ERROR_FORBIDDEN = "forbidden"
        const val ERROR_NO_SPACE = "no_space"
        const val ERROR_SHORT = "short_download"
        const val ERROR_EMPTY = "empty_download"
        const val ERROR_FAILED = "download_failed"

        private const val TIMEOUT_MILLIS = 30_000

        /**
         * What an HTTP status from a gated repository means. 401 is a token
         * the server would not take at all. 403 and 404 are a token it
         * accepted from an account that may not have these files, which is
         * the licence rather than the token: a gated repository answers a
         * request it will not serve with a 404 as readily as a 403.
         */
        fun errorForStatus(status: Int): String = when (status) {
            HttpURLConnection.HTTP_UNAUTHORIZED -> ERROR_UNAUTHORIZED
            HttpURLConnection.HTTP_FORBIDDEN, HttpURLConnection.HTTP_NOT_FOUND ->
                ERROR_FORBIDDEN
            else -> ERROR_FAILED
        }
    }
}

/** The Cancel action on the download notification. */
class ModelDownloadCancelReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ModelDownloads.cancelAll(context)
    }
}
