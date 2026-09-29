package io.github.gameon223.memora.capture

import android.content.Context
import android.graphics.Bitmap
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.background.IngestWorker
import io.github.gameon223.memora.bridge.InboxItem
import io.github.gameon223.memora.gallery.Hashing
import io.github.gameon223.memora.gallery.ImageImporter
import io.github.gameon223.memora.gallery.MimeTypes
import io.github.gameon223.memora.gallery.StoredImageFacts
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Reads size, type and orientation from a stored image file. */
typealias FactsReader = (File) -> StoredImageFacts

/**
 * Captures and shared images wait here until a Dart engine files them.
 *
 * Each entry is an image plus a small JSON sidecar, written last so its
 * presence means the image is complete. A drain copies the image into
 * `originals/` and hands it to Dart, but keeps the inbox entry until
 * [confirm] says the memory row exists. A worker that is stopped halfway
 * therefore loses nothing: the next drain offers the capture again.
 */
object Inbox {
    const val INBOX_DIR = "inbox"
    const val SIDECAR_SUFFIX = ".json"
    private const val PART_SUFFIX = ".part"

    /** Unpaired files older than this are swept away. */
    private const val ORPHAN_AGE_MILLIS = 24 * 60 * 60 * 1000L

    private val drainMutex = Mutex()

    private val defaultFacts: FactsReader = { file ->
        ImageImporter.readFacts(file, MimeTypes.mimeForExtension(file.extension))
    }

    fun dir(filesDir: File): File = File(filesDir, INBOX_DIR).apply { mkdirs() }

    fun dir(context: Context): File = dir(context.filesDir)

    suspend fun writeBitmap(
        context: Context,
        bitmap: Bitmap,
        source: String,
        capturedAtMillis: Long,
    ): File = withContext(Dispatchers.IO) {
        write(context.filesDir, "png", source, capturedAtMillis) { output ->
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
        write(context.filesDir, extension, source, capturedAtMillis) { output ->
            input.copyTo(output, DEFAULT_BUFFER_SIZE)
        }
    }

    /** Tells the user the file is safe and asks a worker to file it. */
    fun finishCapture(context: Context, count: Int) {
        Notifications.captureSaved(context, count)
        IngestWorker.enqueue(context)
    }

    suspend fun drain(context: Context): List<InboxItem> = drain(context.filesDir)

    suspend fun confirm(context: Context, ids: List<String>) = confirm(context.filesDir, ids)

    /**
     * Copies every complete inbox entry into `originals/` and reports it.
     * Runs one at a time, because the UI engine and a worker can both ask.
     *
     * Every drain writes a fresh copy. When an earlier hand-off was never
     * confirmed the memory may already exist, and the ingestor then drops
     * the new copy as a duplicate instead of the file a row points at.
     */
    suspend fun drain(
        filesDir: File,
        readFacts: FactsReader = defaultFacts,
        newId: () -> String = { UUID.randomUUID().toString() },
        now: Long = System.currentTimeMillis(),
    ): List<InboxItem> = drainMutex.withLock {
        withContext(Dispatchers.IO) {
            val inbox = dir(filesDir)
            val originals = File(filesDir, ImageImporter.ORIGINALS_DIR).apply { mkdirs() }
            val items = mutableListOf<InboxItem>()
            val sidecars = inbox.listFiles().orEmpty()
                .filter { it.isFile && it.name.endsWith(SIDECAR_SUFFIX) }
                .sortedBy { it.name }
            for (sidecarFile in sidecars) {
                val id = sidecarFile.name.removeSuffix(SIDECAR_SUFFIX)
                val sidecar = readSidecar(sidecarFile, id)
                val image = imageFor(inbox, id, sidecar)
                if (image == null) {
                    // Nothing to file: the image never landed or was swept.
                    sidecarFile.delete()
                    continue
                }
                val item = try {
                    copyToOriginals(originals, image, id, sidecar, readFacts, newId)
                } catch (error: IOException) {
                    // Android can't read it, so it can never become a memory.
                    image.delete()
                    sidecarFile.delete()
                    null
                }
                if (item != null) {
                    writeSidecar(inbox, id, sidecar.copy(pendingPath = item.relativePath))
                    items += item
                }
            }
            sweepOrphans(inbox, now)
            items
        }
    }

    /** Drops inbox entries whose memories exist. */
    suspend fun confirm(filesDir: File, ids: List<String>) {
        if (ids.isEmpty()) return
        drainMutex.withLock {
            withContext(Dispatchers.IO) {
                val inbox = dir(filesDir)
                val wanted = ids.toSet()
                for (file in inbox.listFiles().orEmpty()) {
                    if (file.name.substringBefore('.') in wanted) file.delete()
                }
            }
        }
    }

    private fun copyToOriginals(
        originals: File,
        image: File,
        id: String,
        sidecar: CaptureSidecar,
        readFacts: FactsReader,
        newId: () -> String,
    ): InboxItem {
        val facts = readFacts(image)
        val hashed = Hashing.hashFile(image)
        val extension = image.extension.ifEmpty { MimeTypes.extensionFor(facts.mimeType) }
        val name = "${newId()}.$extension"
        val target = File(originals, name)
        val part = File(originals, "$name$PART_SUFFIX")
        try {
            image.inputStream().use { input ->
                part.outputStream().use { output -> input.copyTo(output, DEFAULT_BUFFER_SIZE) }
            }
            if (!part.renameTo(target)) {
                part.copyTo(target, overwrite = true)
                part.delete()
            }
        } catch (error: IOException) {
            part.delete()
            target.delete()
            throw error
        }
        return InboxItem(
            id = id,
            relativePath = "${ImageImporter.ORIGINALS_DIR}/$name",
            source = sidecar.source,
            capturedAtMillis = sidecar.capturedAtMillis.takeIf { it > 0 } ?: image.lastModified(),
            sha256 = hashed.sha256,
            mimeType = facts.mimeType,
            width = facts.width.toLong(),
            height = facts.height.toLong(),
            byteSize = hashed.byteCount,
        )
    }

    private fun readSidecar(sidecarFile: File, id: String): CaptureSidecar {
        val fallback = CaptureSidecar(CaptureSidecar.SOURCE_TILE, 0, "$id.png")
        return try {
            CaptureSidecar.parse(sidecarFile.readText(), "$id.png") ?: fallback
        } catch (error: IOException) {
            fallback
        }
    }

    private fun imageFor(inbox: File, id: String, sidecar: CaptureSidecar): File? {
        val named = File(inbox, sidecar.fileName)
        if (named.isFile) return named
        return inbox.listFiles().orEmpty().firstOrNull {
            it.isFile &&
                it.name.substringBefore('.') == id &&
                !it.name.endsWith(SIDECAR_SUFFIX) &&
                !it.name.endsWith(PART_SUFFIX)
        }
    }

    private fun writeSidecar(inbox: File, id: String, sidecar: CaptureSidecar) {
        val part = File(inbox, "$id$SIDECAR_SUFFIX$PART_SUFFIX")
        val target = File(inbox, "$id$SIDECAR_SUFFIX")
        part.writeText(sidecar.toJson())
        if (!part.renameTo(target)) {
            part.copyTo(target, overwrite = true)
            part.delete()
        }
    }

    /** Deletes images with no sidecar, and half-written files, after a day. */
    fun sweepOrphans(inbox: File, now: Long = System.currentTimeMillis()) {
        val cutoff = now - ORPHAN_AGE_MILLIS
        val files = inbox.listFiles().orEmpty()
        val known = files
            .filter { it.name.endsWith(SIDECAR_SUFFIX) }
            .map { it.name.removeSuffix(SIDECAR_SUFFIX) }
            .toSet()
        for (file in files) {
            if (file.name.endsWith(SIDECAR_SUFFIX)) continue
            val id = file.name.substringBefore('.')
            if (id in known && !file.name.endsWith(PART_SUFFIX)) continue
            if (file.lastModified() < cutoff) file.delete()
        }
    }

    private inline fun write(
        filesDir: File,
        extension: String,
        source: String,
        capturedAtMillis: Long,
        writeImage: (OutputStream) -> Unit,
    ): File {
        val inbox = dir(filesDir)
        val id = UUID.randomUUID().toString()
        val imagePart = File(inbox, "$id.$extension$PART_SUFFIX")
        val image = File(inbox, "$id.$extension")
        try {
            imagePart.outputStream().use(writeImage)
            if (!imagePart.renameTo(image)) {
                // A rename can fail on some storage; keep the capture anyway.
                imagePart.copyTo(image, overwrite = true)
                imagePart.delete()
            }
            writeSidecar(inbox, id, CaptureSidecar(source, capturedAtMillis, image.name))
            return image
        } catch (error: IOException) {
            imagePart.delete()
            image.delete()
            throw error
        }
    }
}
