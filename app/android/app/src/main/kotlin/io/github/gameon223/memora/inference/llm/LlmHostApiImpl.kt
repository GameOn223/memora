package io.github.gameon223.memora.inference.llm

import android.content.Context
import io.github.gameon223.memora.MemoraApplication
import io.github.gameon223.memora.bridge.DeviceMemory
import io.github.gameon223.memora.bridge.LlmHostApi
import kotlinx.coroutines.launch

/**
 * The Dart-facing side of [GemmaRuntime]. One instance per Flutter engine,
 * while the model behind it is shared by the process.
 */
class LlmHostApiImpl(private val context: Context) : LlmHostApi {
    override suspend fun load(relativeModelPath: String, vision: Boolean, maxTokens: Long) =
        GemmaRuntime.load(context, relativeModelPath, vision, maxTokens)

    override fun isLoaded(): Boolean = GemmaRuntime.isLoaded()

    override fun loadedModelPath(): String? = GemmaRuntime.loadedModelPath()

    override suspend fun unload() = GemmaRuntime.unload()

    override suspend fun startGeneration(
        prompt: String,
        images: List<ByteArray>,
        maxTokens: Long,
    ): Long {
        val id = GemmaRuntime.beginTurn(prompt, images.size, maxTokens)
        // The reply carries the id straight back, so the work runs on a scope
        // that outlives this call and the engine that made it.
        MemoraApplication.from(context).appScope.launch {
            GemmaRuntime.run(id, prompt, images, LlmChunks::send)
        }
        return id
    }

    override fun cancelGeneration(requestId: Long) = GemmaRuntime.cancel(requestId)

    override fun deviceMemory(): DeviceMemory = GemmaRuntime.deviceMemory(context)
}
