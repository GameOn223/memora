package io.github.gameon223.memora.bridge

import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The activity behind the UI engine, if there is one. Host APIs that need an
 * activity (permission prompts, pickers, the save dialog) ask for it here.
 * The headless engine used by workers has none, and those calls fail with a
 * `no_activity` error instead of crashing.
 */
class ActivityHolder {
    @Volatile
    private var ref: WeakReference<ComponentActivity>? = null

    fun attach(activity: ComponentActivity) {
        ref = WeakReference(activity)
    }

    fun detach() {
        ref = null
    }

    val current: ComponentActivity?
        get() = ref?.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    fun require(): ComponentActivity =
        current ?: throw FlutterError(
            "no_activity",
            "This call needs the Memora screen to be open.",
            null,
        )

    companion object {
        /** Holder for engines that never have an activity. */
        fun none(): ActivityHolder = ActivityHolder()
    }
}

private val requestCounter = AtomicInteger()

/**
 * Launches [contract] and suspends until the result arrives. Registers a
 * one-off launcher so the input (for example a picker limit) can vary per
 * call. Must be called on the main thread.
 */
suspend fun <I, O> ComponentActivity.awaitActivityResult(
    contract: ActivityResultContract<I, O>,
    input: I,
): O = suspendCancellableCoroutine { continuation ->
    val key = "memora.request.${requestCounter.incrementAndGet()}"
    lateinit var launcher: ActivityResultLauncher<I>
    launcher = activityResultRegistry.register(key, contract) { result ->
        launcher.unregister()
        if (continuation.isActive) continuation.resume(result)
    }
    continuation.invokeOnCancellation { launcher.unregister() }
    try {
        launcher.launch(input)
    } catch (error: RuntimeException) {
        launcher.unregister()
        throw error
    }
}
