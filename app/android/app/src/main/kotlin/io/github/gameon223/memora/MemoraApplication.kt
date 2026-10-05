package io.github.gameon223.memora

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngineGroup
import io.github.gameon223.memora.inference.OnnxEmbedder
import io.github.gameon223.memora.inference.llm.GemmaRuntime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MemoraApplication : Application() {
    /**
     * Shared by the UI engine's siblings. Background workers create their
     * headless engines from here so they reuse the loaded Dart snapshot.
     * Must first be touched on the main thread.
     */
    val engineGroup: FlutterEngineGroup by lazy { FlutterEngineGroup(this) }

    /** For work that must finish even if the screen that started it closes. */
    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        // WorkManager uses its default initializer from the merged manifest.
        Notifications.createChannels(this)
    }

    // Android 14 stopped sending the TRIM_MEMORY_RUNNING_* levels and
    // deprecated their constants. They still arrive on older releases, and
    // the threshold also covers the background levels that are still sent.
    @Suppress("DEPRECATION")
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // A generative model holds hundreds of megabytes, sometimes gigabytes,
        // outside the Java heap. It goes first, while Memora is still in the
        // foreground, because the alternative is the kernel killing the
        // process. A cancelled generation reports itself as done.
        if (level >= TRIM_MEMORY_RUNNING_LOW) {
            appScope.launch { GemmaRuntime.unloadQuietly() }
        }
        // The embedding session holds tens of megabytes. It loads again from
        // the model file the next time something needs a vector.
        if (level >= TRIM_MEMORY_BACKGROUND) {
            appScope.launch { OnnxEmbedder.unload() }
        }
    }

    companion object {
        fun from(context: Context): MemoraApplication =
            context.applicationContext as MemoraApplication
    }
}
