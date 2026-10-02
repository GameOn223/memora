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
 * Runs the processing queue on a headless engine, then schedules the next
 * run if work is left.
 *
 * The budget plus the grace has to fit inside WorkManager's ten minute
 * ceiling, with room for the engine to start, so being stopped mid-image
 * stays the exception.
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
        val scheduler = ProcessingScheduler.get(applicationContext)

        val result = try {
            HeadlessEngineRunner.run(applicationContext, BUDGET_MILLIS + CALL_GRACE_MILLIS) { api ->
                api.runQueue(BUDGET_MILLIS, processNow)
            }
        } catch (error: CancellationException) {
            // Stopped rather than finished. A policy change made while this
            // ran was not scheduled, and WorkManager keeps no follow-up for
            // a stopped worker, so ask for one now.
            scheduler.reapplyAfterStop()
            throw error
        } catch (error: Exception) {
            return afterFailure(scheduler, processNow)
        }

        if (processNow) {
            scheduler.afterProcessNowRun(result.processed, result.remaining, usesNetwork)
        } else {
            scheduler.afterScheduledRun(result.processed, result.remaining)
        }
        return Result.success()
    }

    /**
     * A retry ignores the initial delay, so an overnight run that failed
     * could come back at noon. Failures are rescheduled through the stored
     * policy instead, which re-derives the window and the idle backoff.
     */
    private fun afterFailure(scheduler: ProcessingScheduler, processNow: Boolean): Result {
        if (processNow && runAttemptCount < MAX_ATTEMPTS) return Result.retry()
        scheduler.afterScheduledRun(processed = 0, remaining = true)
        return Result.success()
    }

    companion object {
        const val KEY_PROCESS_NOW = "process_now"
        const val KEY_USES_NETWORK = "uses_network"

        /**
         * Seven minutes of work, a minute for the image in progress to
         * finish, and the rest of WorkManager's ten for the engine.
         */
        const val BUDGET_MILLIS = 7 * 60 * 1000L
        private const val CALL_GRACE_MILLIS = 60 * 1000L
        private const val MAX_ATTEMPTS = 3
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
