package io.github.gameon223.memora.background

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.github.gameon223.memora.MemoraApplication
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.BackgroundFlutterApi
import io.github.gameon223.memora.bridge.BackgroundHostApi
import io.github.gameon223.memora.bridge.HostApis
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** The headless engine failed to start or to answer in time. */
class BackgroundEngineException(message: String) : Exception(message)

/**
 * Starts a headless Flutter engine on `backgroundMain`, waits until Dart has
 * built its services, makes one [BackgroundFlutterApi] call and destroys the
 * engine. See docs/architecture.md, section 10.
 */
object HeadlessEngineRunner {
    private const val ENTRYPOINT_LIBRARY = "package:memora/background_main.dart"
    private const val ENTRYPOINT_FUNCTION = "backgroundMain"
    private const val READY_TIMEOUT_MILLIS = 30_000L

    suspend fun <T> run(
        context: Context,
        callTimeoutMillis: Long,
        call: suspend (BackgroundFlutterApi) -> T,
    ): T {
        val app = MemoraApplication.from(context)
        val ready = CompletableDeferred<Unit>()
        val engine = withContext(Dispatchers.Main) { startEngine(app, ready) }
        try {
            try {
                withTimeout(READY_TIMEOUT_MILLIS) { ready.await() }
            } catch (error: TimeoutCancellationException) {
                throw BackgroundEngineException("The background entrypoint didn't signal readiness")
            }
            val api = BackgroundFlutterApi(engine.dartExecutor.binaryMessenger)
            // Channel sends have to happen on the platform thread.
            return try {
                withContext(Dispatchers.Main) {
                    withTimeout(callTimeoutMillis) { call(api) }
                }
            } catch (error: TimeoutCancellationException) {
                throw BackgroundEngineException("The background call didn't finish in time")
            }
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                BackgroundHostApi.setUp(engine.dartExecutor.binaryMessenger, null)
                HostApis.unregister(engine.dartExecutor.binaryMessenger)
                engine.destroy()
            }
        }
    }

    private fun startEngine(app: MemoraApplication, ready: CompletableDeferred<Unit>): FlutterEngine {
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
        }
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            ENTRYPOINT_LIBRARY,
            ENTRYPOINT_FUNCTION,
        )
        val engine = app.engineGroup.createAndRunEngine(app, entrypoint)
        // Dart messages are delivered on this thread after the current task,
        // so handlers registered here are in place before Dart can call them.
        val messenger = engine.dartExecutor.binaryMessenger
        HostApis.register(messenger, app, ActivityHolder.none())
        BackgroundHostApi.setUp(
            messenger,
            object : BackgroundHostApi {
                override fun backgroundReady() {
                    ready.complete(Unit)
                }
            },
        )
        return engine
    }
}
