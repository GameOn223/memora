package io.github.gameon223.memora.inference

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import io.github.gameon223.memora.bridge.EmbeddingHostApi
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.TokenBatch
import java.io.File
import java.nio.LongBuffer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Runs the on-device sentence embedding model with ONNX Runtime. One session
 * is shared by every engine in the process, guarded by a mutex because both
 * the UI and a worker can embed at the same time.
 */
object OnnxEmbedder : EmbeddingHostApi {
    private const val INPUT_IDS = "input_ids"
    private const val ATTENTION_MASK = "attention_mask"
    private const val TOKEN_TYPE_IDS = "token_type_ids"
    private const val THREADS = 2

    private val mutex = Mutex()
    private var environment: OrtEnvironment? = null
    private var session: OrtSession? = null
    private var loadedPath: String? = null

    override suspend fun load(absoluteModelPath: String) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (loadedPath == absoluteModelPath && session != null) return@withLock
                if (!File(absoluteModelPath).isFile) {
                    throw FlutterError("not_found", "The model file is missing.", null)
                }
                closeLocked()
                try {
                    val env = OrtEnvironment.getEnvironment()
                    val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(THREADS) }
                    session = env.createSession(absoluteModelPath, options)
                    environment = env
                    loadedPath = absoluteModelPath
                } catch (error: OrtException) {
                    closeLocked()
                    throw FlutterError("model_failed", "Couldn't load the embedding model.", null)
                }
            }
        }
    }

    override fun isLoaded(): Boolean = session != null

    override suspend fun run(batch: TokenBatch): DoubleArray = withContext(Dispatchers.Default) {
        mutex.withLock {
            val env = environment
            val current = session
            if (env == null || current == null) {
                throw FlutterError("not_loaded", "Load the embedding model first.", null)
            }
            val sequenceLength = batch.sequenceLength.toInt()
            if (sequenceLength <= 0 || batch.inputIds.isEmpty() ||
                batch.inputIds.size % sequenceLength != 0
            ) {
                throw FlutterError("invalid_batch", "The token batch has the wrong shape.", null)
            }
            val rows = batch.inputIds.size / sequenceLength
            val shape = longArrayOf(rows.toLong(), sequenceLength.toLong())
            val inputs = mutableMapOf<String, OnnxTensor>()
            try {
                inputs[INPUT_IDS] = OnnxTensor.createTensor(env, LongBuffer.wrap(batch.inputIds), shape)
                inputs[ATTENTION_MASK] =
                    OnnxTensor.createTensor(env, LongBuffer.wrap(batch.attentionMask), shape)
                if (current.inputNames.contains(TOKEN_TYPE_IDS)) {
                    inputs[TOKEN_TYPE_IDS] =
                        OnnxTensor.createTensor(env, LongBuffer.wrap(batch.tokenTypeIds), shape)
                }
                current.run(inputs).use { results ->
                    val output = results.get(0) as? OnnxTensor
                        ?: throw FlutterError("model_failed", "Unexpected model output.", null)
                    val buffer = output.floatBuffer
                        ?: throw FlutterError("model_failed", "Unexpected model output.", null)
                    val values = FloatArray(buffer.remaining())
                    buffer.get(values)
                    val dimensions = values.size / (rows * sequenceLength)
                    Pooling.clsNormalized(values, rows, sequenceLength, dimensions)
                }
            } catch (error: OrtException) {
                throw FlutterError("model_failed", "The embedding model failed to run.", null)
            } finally {
                inputs.values.forEach { it.close() }
            }
        }
    }

    /** Frees the session, for example after the model file is removed. */
    suspend fun unload() {
        mutex.withLock { closeLocked() }
    }

    private fun closeLocked() {
        session?.close()
        session = null
        loadedPath = null
    }
}
