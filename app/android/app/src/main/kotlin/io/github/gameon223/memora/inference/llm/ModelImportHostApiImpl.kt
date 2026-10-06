package io.github.gameon223.memora.inference.llm

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.ImportedModel
import io.github.gameon223.memora.bridge.ModelImportHostApi
import io.github.gameon223.memora.bridge.ModelImportProgress
import io.github.gameon223.memora.bridge.awaitActivityResult
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Brings a model file into app storage through the system file picker.
 *
 * The copy goes to a `.part` file and is renamed once it is whole, the same
 * way a downloaded model lands, so a file that exists under its real name is
 * a complete file. That is the only state this keeps, and it survives a
 * restart without a record of its own.
 */
class ModelImportHostApiImpl(
    private val context: Context,
    private val activity: ActivityHolder,
) : ModelImportHostApi {
    override suspend fun pickModelFile(): ImportedModel? {
        val host = activity.require()
        // Model bundles have no registered MIME type, so the picker has to
        // show everything. The extension decides what is accepted.
        val uri = host.awaitActivityResult(
            ActivityResultContracts.OpenDocument(),
            arrayOf("*/*"),
        ) ?: return null
        return copyIn(uri)
    }

    override suspend fun deleteModel(relativePath: String) {
        val file = importedFile(relativePath)
        withContext(Dispatchers.IO) {
            if (GemmaRuntime.loadedModelPath() == relativePath) GemmaRuntime.unloadQuietly()
            if (file.exists() && !file.delete()) {
                throw FlutterError("delete_failed", "Couldn't remove that model file.", null)
            }
        }
    }

    override fun listModels(): List<ImportedModel> {
        val dir = File(context.filesDir, ModelFileNames.IMPORTED_DIR)
        val files = dir.listFiles() ?: return emptyList()
        return files
            .filter { it.isFile && ModelFileNames.isSupported(it.name) }
            .sortedBy { it.name }
            .map {
                ImportedModel(
                    relativePath = ModelFileNames.relativePath(it.name),
                    fileName = it.name,
                    byteSize = it.length(),
                )
            }
    }

    private suspend fun copyIn(uri: Uri): ImportedModel = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            throw FlutterError("invalid_source", "Pick the model from the file picker.", null)
        }
        val displayName = queryDisplayName(resolver, uri)
        val fileName = ModelFileNames.sanitize(displayName)
        try {
            ModelFileNames.requireSupported(fileName)
        } catch (error: IllegalArgumentException) {
            throw FlutterError("unsupported_model", error.message, null)
        }

        val dir = File(context.filesDir, ModelFileNames.IMPORTED_DIR)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw FlutterError("write_failed", "Couldn't create the models folder.", null)
        }
        val taken = (dir.listFiles() ?: emptyArray()).map { it.name }.toSet()
        val finalName = ModelFileNames.deduplicate(fileName, taken)
        val target = File(dir, finalName)
        val part = File(dir, "$finalName.part")

        val expected = querySize(resolver, uri)
        // A 3 GB model needs 3 GB of room, and the file it is copied from is
        // usually still on the phone as well.
        if (expected != null && expected > dir.usableSpace) {
            throw FlutterError(
                "no_space",
                "That model needs ${expected / MB} MB and only " +
                    "${dir.usableSpace / MB} MB is free.",
                null,
            )
        }

        var copied = 0L
        try {
            resolver.openInputStream(uri).use { input ->
                if (input == null) throw IOException("Couldn't open the file you picked")
                part.outputStream().use { output ->
                    copied = ModelCopy.copy(input, output, expected ?: 0L) { soFar ->
                        ModelImportEvents.send(
                            ModelImportProgress(copiedBytes = soFar, totalBytes = expected ?: 0L),
                        )
                    }
                }
            }
            if (copied <= 0L) throw IOException("The file you picked is empty")
            if (expected != null && copied != expected) {
                throw IOException("The copy ended early at $copied of $expected bytes")
            }
            if (!part.renameTo(target)) throw IOException("Couldn't save the model file")
        } catch (error: Exception) {
            part.delete()
            if (error is FlutterError) throw error
            throw FlutterError("copy_failed", error.message ?: "Couldn't copy the model.", null)
        }
        ImportedModel(
            relativePath = ModelFileNames.relativePath(finalName),
            fileName = finalName,
            byteSize = target.length(),
        )
    }

    private fun importedFile(relativePath: String): File {
        if (!ModelFileNames.isImportedPath(relativePath)) {
            throw FlutterError(
                "invalid_path",
                "Only files in ${ModelFileNames.IMPORTED_DIR}/ can be removed here.",
                null,
            )
        }
        return File(context.filesDir, relativePath)
    }

    private fun queryDisplayName(resolver: ContentResolver, uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
        }
    } catch (error: RuntimeException) {
        null
    }

    private fun querySize(resolver: ContentResolver, uri: Uri): Long? = try {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) {
                cursor.getLong(0).takeIf { it > 0 }
            } else {
                null
            }
        }
    } catch (error: RuntimeException) {
        null
    }

    private companion object {
        const val MB = 1024 * 1024
    }
}
