package io.github.gameon223.memora.background

import android.content.Context
import android.content.SharedPreferences
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.github.gameon223.memora.bridge.SchedulePolicy
import io.github.gameon223.memora.bridge.SchedulerHostApi
import java.time.ZoneId
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Turns the queue policy into WorkManager requests. Android can't run work
 * at an exact time, so overnight runs are one-time requests with an initial
 * delay until the window opens.
 *
 * A running worker is never cancelled from here. The Dart side checks the
 * policy before every item, so pausing stops a run between images, and the
 * worker re-applies the stored policy when it ends.
 */
class ProcessingScheduler private constructor(context: Context) : SchedulerHostApi {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Keeps scheduling calls in order without blocking the main thread. */
    private val serial: Executor = Executors.newSingleThreadExecutor()

    private val workManager: WorkManager get() = WorkManager.getInstance(appContext)

    override fun apply(policy: SchedulePolicy) {
        store(policy)
        serial.execute { schedule(policy, fromWorker = false) }
    }

    override fun processNow(requiresUnmeteredNetwork: Boolean) {
        serial.execute { enqueueProcessNow(requiresUnmeteredNetwork, fromWorker = false) }
    }

    override fun cancelAll() {
        serial.execute {
            workManager.cancelUniqueWork(UNIQUE_PROCESSING)
            workManager.cancelUniqueWork(UNIQUE_PROCESS_NOW)
        }
    }

    /** Called by [ProcessingWorker] after a scheduled run. */
    fun afterScheduledRun(processed: Long, remaining: Boolean) {
        val policy = storedPolicy() ?: return
        val base = delayFor(policy)
        val delay = ScheduleMath.followUpDelayMillis(processed, remaining, base) ?: return
        serial.execute {
            schedule(policy.copy(hasWork = true), fromWorker = true, delayMillis = delay)
        }
    }

    /** Called by [ProcessingWorker] after a "Process now" run. */
    fun afterProcessNowRun(processed: Long, remaining: Boolean, usesNetwork: Boolean) {
        if (remaining && processed > 0) {
            serial.execute { enqueueProcessNow(usesNetwork, fromWorker = true) }
        }
    }

    /**
     * Called when a worker is stopped rather than finishing. A policy change
     * that arrived while it ran was not scheduled (see [schedule]), so the
     * stored policy is applied again here. Existing work wins, so this never
     * undoes the request that replaced the stopped one.
     */
    fun reapplyAfterStop() {
        val policy = storedPolicy() ?: return
        serial.execute {
            schedule(
                policy.copy(hasWork = true),
                fromWorker = true,
                existing = ExistingWorkPolicy.KEEP,
            )
        }
    }

    private fun schedule(
        policy: SchedulePolicy,
        fromWorker: Boolean,
        delayMillis: Long? = null,
        existing: ExistingWorkPolicy? = null,
    ) {
        // A worker that starts between this check and the enqueue below is
        // left alone on purpose: the Dart loop re-reads the policy before
        // every image, and the worker re-applies the stored policy when it
        // ends or is stopped.
        if (!fromWorker && isRunning(UNIQUE_PROCESSING)) return
        if (policy.paused || !policy.hasWork) {
            if (!fromWorker) {
                workManager.cancelUniqueWork(UNIQUE_PROCESSING)
                if (policy.paused && !isRunning(UNIQUE_PROCESS_NOW)) {
                    workManager.cancelUniqueWork(UNIQUE_PROCESS_NOW)
                }
            }
            return
        }
        val network = ScheduleMath.networkNeed(policy.immediate, policy.requiresUnmeteredNetwork)
        val constraints = Constraints.Builder()
            .setRequiresCharging(!policy.immediate)
            .setRequiredNetworkType(network.toNetworkType())
            .build()
        val request = OneTimeWorkRequestBuilder<ProcessingWorker>()
            .setInitialDelay(delayMillis ?: delayFor(policy), TimeUnit.MILLISECONDS)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .setInputData(workDataOf(ProcessingWorker.KEY_PROCESS_NOW to false))
            .addTag(TAG)
            .build()
        workManager.enqueueUniqueWork(
            UNIQUE_PROCESSING,
            existing
                ?: if (fromWorker) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    private fun enqueueProcessNow(usesNetwork: Boolean, fromWorker: Boolean) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (usesNetwork) NetworkType.CONNECTED else NetworkType.NOT_REQUIRED)
            .build()
        val request = OneTimeWorkRequestBuilder<ProcessingWorker>()
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
            .setInputData(
                workDataOf(
                    ProcessingWorker.KEY_PROCESS_NOW to true,
                    ProcessingWorker.KEY_USES_NETWORK to usesNetwork,
                ),
            )
            .addTag(TAG)
            .build()
        workManager.enqueueUniqueWork(
            UNIQUE_PROCESS_NOW,
            if (fromWorker) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }

    private fun delayFor(policy: SchedulePolicy): Long = ScheduleMath.initialDelayMillis(
        nowMillis = System.currentTimeMillis(),
        zone = ZoneId.systemDefault(),
        windowStartMinutes = policy.windowStartMinutes.toInt(),
        windowEndMinutes = policy.windowEndMinutes.toInt(),
        immediate = policy.immediate,
    )

    private fun isRunning(uniqueName: String): Boolean = try {
        workManager.getWorkInfosForUniqueWork(uniqueName).get().any { it.state == WorkInfo.State.RUNNING }
    } catch (error: ExecutionException) {
        false
    } catch (error: InterruptedException) {
        Thread.currentThread().interrupt()
        false
    }

    private fun store(policy: SchedulePolicy) {
        val editor = prefs.edit().putBoolean(KEY_STORED, true)
        for ((key, value) in SchedulePolicyCodec.toMap(policy)) {
            when (value) {
                is Boolean -> editor.putBoolean(key, value)
                is Long -> editor.putLong(key, value)
                else -> Unit
            }
        }
        editor.apply()
    }

    /** What the app last asked for, or null when it never has. */
    fun storedPolicy(): SchedulePolicy? {
        if (!prefs.getBoolean(KEY_STORED, false)) return null
        val stored = prefs.all
        return SchedulePolicyCodec.fromMap(
            SchedulePolicyCodec.keys.associateWith { stored[it] },
        )
    }

    private fun NetworkNeed.toNetworkType(): NetworkType = when (this) {
        NetworkNeed.NONE -> NetworkType.NOT_REQUIRED
        NetworkNeed.CONNECTED -> NetworkType.CONNECTED
        NetworkNeed.UNMETERED -> NetworkType.UNMETERED
    }

    companion object {
        const val UNIQUE_PROCESSING = "processing"
        const val UNIQUE_PROCESS_NOW = "processing-now"
        const val TAG = "memora-processing"

        private const val PREFS_NAME = "memora_schedule"
        private const val KEY_STORED = "stored"

        @Volatile
        private var instance: ProcessingScheduler? = null

        fun get(context: Context): ProcessingScheduler =
            instance ?: synchronized(this) {
                instance ?: ProcessingScheduler(context).also { instance = it }
            }
    }
}
