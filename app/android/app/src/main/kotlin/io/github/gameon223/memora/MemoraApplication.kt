package io.github.gameon223.memora

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngineGroup
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

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

    companion object {
        fun from(context: Context): MemoraApplication =
            context.applicationContext as MemoraApplication
    }
}
