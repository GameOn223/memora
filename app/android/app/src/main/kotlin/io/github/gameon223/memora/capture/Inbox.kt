package io.github.gameon223.memora.capture

import android.content.Context
import android.graphics.Bitmap
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.background.IngestWorker
import io.github.gameon223.memora.bridge.InboxItem
import io.github.gameon223.memora.gallery.Hashing
import io.github.gameon223.memora.gallery.ImageImporter
import io.github.gameon223.memora.gallery.MimeTypes
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Captures and shared images wait here as a PNG plus a small JSON sidecar
 * until a Dart engine files them. The sidecar is written last, so its
 * presence means the image is complete.
 */
object Inbox {
    const val INBOX_DIR = "inbox"

    /** Unpaired files older than this are swept away. */
    private const val ORPHAN_AGE_MILLIS = 24 * 60 * 60 * 1000L

    private val drainMutex = Mutex()

    fun dir(context: Context): File = File(context.filesDir, INBOX_DIR).apply { mkdirs() }

    suspend fun writeBitmap(
        context: Context,
        bitmap: Bitmap,
        source: String,
        capturedAtMillis: Long,
    ): File = withContext(Dispatchers.IO) {
        write(context, "png", source, capturedAtMillis) { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw IOException("Couldn't encode the screenshot")
            }
        }
    }

    suspend fun writeStream(
        context: Context,
        input: InputStream,
        extension: String,
        source: String,
        capturedAtMillis: Long,
    ): File = withContext(Dispatchers.IO) {
        write(context, extension, source, capturedAtMillis) { output ->
            input.copyTo(output, DEFAULT_BUFFER_SIZE)
        }
    }

    /** Tells the user the file is safe and asks a worker to file it. */
    fun finishCapture(context: Context, count: Int) {
        Notifications.captureSaved(context, count)
        IngestWorker.enqueue(context)
    }

    /**
     * Moves every complete inbox entry into `originals/` and reports it.
     * Runs one at a time, because the UI engine and a worker can both ask.
     */
    suspend fun drain(context: Context): List<InboxItem> = drainMutex.withLock {
        withContext(Dispatchers.IO) {
            val dir = dir(context)
            val items = mutableListOf<InboxItem>()
            for (sidecarFile in dir.listFiles().orEmpty().filter { it.name.endsWith(".json") }) {
                val id = sidecarFile.nameWithoutExtension
                val sidecar = try {
                    CaptureSidecar.parse(sidecarFile.readText(), "$id.png")
                } catch (error: IOException) {
                    null
                }
                val image = imageFor(dir, id, sidecar)
                if (image == null) {
                    sidecarFile.delete()
                    continue
                }
                try {
                    items += fileOne(context, image, sidecar)
                    sidecarFile.delete()
                } catch (error: IOException) {
                    // The file can't be read, so it never becomes a memory.
                    image.delete()
                    sidecarFile.delete()
                }
            }
            sweepOrphans(dir)
            items
        }
    }

    private fun fileOne(context: Context, image: File, sidecar: CaptureSidecar?): InboxItem {
        val hashed = Hashing.hashFile(image)
        val facts = ImageImporter.readFacts(image, MimeTypes.mimeForExtension(image.extension))
        val target = File(ImageImporter.originalsDir(context), image.name)
        if (!image.renameTo(target)) throw IOException("Couldn't move the capture")
        val capturedAt = sidecar?.capturedAtMillis?.takeIf { it > 0 } ?: image.lastModified()
        return InboxItem(
            relativePath = "${ImageImporter.ORIGINALS_DIR}/${target.name}",
            source = sidecar?.source ?: CaptureSidecar.SOURCE_TILE,
            capturedAtMillis = capturedAt,
            sha256 = hashed.sha256,
            mimeType = facts.mimeType,
            width = facts.width.toLong(),
            height = facts.height.toLong(),
            byteSize = hashed.byteCount,
        )
    }

    private fun imageFor(dir: File, id: String, sidecar: CaptureSidecar?): File? {
        sidecar?.fileName?.let { name ->
            val named = File(dir, name)
            if (named.isFile) return named
        }
        return dir.listFiles().orEmpty().firstOrNull {
            it.isFile && it.nameWithoutExtension == id && !it.name.endsWith(".json") && !it.name.endsWith(".part")
        }
    }

    private fun sweepOrphans(dir: File) {
        val cutoff = System.currentTimeMillis() - ORPHAN_AGE_MILLIS
        val files = dir.listFiles().orEmpty()
        val sidecarIds = files.filter { it.name.endsWith(".json") }.map { it.nameWithoutExtension }.toSet()
        for (file in files) {
            if (file.name.endsWith(".json")) continue
            if (file.nameWithoutExtension.removeSuffix(".png") in sidecarIds) continue
            if (file.lastModified() < cutoff) file.delete()
        }
    }

    private inline fun write(
        context: Context,
        extension: String,
        source: String,
        capturedAtMillis: Long,
        writeImage: (java.io.OutputStream) -> Unit,
    ): File {
        val dir = dir(context)
        val id = UUID.randomUUID().toString()
        val imagePart = File(dir, "$id.$extension.part")
        val image = File(dir, "$id.$extension")
        try {
            imagePart.outputStream().use(writeImage)
            if (!imagePart.renameTo(image)) throw IOException("Couldn't save the capture")
            val sidecarPart = File(dir, "$id.json.part")
            sidecarPart.writeText(CaptureSidecar(source, capturedAtMillis, image.name).toJson())
            val sidecar = File(dir, "$id.json")
            if (!sidecarPart.renameTo(sidecar)) {
                sidecarPart.delete()
                throw IOException("Couldn't save the capture details")
            }
            return image
        } catch (error: IOException) {
            imagePart.delete()
            image.delete()
            throw error
        }
    }
}
