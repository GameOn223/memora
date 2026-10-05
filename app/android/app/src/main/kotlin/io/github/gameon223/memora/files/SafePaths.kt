package io.github.gameon223.memora.files

import java.io.File

/** Guards file access to app-private directories. */
object SafePaths {
    /**
     * Resolves [relative] under [root]. Throws for absolute paths and for
     * anything that would escape [root], such as `../databases`.
     */
    fun resolve(root: File, relative: String): File {
        require(relative.isNotBlank()) { "Empty path" }
        val normalized = relative.replace('\\', '/')
        require(!normalized.startsWith("/")) { "Path must be relative" }
        require(normalized.split('/').none { it == ".." }) { "Path must stay inside app storage" }
        val file = File(root, normalized)
        require(isInside(file, root)) { "Path must stay inside app storage" }
        return file
    }

    /** True when [file] is [root] itself or somewhere below it. */
    fun isInside(file: File, root: File): Boolean {
        val rootPath = root.canonicalPath
        val filePath = file.canonicalPath
        return filePath == rootPath || filePath.startsWith(rootPath + File.separator)
    }

    /** Requires [file] to live under one of [roots]. */
    fun requireInside(file: File, roots: List<File>): File {
        require(roots.any { isInside(file, it) }) { "Path must stay inside app storage" }
        return file
    }
}
