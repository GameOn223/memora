package io.github.gameon223.memora.inference.llm

import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.bridge.ChunksStreamHandler
import io.github.gameon223.memora.bridge.ImportProgressStreamHandler
import io.github.gameon223.memora.bridge.LlmChunk
import io.github.gameon223.memora.bridge.ModelImportProgress
import io.github.gameon223.memora.bridge.PigeonEventSink

/**
 * Carries generated text to whichever Flutter engines are listening.
 *
 * One model is shared by the whole process, so chunks go to every live
 * listener and each one keeps the requests it started. Request ids are unique
 * within the process, which is what makes that safe.
 */
object LlmChunks {
    private val streams = EngineStreams<LlmChunk>()

    fun register(messenger: BinaryMessenger) {
        ChunksStreamHandler.register(messenger, Stream(streams.slot(messenger)))
    }

    fun unregister(messenger: BinaryMessenger) {
        streams.release(messenger)
    }

    /** False once every engine is gone, which means nobody can use a model. */
    fun hasEngines(): Boolean = streams.hasListeners()

    /** Posts [chunk] to the platform thread, where event sinks have to run. */
    fun send(chunk: LlmChunk) {
        streams.send(chunk)
    }

    private class Stream(
        private val slot: EngineStreams.Slot<LlmChunk>,
    ) : ChunksStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<LlmChunk>) {
            slot.hold(sink)
        }

        override fun onCancel(p0: Any?) {
            slot.detach()
        }
    }
}

/**
 * Carries copy progress out of a model import.
 *
 * The picker belongs to the UI engine, but progress goes out the same way
 * chunks do, and an engine that started no import simply has nothing to
 * match it to.
 */
object ModelImportEvents {
    private val streams = EngineStreams<ModelImportProgress>()

    fun register(messenger: BinaryMessenger) {
        ImportProgressStreamHandler.register(messenger, Stream(streams.slot(messenger)))
    }

    fun unregister(messenger: BinaryMessenger) {
        streams.release(messenger)
    }

    fun send(progress: ModelImportProgress) {
        streams.send(progress)
    }

    private class Stream(
        private val slot: EngineStreams.Slot<ModelImportProgress>,
    ) : ImportProgressStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<ModelImportProgress>) {
            slot.hold(sink)
        }

        override fun onCancel(p0: Any?) {
            slot.detach()
        }
    }
}
