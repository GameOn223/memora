package io.github.gameon223.memora.inference.llm

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.bridge.ChunksStreamHandler
import io.github.gameon223.memora.bridge.LlmChunk
import io.github.gameon223.memora.bridge.PigeonEventSink
import java.util.concurrent.ConcurrentHashMap

/**
 * Carries generated text to whichever Flutter engines are listening.
 *
 * One model is shared by the whole process, while an event channel belongs to
 * a single engine. The UI engine and a worker's headless engine can both be
 * up, so chunks go to every live listener and each one keeps the requests it
 * started. Request ids are unique within the process, which is what makes
 * that safe.
 */
object LlmChunks {
    private val main = Handler(Looper.getMainLooper())
    private val streams = ConcurrentHashMap<BinaryMessenger, Stream>()

    fun register(messenger: BinaryMessenger) {
        val stream = Stream()
        ChunksStreamHandler.register(messenger, stream)
        streams.put(messenger, stream)?.detach()
    }

    fun unregister(messenger: BinaryMessenger) {
        streams.remove(messenger)?.detach()
    }

    /** False once every engine is gone, which means nobody can use a model. */
    fun hasEngines(): Boolean = streams.isNotEmpty()

    /** Posts [chunk] to the platform thread, where event sinks have to run. */
    fun send(chunk: LlmChunk) {
        main.post { streams.values.forEach { it.emit(chunk) } }
    }

    private class Stream : ChunksStreamHandler() {
        @Volatile
        private var sink: PigeonEventSink<LlmChunk>? = null

        override fun onListen(p0: Any?, sink: PigeonEventSink<LlmChunk>) {
            this.sink = sink
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }

        fun detach() {
            sink = null
        }

        fun emit(chunk: LlmChunk) {
            // The engine can go away between the post and here.
            try {
                sink?.success(chunk)
            } catch (error: RuntimeException) {
                sink = null
            }
        }
    }
}
