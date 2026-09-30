package io.github.gameon223.memora.gallery

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.BaseColumns
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.CopyResult
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.GalleryHostApi
import io.github.gameon223.memora.bridge.GalleryImage
import io.github.gameon223.memora.bridge.GalleryPage
import io.github.gameon223.memora.bridge.GalleryPermission
import io.github.gameon223.memora.bridge.awaitActivityResult
import java.io.ByteArrayOutputStream
import kotlin.math.min
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class GalleryHostApiImpl(
    private val context: Context,
    private val activity: ActivityHolder,
) : GalleryHostApi {
    private val resolver: ContentResolver = context.contentResolver
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val importer = ImageImporter(context)

    override fun permissionState(): GalleryPermission = currentPermission()

    override suspend fun requestPermission(): GalleryPermission {
        if (currentPermission() == GalleryPermission.GRANTED) return GalleryPermission.GRANTED
        val host = activity.require()
        host.awaitActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
            GalleryPermissions.toRequest(Build.VERSION.SDK_INT),
        )
        prefs.edit().putBoolean(KEY_ASKED, true).apply()
        return currentPermission()
    }

    override fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", context.packageName, null),
        )
        val host = activity.current
        if (host != null) {
            host.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    override suspend fun listImages(offset: Long, limit: Long): GalleryPage = withContext(Dispatchers.IO) {
        val pageSize = limit.toInt().coerceIn(1, MAX_PAGE)
        val start = offset.toInt().coerceAtLeast(0)
        val images = mutableListOf<GalleryImage>()
        // Ask for one extra row to learn whether another page exists.
        queryPage(start, pageSize + 1)?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val taken = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val added = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val modified = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val width = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
            val height = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
            val size = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val mime = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val orientation = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.ORIENTATION)
            while (cursor.moveToNext()) {
                val (w, h) = ImageMath.displaySize(
                    cursor.getIntOrZero(width),
                    cursor.getIntOrZero(height),
                    Orientation.fromDegrees(cursor.getIntOrZero(orientation)),
                )
                images += GalleryImage(
                    uri = ContentUris.withAppendedId(COLLECTION, cursor.getLong(id)).toString(),
                    takenAtMillis = TakenTime.choose(
                        mediaStoreTaken = cursor.getLongOrNull(taken),
                        exifTaken = null,
                        modified = cursor.getLongOrNull(modified)?.times(1000),
                        now = (cursor.getLongOrNull(added) ?: 0L) * 1000,
                    ),
                    width = w.toLong(),
                    height = h.toLong(),
                    byteSize = cursor.getLongOrNull(size) ?: 0L,
                    mimeType = cursor.getString(mime) ?: "image/*",
                )
            }
        }
        val hasMore = images.size > pageSize
        GalleryPage(images.take(pageSize), hasMore)
    }

    override suspend fun thumbnail(uri: String, size: Long): ByteArray = withContext(Dispatchers.IO) {
        val parsed = requireContentUri(uri)
        val edge = size.toInt().coerceIn(32, 1024)
        val bitmap = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.loadThumbnail(parsed, Size(edge, edge), null)
            } else {
                decodeSampled(parsed, edge)
            }
        } catch (error: java.io.IOException) {
            throw FlutterError("thumbnail_failed", "Couldn't load a preview for this image.", null)
        } catch (error: SecurityException) {
            throw FlutterError("permission_denied", "Memora can't read this image.", null)
        }
        val fitted = try {
            Thumbnails.scaleToFit(bitmap, edge)
        } catch (error: RuntimeException) {
            bitmap.recycle()
            throw FlutterError("thumbnail_failed", "Couldn't scale this image.", null)
        }
        try {
            ByteArrayOutputStream().use { out ->
                fitted.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                out.toByteArray()
            }
        } finally {
            fitted.recycle()
        }
    }

    override suspend fun pickWithSystemPicker(maxItems: Long): List<String> {
        val host = activity.require()
        val request = PickVisualMediaRequest.Builder()
            .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly)
            .build()
        val limit = pickerLimit(maxItems.toInt())
        val uris = if (limit <= 1) {
            listOfNotNull(host.awaitActivityResult(ActivityResultContracts.PickVisualMedia(), request))
        } else {
            host.awaitActivityResult(ActivityResultContracts.PickMultipleVisualMedia(limit), request)
        }
        return uris.map { it.toString() }
    }

    override suspend fun copyToAppStorage(uris: List<String>): CopyResult = importer.copyAll(uris)

    override suspend fun createThumbnail(relativeSourcePath: String, maxEdge: Long): String =
        Thumbnails.create(context, relativeSourcePath, maxEdge.toInt().coerceIn(64, 2048))

    private fun currentPermission(): GalleryPermission {
        val sdk = Build.VERSION.SDK_INT
        val fullPermission = GalleryPermissions.fullAccessPermission(sdk)
        val full = isGranted(fullPermission)
        val partial = GalleryPermissions.supportsPartialAccess(sdk) &&
            isGranted(android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        // Without an activity there's no way to ask about the rationale, so
        // never report "permanently denied" from the headless engine.
        val host = activity.current
        val rationale = host?.let { ActivityCompat.shouldShowRequestPermissionRationale(it, fullPermission) } ?: true
        return GalleryPermissions.resolve(full, partial, prefs.getBoolean(KEY_ASKED, false), rationale)
    }

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun queryPage(offset: Int, limit: Int): Cursor? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // Older MediaProvider versions ignore paging arguments in a
            // Bundle but accept LIMIT in the sort clause.
            return resolver.query(COLLECTION, PROJECTION, null, null, "$SORT_SQL LIMIT $limit OFFSET $offset")
        }
        val args = Bundle().apply {
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
            putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, SORT_SQL)
        }
        return try {
            resolver.query(COLLECTION, PROJECTION, args, null)
        } catch (error: IllegalArgumentException) {
            // A provider with strict sort grammar may refuse COALESCE.
            args.remove(ContentResolver.QUERY_ARG_SQL_SORT_ORDER)
            args.putStringArray(
                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.MediaColumns.DATE_TAKEN, MediaStore.MediaColumns.DATE_MODIFIED),
            )
            args.putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            resolver.query(COLLECTION, PROJECTION, args, null)
        }
    }

    private fun decodeSampled(uri: Uri, edge: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0) throw java.io.IOException("Not a readable image")
        val options = BitmapFactory.Options().apply {
            inSampleSize = ImageMath.sampleSize(bounds.outWidth, bounds.outHeight, edge)
        }
        return resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            ?: throw java.io.IOException("Not a readable image")
    }

    private fun requireContentUri(uri: String): Uri {
        val parsed = Uri.parse(uri)
        if (parsed.scheme != ContentResolver.SCHEME_CONTENT) {
            throw FlutterError("invalid_uri", "Only content URIs are supported.", null)
        }
        return parsed
    }

    private fun pickerLimit(requested: Int): Int {
        val wanted = requested.coerceAtLeast(1)
        return try {
            // The limit only exists from Android 13. Older devices reach the
            // picker through a backport with its own, smaller cap.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                min(wanted, MediaStore.getPickImagesMaxLimit())
            } else {
                min(wanted, FALLBACK_PICKER_LIMIT)
            }
        } catch (error: NoSuchMethodError) {
            min(wanted, FALLBACK_PICKER_LIMIT)
        }
    }

    private fun Cursor.getLongOrNull(index: Int): Long? =
        if (isNull(index)) null else getLong(index).takeIf { it > 0 }

    private fun Cursor.getIntOrZero(index: Int): Int = if (isNull(index)) 0 else getInt(index)

    private companion object {
        const val PREFS_NAME = "memora_gallery"
        const val KEY_ASKED = "permission_requested"
        const val MAX_PAGE = 500
        const val JPEG_QUALITY = 85
        const val FALLBACK_PICKER_LIMIT = 100
        const val SORT_SQL = "COALESCE(datetaken, date_modified * 1000) DESC, _id DESC"

        val COLLECTION: Uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

        val PROJECTION = arrayOf(
            BaseColumns._ID,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.ORIENTATION,
        )
    }
}
