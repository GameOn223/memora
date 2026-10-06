package io.github.gameon223.memora.inference.llm

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.bridge.DownloadEventsStreamHandler
import io.github.gameon223.memora.bridge.ModelDownloadEvent
import io.github.gameon223.memora.bridge.PigeonEventSink

/**
 * Starts, stops and reports on model downloads.
 *
 * One at a time. These files are measured in gigabytes and two at once would
 * compete for the same bandwidth and the same disk, so a new download
 * replaces whatever was running under the same unique work name.
 */
object ModelDownloads {
    /** Unique work name. Also what makes a second download replace the first. */
    const val WORK_NAME = "memora-model-download"

    private val streams = EngineStreams<ModelDownloadEvent>()

    fun register(messenger: BinaryMessenger) {
        DownloadEventsStreamHandler.register(messenger, Stream(streams.slot(messenger)))
    }

    fun unregister(messenger: BinaryMessenger) {
        streams.release(messenger)
    }

    /** Posts an event to every engine that is listening, if any is. */
    fun send(event: ModelDownloadEvent) {
        streams.send(event)
    }

    fun start(
        context: Context,
        modelId: String,
        url: String,
        fileName: String,
        displayName: String,
    ) {
        val request = OneTimeWorkRequestBuilder<ModelDownloadWorker>()
            .setInputData(
                Data.Builder()
                    .putString(ModelDownloadWorker.KEY_MODEL_ID, modelId)
                    .putString(ModelDownloadWorker.KEY_URL, url)
                    .putString(ModelDownloadWorker.KEY_FILE_NAME, fileName)
                    .putString(ModelDownloadWorker.KEY_DISPLAY_NAME, displayName)
                    .build(),
            )
            // The tag is how active() names the model after a restart.
            .addTag(TAG_PREFIX + modelId)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancelAll(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    /**
     * The model downloading right now, read from WorkManager rather than
     * from memory, because the screen asking may have been built after the
     * process was restarted under the download.
     */
    fun active(context: Context): String? {
        val infos = try {
            WorkManager.getInstance(context).getWorkInfosForUniqueWork(WORK_NAME).get()
        } catch (error: Exception) {
            return null
        }
        val running = infos.firstOrNull { !it.state.isFinished } ?: return null
        return running.progress.getString(ModelDownloadWorker.KEY_MODEL_ID)
            ?: running.tags.firstNotNullOfOrNull { tag ->
                tag.takeIf { it.startsWith(TAG_PREFIX) }?.removePrefix(TAG_PREFIX)
            }
    }

    /** Whether anything is downloading, for callers that need only that. */
    fun isActive(context: Context): Boolean = try {
        WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(WORK_NAME)
            .get()
            .any { it.state == WorkInfo.State.RUNNING || it.state == WorkInfo.State.ENQUEUED }
    } catch (error: Exception) {
        false
    }

    private const val TAG_PREFIX = "model:"

    private class Stream(
        private val slot: EngineStreams.Slot<ModelDownloadEvent>,
    ) : DownloadEventsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<ModelDownloadEvent>) {
            slot.hold(sink)
        }

        override fun onCancel(p0: Any?) {
            slot.detach()
        }
    }
}
