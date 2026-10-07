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
        } catch (error: StoppedEarly) {
            // WorkManager stops a worker after about ten minutes, and three
            // gigabytes does not always arrive in ten minutes. The part file
            // stays where it is and the next run picks up from its length,
            // so being stopped costs the time rather than the download.
            clearOngoing()
            Result.retry()
        } catch (error: CancellationException) {
            clearOngoing()
            throw error
        } catch (error: Exception) {
            finish(error.message ?: ERROR_FAILED)
        }
    }

    /** Stopped by the system rather than by the user. */
    private class StoppedEarly : Exception()

    private suspend fun download(url: String, fileName: String, token: String): Result =
        withContext(Dispatchers.IO) {
            val dir = File(applicationContext.filesDir, ModelFileNames.IMPORTED_DIR)
            if (!dir.isDirectory && !dir.mkdirs()) return@withContext finish(ERROR_FAILED)
            val target = File(dir, fileName)
            val part = File(dir, "$fileName.part")

            // What an earlier run already fetched. Asking for the rest is
            // what makes a download survive being stopped.
            val already = if (part.isFile) part.length() else 0L
            val connection = open(url, token, from = already)
                ?: return@withContext finish(ERROR_FAILED)
            try {
                val status = connection.responseCode
                val resuming = status == HttpURLConnection.HTTP_PARTIAL
                if (!isAcceptable(status)) {
                    // A refusal is the end of it, so the part file goes too.
                    part.delete()
                    return@withContext finish(errorForStatus(status))
                }
                // The server ignored the range, so start again from nothing.
                val from = if (resuming) already else 0L
                val remaining = connection.contentLengthLong.coerceAtLeast(0L)
                val declared = if (remaining > 0) remaining + from else 0L
                if (declared > 0 && declared - from > dir.usableSpace) {
                    part.delete()
                    return@withContext finish(ERROR_NO_SPACE)
                }
                var copied = from
                connection.inputStream.use { input ->
                    java.io.FileOutputStream(part, resuming).use { output ->
                        ModelCopy.copy(input, output, declared) { soFar ->
                            if (isStopped) throw StoppedEarly()
                            copied = from + soFar
                            report(copied, declared)
                        }
                    }
                }
                if (copied <= 0L) {
                    part.delete()
                    return@withContext finish(ERROR_EMPTY)
                }
                if (declared > 0 && copied != declared) {
                    // Short, but the bytes so far are good, so keep them and
                    // let the retry ask for the rest.
                    return@withContext Result.retry()
                }
                // Checked before it is given its real name, because a file
                // sitting there under its real name is taken to be a model.
                // A gated download can hand back a page instead of weights.
                ModelBundle.check(part)?.let {
                    part.delete()
                    return@withContext finish("$ERROR_NOT_A_MODEL: $it")
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
        const val ERROR_NOT_A_MODEL = "not_a_model"

        private const val TIMEOUT_MILLIS = 30_000

        /** Redirects to follow before giving up. */
        private const val MAX_REDIRECTS = 5

        /**
         * Opens [url], following redirects by hand.
         *
         * Hugging Face answers a request for gated weights with a redirect to
         * a CDN whose own signed URL carries the authorization. Sending the
         * bearer token on there as well is what HttpURLConnection would do
         * with instanceFollowRedirects, and the CDN refuses the request for
         * having two sets of credentials. So the token goes to
         * huggingface.co only, and the redirect is followed without it.
         */
        private fun open(url: String, token: String, from: Long = 0L): HttpURLConnection? {
            var next = url
            var carryToken = true
            repeat(MAX_REDIRECTS + 1) {
                val connection = (URL(next).openConnection() as HttpURLConnection).apply {
                    if (carryToken) setRequestProperty("Authorization", "Bearer $token")
                    // Ask for the rest of a file an earlier run started.
                    if (from > 0) setRequestProperty("Range", "bytes=$from-")
                    instanceFollowRedirects = false
                    connectTimeout = TIMEOUT_MILLIS
                    readTimeout = TIMEOUT_MILLIS
                }
                val status = connection.responseCode
                if (status !in REDIRECTS) return connection
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank()) return null
                next = URL(URL(next), location).toString()
                // Only huggingface.co is told who we are.
                carryToken = URL(next).host.endsWith("huggingface.co")
            }
            return null
        }

        private val REDIRECTS = setOf(301, 302, 303, 307, 308)

        /**
         * What an HTTP status from a gated repository means. 401 is a token
         * the server would not take at all. 403 and 404 are a token it
         * accepted from an account that may not have these files, which is
         * the licence rather than the token: a gated repository answers a
         * request it will not serve with a 404 as readily as a 403.
         */
        /**
         * Whether the server is sending the file. 206 means it honoured the
         * Range header and is sending the rest of one already started;
         * treating that as a failure would restart a download from nothing.
         */
        fun isAcceptable(status: Int): Boolean =
            status == HttpURLConnection.HTTP_OK ||
                status == HttpURLConnection.HTTP_PARTIAL

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
        // A stopped worker keeps its part file so a retry can carry on. A
        // cancelled one is not coming back, and a few gigabytes is not
        // something to leave lying around.
        ModelDownloads.discardPartials(context)
    }
}
