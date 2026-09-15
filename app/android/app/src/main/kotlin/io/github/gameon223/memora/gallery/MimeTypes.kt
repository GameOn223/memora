package io.github.gameon223.memora.gallery

/** File extensions for the image types Memora stores. */
object MimeTypes {
    private val extensionsByMime = mapOf(
        "image/jpeg" to "jpg",
        "image/jpg" to "jpg",
        "image/pjpeg" to "jpg",
        "image/png" to "png",
        "image/webp" to "webp",
        "image/gif" to "gif",
        "image/heic" to "heic",
        "image/heif" to "heif",
        "image/avif" to "avif",
        "image/bmp" to "bmp",
        "image/x-ms-bmp" to "bmp",
    )

    private val mimesByExtension = mapOf(
        "jpg" to "image/jpeg",
        "jpeg" to "image/jpeg",
        "png" to "image/png",
        "webp" to "image/webp",
        "gif" to "image/gif",
        "heic" to "image/heic",
        "heif" to "image/heif",
        "avif" to "image/avif",
        "bmp" to "image/bmp",
    )

    /** Lowercases and drops parameters: `Image/PNG; q=1` becomes `image/png`. */
    fun normalize(mimeType: String?): String? =
        mimeType?.substringBefore(';')?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }

    fun isImage(mimeType: String?): Boolean = normalize(mimeType)?.startsWith("image/") == true

    /**
     * Extension for a stored file. Prefers the MIME type, then the display
     * name's extension, and falls back to `img` so a file is never nameless.
     */
    fun extensionFor(mimeType: String?, displayName: String? = null): String {
        normalize(mimeType)?.let { extensionsByMime[it] }?.let { return it }
        val fromName = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
        if (fromName in mimesByExtension) return if (fromName == "jpeg") "jpg" else fromName
        return "img"
    }

    fun mimeForExtension(extension: String): String? = mimesByExtension[extension.lowercase()]
}
