package io.github.gameon223.memora.gallery

import android.content.ContentResolver
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import io.github.gameon223.memora.bridge.CopiedImage
import io.github.gameon223.memora.bridge.CopyFailure
import io.github.gameon223.memora.bridge.CopyResult
import java.io.File
import java.io.IOException
import java.time.ZoneId
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Facts about an image file already in app storage. */
data class StoredImageFacts(
    val mimeType: String,
    val width: Int,
    val height: Int,
    val exifTakenMillis: Long?,
)

/**
 * Copies images from content URIs into `files/originals/`. Originals are
 * written once, under a new UUID, and never rewritten afterwards.
 */
class ImageImporter(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver

    suspend fun copyAll(uris: List<String>): CopyResult = withContext(Dispatchers.IO) {
        val copied = mutableListOf<CopiedImage>()
        val failed = mutableListOf<CopyFailure>()
        for (uri in uris) {
            ensureActive()
            try {
                copied += copy(uri)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                failed += CopyFailure(uri, failureMessage(error))
            }
        }
        CopyResult(copied, failed)
    }

    private fun copy(uriString: String): CopiedImage {
        val uri = Uri.parse(uriString)
        // Never accept raw file paths from other apps.
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            throw IllegalArgumentException("Only content URIs can be imported")
        }
        val dir = originalsDir(context)
        val id = UUID.randomUUID().toString()
        val part = File(dir, "$id.part")
        var target: File? = null
        try {
            val hashed = resolver.openInputStream(uri)?.use { input ->
                part.outputStream().use { output -> Hashing.copy(input, output) }
            } ?: throw IOException("Couldn't open the image")

            val facts = readFacts(part, resolver.getType(uri))
            val extension = MimeTypes.extensionFor(facts.mimeType, displayName(uri))
            val finalFile = File(dir, "$id.$extension")
            if (!part.renameTo(finalFile)) throw IOException("Couldn't save the image")
            target = finalFile

            val takenAt = TakenTime.choose(
                mediaStoreTaken = queryLong(uri, MediaStore.MediaColumns.DATE_TAKEN),
                exifTaken = facts.exifTakenMillis,
                modified = queryLong(uri, MediaStore.MediaColumns.DATE_MODIFIED)?.times(1000),
                now = System.currentTimeMillis(),
            )
            return CopiedImage(
                sourceUri = uriString,
                relativePath = "$ORIGINALS_DIR/${finalFile.name}",
                sha256 = hashed.sha256,
                mimeType = facts.mimeType,
                width = facts.width.toLong(),
                height = facts.height.toLong(),
                byteSize = hashed.byteCount,
                takenAtMillis = takenAt,
            )
        } catch (error: Exception) {
            part.delete()
            target?.delete()
            throw error
        }
    }

    private fun displayName(uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
        }
    } catch (error: RuntimeException) {
        null
    }

    /** Reads one column, tolerating providers that don't have it. */
    private fun queryLong(uri: Uri, column: String): Long? = try {
        resolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0).takeIf { it > 0 } else null
        }
    } catch (error: RuntimeException) {
        null
    }

    private fun failureMessage(error: Exception): String = when (error) {
        is SecurityException -> "Memora isn't allowed to read this image"
        is IllegalArgumentException -> error.message ?: "Unsupported image"
        is IOException -> error.message ?: "Couldn't read the image"
        else -> "Couldn't import the image"
    }

    companion object {
        const val ORIGINALS_DIR = "originals"

        fun originalsDir(context: Context): File =
            File(context.filesDir, ORIGINALS_DIR).apply { mkdirs() }

        /**
         * Decodes only the header of [file]. Throws when it isn't an image
         * Android can read, so broken files never become memories.
         */
        fun readFacts(file: File, reportedMimeType: String?): StoredImageFacts {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                throw IOException("Not a readable image")
            }
            val mimeType = MimeTypes.normalize(bounds.outMimeType)?.takeIf { MimeTypes.isImage(it) }
                ?: MimeTypes.normalize(reportedMimeType)?.takeIf { MimeTypes.isImage(it) }
                ?: "image/*"

            var orientation = Orientation.NORMAL
            var exifTaken: Long? = null
            try {
                val exif = ExifInterface(file)
                orientation = Orientation.fromExif(
                    exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL),
                )
                exifTaken = ExifDates.parse(
                    exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL),
                    exif.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL),
                    ZoneId.systemDefault(),
                )
            } catch (error: IOException) {
                // No readable EXIF, which is normal for screenshots.
            } catch (error: RuntimeException) {
                // Malformed EXIF blocks shouldn't stop an import.
            }
            val (width, height) = ImageMath.displaySize(bounds.outWidth, bounds.outHeight, orientation)
            return StoredImageFacts(mimeType, width, height, exifTaken)
        }
    }
}
