package io.github.gameon223.memora.background

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R
import kotlin.coroutines.cancellation.CancellationException

/**
 * Runs the processing queue on a headless engine for up to nine minutes,
 * then schedules the next run if work is left.
 */
class ProcessingWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun getForegroundInfo(): ForegroundInfo =
        foregroundInfo(applicationContext, Notifications.ID_PROCESSING, R.string.processing)

    override suspend fun doWork(): Result {
        val processNow = inputData.getBoolean(KEY_PROCESS_NOW, false)
        val usesNetwork = inputData.getBoolean(KEY_USES_NETWORK, false)
        promoteToForeground(this, applicationContext, Notifications.ID_PROCESSING, R.string.processing)

        val result = try {
            HeadlessEngineRunner.run(applicationContext, BUDGET_MILLIS + CALL_GRACE_MILLIS) { api ->
                api.runQueue(BUDGET_MILLIS, processNow)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            return if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }

        val scheduler = ProcessingScheduler.get(applicationContext)
        if (processNow) {
            scheduler.afterProcessNowRun(result.processed, result.remaining, usesNetwork)
        } else {
            scheduler.afterScheduledRun(result.processed, result.remaining)
        }
        return Result.success()
    }

    companion object {
        const val KEY_PROCESS_NOW = "process_now"
        const val KEY_USES_NETWORK = "uses_network"

        /** Matches the 9 minute budget in docs/architecture.md 5.4. */
        const val BUDGET_MILLIS = 9 * 60 * 1000L

        /** Time for the item in progress to finish after the budget runs out. */
        private const val CALL_GRACE_MILLIS = 4 * 60 * 1000L
        private const val MAX_ATTEMPTS = 5
    }
}

internal fun foregroundInfo(context: Context, id: Int, textRes: Int): ForegroundInfo {
    val notification = Notifications.processing(context, textRes)
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ForegroundInfo(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
        ForegroundInfo(id, notification)
    }
}

/**
 * Asks to run as a foreground service so long runs aren't cut off. Android
 * 12+ refuses this for some background starts; the work then continues as a
 * normal job, which still fits the budget.
 */
internal suspend fun promoteToForeground(worker: CoroutineWorker, context: Context, id: Int, textRes: Int) {
    try {
        worker.setForeground(foregroundInfo(context, id, textRes))
    } catch (error: IllegalStateException) {
        // ForegroundServiceStartNotAllowedException extends this.
    } catch (error: SecurityException) {
        // Missing foreground service permission on an unusual build.
    }
}
