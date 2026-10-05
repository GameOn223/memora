package io.github.gameon223.memora.gallery

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.files.SafePaths
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** WebP thumbnails for images in app storage. */
object Thumbnails {
    const val THUMBNAILS_DIR = "thumbnails"
    private const val QUALITY = 80

    /** Writes `thumbnails/<source name>.webp` and returns that relative path. */
    suspend fun create(context: Context, relativeSourcePath: String, maxEdge: Int): String =
        withContext(Dispatchers.IO) {
            val root = context.filesDir
            val source = try {
                SafePaths.resolve(root, relativeSourcePath)
            } catch (error: IllegalArgumentException) {
                throw FlutterError("invalid_path", error.message, null)
            }
            if (!source.isFile) throw FlutterError("not_found", "The image file is missing.", null)

            val bitmap = decodeUpright(source, maxEdge)
                ?: throw FlutterError("decode_failed", "Couldn't read the image.", null)
            val dir = File(root, THUMBNAILS_DIR).apply { mkdirs() }
            val name = "${source.nameWithoutExtension}.webp"
            val target = File(dir, name)
            val part = File(dir, "$name.part")
            try {
                part.outputStream().use { out ->
                    if (!bitmap.compress(webpFormat(), QUALITY, out)) {
                        throw IOException("Couldn't encode the thumbnail")
                    }
                }
                if (target.exists()) target.delete()
                if (!part.renameTo(target)) throw IOException("Couldn't save the thumbnail")
            } catch (error: IOException) {
                part.delete()
                throw FlutterError("write_failed", error.message, null)
            } finally {
                bitmap.recycle()
            }
            "$THUMBNAILS_DIR/$name"
        }

    /**
     * Decodes [file] at the smallest size that still covers [maxEdge], scales
     * it to fit, and applies the EXIF orientation.
     */
    fun decodeUpright(file: File, maxEdge: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val options = BitmapFactory.Options().apply {
            inSampleSize = ImageMath.sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
        }
        val decoded = BitmapFactory.decodeFile(file.path, options) ?: return null
        val (width, height) = ImageMath.scaledSize(decoded.width, decoded.height, maxEdge)
        val scaled = if (width != decoded.width || height != decoded.height) {
            Bitmap.createScaledBitmap(decoded, width, height, true).also {
                if (it !== decoded) decoded.recycle()
            }
        } else {
            decoded
        }
        return applyOrientation(scaled, readOrientation(file))
    }

    fun scaleToFit(bitmap: Bitmap, maxEdge: Int): Bitmap {
        val (width, height) = ImageMath.scaledSize(bitmap.width, bitmap.height, maxEdge)
        if (width == bitmap.width && height == bitmap.height) return bitmap
        return Bitmap.createScaledBitmap(bitmap, width, height, true).also {
            if (it !== bitmap) bitmap.recycle()
        }
    }

    private fun readOrientation(file: File): Orientation = try {
        Orientation.fromExif(
            ExifInterface(file).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            ),
        )
    } catch (error: IOException) {
        Orientation.NORMAL
    } catch (error: RuntimeException) {
        Orientation.NORMAL
    }

    private fun applyOrientation(bitmap: Bitmap, orientation: Orientation): Bitmap {
        if (orientation.isIdentity) return bitmap
        val matrix = Matrix().apply {
            if (orientation.flipHorizontal) postScale(-1f, 1f)
            if (orientation.rotationDegrees != 0) postRotate(orientation.rotationDegrees.toFloat())
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    @Suppress("DEPRECATION")
    private fun webpFormat(): Bitmap.CompressFormat =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY
        else Bitmap.CompressFormat.WEBP
}
