package io.github.gameon223.memora.files

import android.content.Context
import androidx.activity.result.contract.ActivityResultContracts
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.FilesHostApi
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.awaitActivityResult
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class FilesHostApiImpl(
    private val context: Context,
    private val activity: ActivityHolder,
) : FilesHostApi {
    override fun filesDir(): String = context.filesDir.absolutePath

    override suspend fun saveToUserLocation(
        absoluteSourcePath: String,
        suggestedName: String,
        mimeType: String,
    ): Boolean {
        val source = File(absoluteSourcePath)
        try {
            SafePaths.requireInside(source, listOf(context.filesDir, context.cacheDir))
        } catch (error: IllegalArgumentException) {
            throw FlutterError("invalid_path", error.message, null)
        }
        if (!source.isFile) throw FlutterError("not_found", "The file to save doesn't exist.", null)

        val host = activity.require()
        val target = host.awaitActivityResult(
            ActivityResultContracts.CreateDocument(mimeType),
            suggestedName,
        ) ?: return false

        withContext(Dispatchers.IO) {
            val output = context.contentResolver.openOutputStream(target, "w")
                ?: throw FlutterError("write_failed", "Couldn't open the chosen location.", null)
            output.use { out ->
                source.inputStream().use { input -> input.copyTo(out, BUFFER_BYTES) }
            }
        }
        return true
    }

    private companion object {
        const val BUFFER_BYTES = 64 * 1024
    }
}
