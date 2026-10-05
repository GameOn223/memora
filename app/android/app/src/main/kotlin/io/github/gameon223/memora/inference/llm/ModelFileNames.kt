package io.github.gameon223.memora.inference.llm

/**
 * Names and extensions for model files the user brings in. Kept free of
 * Android types so the rules can be unit tested.
 */
object ModelFileNames {
    /** Imported files live here, relative to the app files directory. */
    const val IMPORTED_DIR = "models/imported"

    /**
     * What MediaPipe LLM Inference can open. `.task` and `.litertlm` are the
     * two bundle formats; `.bin` is the older single-file name that some
     * conversions still produce.
     */
    val allowedExtensions: Set<String> = setOf("task", "litertlm", "bin")

    /** Lowercased extension without the dot, or null when there isn't one. */
    fun extensionOf(fileName: String): String? {
        val dot = fileName.lastIndexOf('.')
        if (dot <= 0 || dot == fileName.length - 1) return null
        return fileName.substring(dot + 1).lowercase()
    }

    fun isSupported(fileName: String): Boolean = extensionOf(fileName) in allowedExtensions

    /**
     * Throws with a message the settings screen can show as is when
     * [fileName] isn't a model file Memora can open.
     */
    fun requireSupported(fileName: String) {
        if (isSupported(fileName)) return
        val allowed = allowedExtensions.sorted().joinToString(", ") { ".$it" }
        throw IllegalArgumentException(
            "Memora can only open $allowed model files. \"$fileName\" is not one of them.",
        )
    }

    /**
     * A file name that is safe to write into app storage. Keeps the stem and
     * the extension, drops directory separators and anything else that could
     * surprise the file system, and never returns an empty stem.
     */
    fun sanitize(displayName: String?): String {
        val raw = displayName.orEmpty().replace('\\', '/').substringAfterLast('/').trim()
        val extension = extensionOf(raw)
        val stem = if (extension == null) raw else raw.substring(0, raw.length - extension.length - 1)
        val cleaned = stem
            .map { if (it.isLetterOrDigit() || it == '-' || it == '_' || it == '.') it else '-' }
            .joinToString("")
            .trim('.', '-')
            .take(MAX_STEM)
        val safeStem = cleaned.ifEmpty { "model" }
        return if (extension == null) safeStem else "$safeStem.$extension"
    }

    /**
     * [fileName] if nothing in [taken] uses it, otherwise the same name with
     * a counter before the extension.
     */
    fun deduplicate(fileName: String, taken: Set<String>): String {
        if (fileName !in taken) return fileName
        val extension = extensionOf(fileName)
        val stem = if (extension == null) fileName else fileName.dropLast(extension.length + 1)
        var counter = 2
        while (true) {
            val candidate = if (extension == null) "$stem-$counter" else "$stem-$counter.$extension"
            if (candidate !in taken) return candidate
            counter++
        }
    }

    /** Where [fileName] lives, relative to the app files directory. */
    fun relativePath(fileName: String): String = "$IMPORTED_DIR/$fileName"

    /**
     * True when [relativePath] names a file directly inside
     * [IMPORTED_DIR]. Deleting and loading only accept these, so a path from
     * Dart can never reach the database or an original image.
     */
    fun isImportedPath(relativePath: String): Boolean {
        val normalized = relativePath.replace('\\', '/')
        if (!normalized.startsWith("$IMPORTED_DIR/")) return false
        val name = normalized.removePrefix("$IMPORTED_DIR/")
        return name.isNotEmpty() && !name.contains('/') && name != "." && name != ".."
    }

    private const val MAX_STEM = 96
}
