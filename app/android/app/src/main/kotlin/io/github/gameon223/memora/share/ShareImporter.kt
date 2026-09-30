package io.github.gameon223.memora.share

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import io.github.gameon223.memora.capture.CaptureSidecar
import io.github.gameon223.memora.capture.Inbox
import io.github.gameon223.memora.gallery.MimeTypes
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Copies shared images into the inbox, where a worker files them. */
object ShareImporter {
    suspend fun saveToInbox(context: Context, uris: List<Uri>): Int = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        var saved = 0
        for (uri in uris) {
            // Other apps can only hand Memora content URIs, never file paths.
            if (uri.scheme != ContentResolver.SCHEME_CONTENT) continue
            try {
                val mimeType = MimeTypes.normalize(resolver.getType(uri))
                if (!MimeTypes.isImage(mimeType)) continue
                val extension = MimeTypes.extensionFor(mimeType, displayName(context, uri))
                val stream = resolver.openInputStream(uri) ?: continue
                stream.use { input ->
                    Inbox.writeStream(
                        context = context,
                        input = input,
                        extension = extension,
                        source = CaptureSidecar.SOURCE_SHARE,
                        capturedAtMillis = System.currentTimeMillis(),
                    )
                }
                saved++
            } catch (error: IOException) {
                continue
            } catch (error: SecurityException) {
                continue
            }
        }
        if (saved > 0) Inbox.finishCapture(context, saved)
        saved
    }

    private fun displayName(context: Context, uri: Uri): String? = try {
        context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
    } catch (error: RuntimeException) {
        null
    }
}
