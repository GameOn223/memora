package io.github.gameon223.memora.capture

import org.json.JSONException
import org.json.JSONObject

/**
 * What Kotlin knows about a capture before Dart files it. Written next to the
 * image as `<id>.json`, because the Kotlin side can't write to the database.
 */
data class CaptureSidecar(
    val source: String,
    val capturedAtMillis: Long,
    val fileName: String,
    /** Copy handed to Dart by the last drain, kept for diagnostics. */
    val pendingPath: String? = null,
) {
    fun toJson(): String = JSONObject()
        .put(KEY_SOURCE, source)
        .put(KEY_CAPTURED_AT, capturedAtMillis)
        .put(KEY_FILE_NAME, fileName)
        .apply { if (pendingPath != null) put(KEY_PENDING_PATH, pendingPath) }
        .toString()

    companion object {
        const val SOURCE_TILE = "tile"
        const val SOURCE_SHARE = "share"

        private const val KEY_SOURCE = "source"
        private const val KEY_CAPTURED_AT = "captured_at_millis"
        private const val KEY_FILE_NAME = "file_name"
        private const val KEY_PENDING_PATH = "pending_path"

        /**
         * Reads a sidecar. Missing fields fall back to [fallbackFileName] and
         * a tile capture, so an older or truncated file still gets filed.
         * A capture time of zero means the caller should use the file's own
         * modified time.
         */
        fun parse(json: String, fallbackFileName: String): CaptureSidecar? = try {
            val obj = JSONObject(json)
            val source = obj.optString(KEY_SOURCE).ifBlank { SOURCE_TILE }
            val fileName = obj.optString(KEY_FILE_NAME).ifBlank { fallbackFileName }
            CaptureSidecar(
                source = if (source == SOURCE_SHARE) SOURCE_SHARE else SOURCE_TILE,
                capturedAtMillis = obj.optLong(KEY_CAPTURED_AT, 0L).coerceAtLeast(0L),
                fileName = fileName,
                pendingPath = obj.optString(KEY_PENDING_PATH).ifBlank { null },
            )
        } catch (error: JSONException) {
            null
        }
    }
}
