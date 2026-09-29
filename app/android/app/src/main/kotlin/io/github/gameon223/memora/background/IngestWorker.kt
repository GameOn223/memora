package io.github.gameon223.memora.background

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R
import kotlin.coroutines.cancellation.CancellationException

/** Files tile captures and shared images from the inbox as memories. */
class IngestWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    // Expedited work needs this on Android 11 and older.
    override suspend fun getForegroundInfo(): ForegroundInfo =
        foregroundInfo(applicationContext, Notifications.ID_INGEST, R.string.ingesting)

    // Dart confirms each filed capture, and that call updates the
    // notification, so nothing is claimed as filed before its row exists.
    override suspend fun doWork(): Result = try {
        HeadlessEngineRunner.run(applicationContext, CALL_TIMEOUT_MILLIS) { api -> api.ingestInbox() }
        Result.success()
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
    }

    companion object {
        const val UNIQUE_INGEST = "ingest"
        private const val CALL_TIMEOUT_MILLIS = 3 * 60 * 1000L
        private const val MAX_ATTEMPTS = 3

        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<IngestWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context.applicationContext)
                .enqueueUniqueWork(UNIQUE_INGEST, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
