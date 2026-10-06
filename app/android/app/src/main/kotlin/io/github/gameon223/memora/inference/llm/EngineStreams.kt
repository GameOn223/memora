package io.github.gameon223.memora.inference.llm

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.bridge.PigeonEventSink
import java.util.concurrent.ConcurrentHashMap

/**
 * Fans one event channel out to every Flutter engine that is listening.
 *
 * An event channel belongs to a single engine, while the things these events
 * come from belong to the process. The UI engine and a worker's headless
 * engine can both be up, so an event goes to every live listener and each one
 * keeps what it asked for.
 *
 * Event sinks have to be used on the platform thread, which is the other
 * thing this takes care of.
 */
class EngineStreams<T : Any> {
    private val main = Handler(Looper.getMainLooper())
    private val slots = ConcurrentHashMap<BinaryMessenger, Slot<T>>()

    /**
     * A fresh slot for [messenger] to put its sink in, replacing whatever it
     * had before. A second engine on the same messenger means the first one
     * is gone.
     */
    fun slot(messenger: BinaryMessenger): Slot<T> {
        val slot = Slot<T>()
        slots.put(messenger, slot)?.detach()
        return slot
    }

    fun release(messenger: BinaryMessenger) {
        slots.remove(messenger)?.detach()
    }

    /** False once every engine is gone. */
    fun hasListeners(): Boolean = slots.isNotEmpty()

    /** Posts [event] to the platform thread and on to every engine. */
    fun send(event: T) {
        main.post { slots.values.forEach { it.emit(event) } }
    }

    class Slot<T : Any> {
        @Volatile
        private var sink: PigeonEventSink<T>? = null

        fun hold(sink: PigeonEventSink<T>) {
            this.sink = sink
        }

        fun detach() {
            sink = null
        }

        fun emit(event: T) {
            // The engine can go away between the post and here.
            try {
                sink?.success(event)
            } catch (error: RuntimeException) {
                sink = null
            }
        }
    }
}
