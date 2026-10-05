package io.github.gameon223.memora.inference.llm

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
import io.github.gameon223.memora.bridge.DeviceMemory
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.LlmChunk
import io.github.gameon223.memora.files.SafePaths
import io.github.gameon223.memora.gallery.ImageMath
import java.io.File
import java.util.concurrent.Executor
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Runs a Gemma model file through MediaPipe LLM Inference.
 *
 * One model is loaded for the whole process, the way the embedding session
 * is, because the weights are measured in hundreds of megabytes and the UI
 * engine and a worker's headless engine share the same address space. A
 * mutex serializes loading, generating and unloading: the session takes one
 * turn at a time and a second one would corrupt it.
 *
 * Each generation gets a fresh session, so one answer never inherits
 * another's context. The engine stays up between turns, which is where the
 * expensive work is.
 *
 * MediaPipe marks these classes deprecated: the task is in maintenance and
 * Google points new work at LiteRT-LM. It still ships, still runs Gemma 3
 * and Gemma 3n, and has an Android artifact to depend on, which LiteRT-LM
 * did not when this was written. Everything MediaPipe-specific is behind this
 * one file, so swapping the runtime later is a local change.
 */
@Suppress("DEPRECATION")
object GemmaRuntime {
    /** Sampling. Fixed here because the bridge doesn't carry it. */
    private const val TOP_K = 40
    private const val TOP_P = 0.95f

    /** Low enough for pulling facts out of a screenshot, not rigid. */
    private const val TEMPERATURE = 0.4f

    /** What MediaPipe allows per session. */
    private const val MAX_IMAGES = 10

    /** Gemma's vision tower works at 768 pixels. Anything larger is waste. */
    private const val IMAGE_MAX_EDGE = 768

    /** How long unload waits for a cancelled generation to let go. */
    private const val RELEASE_TIMEOUT_MILLIS = 15_000L

    private val mutex = Mutex()
    private val turns = GenerationTurns()

    /** For releases asked for by callers that can't suspend. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile
    private var engine: LlmInference? = null

    @Volatile
    private var session: LlmInferenceSession? = null

    // Written under the mutex, read from the platform thread when a request
    // is validated, so every field has to be visible across threads.
    @Volatile
    private var loadedPath: String? = null

    @Volatile
    private var loadedVision = false

    @Volatile
    private var loadedMaxTokens = 0

    /** A hint for the UI. Generation reads the engine under the mutex. */
    fun isLoaded(): Boolean = engine != null

    /** The relative path the loaded model came from, for the settings screen. */
    fun loadedModelPath(): String? = loadedPath

    fun deviceMemory(context: Context): DeviceMemory {
        val manager = context.getSystemService(ActivityManager::class.java)
            ?: throw FlutterError("no_memory_info", "Couldn't read the device's memory.", null)
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return DeviceMemory(
            totalBytes = info.totalMem,
            availableBytes = info.availMem,
            lowRamDevice = manager.isLowRamDevice,
        )
    }

    suspend fun load(
        context: Context,
        relativeModelPath: String,
        vision: Boolean,
        maxTokens: Long,
    ) {
        val file = modelFile(context, relativeModelPath)
        val tokens = maxTokens.toInt()
        if (tokens <= 0) {
            throw FlutterError("invalid_max_tokens", "maxTokens has to be positive.", null)
        }
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val sameModel = loadedPath == relativeModelPath &&
                    loadedVision == vision &&
                    loadedMaxTokens == tokens
                if (sameModel && engine != null) return@withLock

                // Free the old model before measuring, so swapping models is
                // not refused over memory the previous one is still holding.
                closeLocked()
                val memory = deviceMemory(context)
                val headroom = MemoryHeadroom.decide(
                    modelBytes = file.length(),
                    availableBytes = memory.availableBytes,
                    totalBytes = memory.totalBytes,
                    lowRamDevice = memory.lowRamDevice,
                )
                if (headroom is Headroom.Refused) {
                    throw FlutterError(headroom.code, headroom.message, null)
                }

                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(file.absolutePath)
                    .setMaxTokens(tokens)
                    .setMaxTopK(TOP_K)
                    .setMaxNumImages(if (vision) MAX_IMAGES else 0)
                    .build()
                try {
                    engine = LlmInference.createFromOptions(context, options)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    closeLocked()
                    throw FlutterError("model_failed", loadFailureMessage(error), null)
                }
                loadedPath = relativeModelPath
                loadedVision = vision
                loadedMaxTokens = tokens
            }
        }
    }

    /**
     * Frees the model. Cancels a running generation first and waits for it to
     * let go, so the native session is never closed under a live turn.
     */
    suspend fun unload() {
        turns.runningId?.let { cancel(it) }
        val released = withTimeoutOrNull(RELEASE_TIMEOUT_MILLIS) {
            withContext(Dispatchers.IO) { mutex.withLock { closeLocked() } }
            true
        }
        if (released == null) {
            throw FlutterError(
                "busy",
                "A generation is still finishing. Try unloading again in a moment.",
                null,
            )
        }
    }

    /**
     * Frees the model from a caller that can't suspend, such as a Flutter
     * engine being torn down.
     */
    fun requestUnload() {
        if (engine == null) return
        scope.launch { unloadQuietly() }
    }

    /** Frees the model without reporting anything. Used on memory pressure. */
    suspend fun unloadQuietly() {
        try {
            unload()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            // Nothing asked for this, so there is nobody to tell.
        }
    }

    /**
     * Claims the single generation turn and returns its request id. Called
     * before the work is handed off, so a second request is refused while the
     * caller is still on the channel.
     */
    fun beginTurn(prompt: String, imageCount: Int, maxTokens: Long): Long {
        if (engine == null) {
            throw FlutterError("not_loaded", "Load a model before generating.", null)
        }
        if (prompt.isBlank() && imageCount == 0) {
            throw FlutterError("empty_prompt", "There is nothing to generate from.", null)
        }
        if (imageCount > 0 && !loadedVision) {
            throw FlutterError(
                "no_vision",
                "This model was loaded without vision. Load it with vision to send images.",
                null,
            )
        }
        if (imageCount > MAX_IMAGES) {
            throw FlutterError(
                "too_many_images",
                "A turn takes at most $MAX_IMAGES images, not $imageCount.",
                null,
            )
        }
        // maxTokens sizes the kv-cache when the engine is created, so a turn
        // can ask for less than the loaded budget but never for more.
        if (maxTokens > loadedMaxTokens) {
            throw FlutterError(
                "max_tokens_too_large",
                "The loaded model allows $loadedMaxTokens tokens. Load it again with a " +
                    "larger budget to ask for $maxTokens.",
                null,
            )
        }
        return try {
            turns.begin()
        } catch (error: GenerationBusyException) {
            throw FlutterError("busy", error.message, null)
        }
    }

    /**
     * Runs the turn [id] claimed by [beginTurn]. Never throws: a failure
     * arrives as the terminal chunk, because the caller has already been
     * answered with the request id by then.
     */
    suspend fun run(id: Long, prompt: String, images: List<ByteArray>, emit: (LlmChunk) -> Unit) {
        try {
            withContext(Dispatchers.IO) {
                val bitmaps = images.map { decodeImage(it) }
                try {
                    mutex.withLock { generateLocked(id, prompt, bitmaps, emit) }
                } finally {
                    bitmaps.forEach { it.recycle() }
                }
            }
            emit(LlmChunk(requestId = id, text = "", done = true, error = null))
        } catch (error: CancellationException) {
            emit(LlmChunk(requestId = id, text = "", done = true, error = null))
            throw error
        } catch (error: Throwable) {
            emit(
                LlmChunk(
                    requestId = id,
                    text = "",
                    done = true,
                    error = generationFailureMessage(error),
                ),
            )
        } finally {
            turns.end(id)
        }
    }

    /** Stops the stream and releases the turn. */
    fun cancel(id: Long) {
        if (!turns.cancel(id)) return
        try {
            session?.cancelGenerateResponseAsync()
        } catch (error: RuntimeException) {
            // The session may have finished between the two calls.
        }
    }

    private suspend fun generateLocked(
        id: Long,
        prompt: String,
        images: List<Bitmap>,
        emit: (LlmChunk) -> Unit,
    ) {
        val inference = engine
            ?: throw FlutterError("not_loaded", "The model was unloaded.", null)
        if (turns.isCancelled(id)) return
        val options = LlmInferenceSession.LlmInferenceSessionOptions.builder()
            .setTopK(TOP_K)
            .setTopP(TOP_P)
            .setTemperature(TEMPERATURE)
            .setGraphOptions(
                GraphOptions.builder().setEnableVisionModality(loadedVision).build(),
            )
            .build()
        val turn = LlmInferenceSession.createFromOptions(inference, options)
        session = turn
        try {
            if (prompt.isNotEmpty()) turn.addQueryChunk(prompt)
            for (image in images) turn.addImage(BitmapImageBuilder(image).build())
            await(turn) { partial, done ->
                // A cancelled turn still gets its terminal chunk from run(),
                // but no more text after the user asked it to stop.
                if (!done && partial.isNotEmpty() && !turns.isCancelled(id)) {
                    emit(LlmChunk(requestId = id, text = partial, done = false, error = null))
                }
            }
        } finally {
            session = null
            turn.close()
        }
    }

    /**
     * Bridges the task's callback onto a coroutine. Completion comes from the
     * progress listener, which is where the last text arrives. The future is
     * only watched so a failure that never reports `done` can't leave the
     * mutex held forever.
     */
    private suspend fun await(
        turn: LlmInferenceSession,
        onText: (String, Boolean) -> Unit,
    ): Unit = suspendCancellableCoroutine { continuation ->
        val listener = ProgressListener<String> { partial, done ->
            try {
                onText(partial ?: "", done)
            } catch (error: RuntimeException) {
                // A listener that throws would take down the task's thread.
            }
            if (done && continuation.isActive) continuation.resume(Unit)
        }
        val future = try {
            turn.generateResponseAsync(listener)
        } catch (error: Throwable) {
            continuation.resumeWithException(error)
            return@suspendCancellableCoroutine
        }
        val direct = Executor { it.run() }
        future.addListener(
            {
                try {
                    future.get()
                } catch (error: Throwable) {
                    if (continuation.isActive) continuation.resumeWithException(error)
                }
            },
            direct,
        )
        continuation.invokeOnCancellation {
            try {
                turn.cancelGenerateResponseAsync()
            } catch (error: RuntimeException) {
                // Already finished.
            }
        }
    }

    private fun modelFile(context: Context, relativeModelPath: String): File {
        if (!ModelFileNames.isImportedPath(relativeModelPath)) {
            throw FlutterError(
                "invalid_path",
                "Models are loaded from ${ModelFileNames.IMPORTED_DIR}/.",
                null,
            )
        }
        val file = try {
            SafePaths.resolve(context.filesDir, relativeModelPath)
        } catch (error: IllegalArgumentException) {
            throw FlutterError("invalid_path", error.message, null)
        }
        try {
            ModelFileNames.requireSupported(file.name)
        } catch (error: IllegalArgumentException) {
            throw FlutterError("unsupported_model", error.message, null)
        }
        if (!file.isFile) {
            throw FlutterError("not_found", "That model file is no longer in Memora.", null)
        }
        return file
    }

    private fun closeLocked() {
        try {
            session?.close()
        } catch (error: RuntimeException) {
            // Nothing left to do about a session that won't close.
        }
        session = null
        try {
            engine?.close()
        } catch (error: RuntimeException) {
            // Same.
        }
        engine = null
        loadedPath = null
        loadedVision = false
        loadedMaxTokens = 0
    }

    private fun decodeImage(bytes: ByteArray): Bitmap {
        if (bytes.isEmpty()) {
            throw FlutterError("invalid_image", "An image had no bytes.", null)
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw FlutterError("invalid_image", "Couldn't read one of the images.", null)
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = ImageMath.sampleSize(bounds.outWidth, bounds.outHeight, IMAGE_MAX_EDGE)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            ?: throw FlutterError("invalid_image", "Couldn't read one of the images.", null)
        val (width, height) = ImageMath.scaledSize(decoded.width, decoded.height, IMAGE_MAX_EDGE)
        if (width == decoded.width && height == decoded.height) return decoded
        val scaled = Bitmap.createScaledBitmap(decoded, width, height, true)
        if (scaled !== decoded) decoded.recycle()
        return scaled
    }

    private fun loadFailureMessage(error: Throwable): String = when (error) {
        is OutOfMemoryError ->
            "The device ran out of memory while loading the model."
        is UnsatisfiedLinkError ->
            "This build can't run on-device models on this processor."
        else ->
            "Couldn't load that model file. It may be for a different runtime."
    }

    private fun generationFailureMessage(error: Throwable): String = when {
        error is FlutterError -> error.message ?: "The model failed."
        error is OutOfMemoryError -> "The device ran out of memory while generating."
        else -> "The model stopped before it finished."
    }
}
