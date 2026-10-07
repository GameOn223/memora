package io.github.gameon223.memora.inference.llm

import java.io.File

/**
 * Whether a file is plausibly a model bundle before anything tries to load
 * it.
 *
 * A `.task` holds a zip archive. MediaPipe answers anything else with
 * "Unable to open zip archive" from deep inside `createFromOptions`, minutes
 * after the download that caused it, which is a miserable way to find out. A
 * gated download is the likely source: an error page, a login page or a
 * transfer that stopped early all arrive looking like a file.
 *
 * The archive is not always at the very start. The Gemma 3 1B bundle begins
 * `00 00 00 00` and the zip header follows at offset 4, so the first bytes
 * are searched rather than matched. Being strict about offset zero rejected
 * a perfectly good 529 MB model.
 *
 * `.litertlm` is not a zip, so it is only checked for a plausible size.
 */
object ModelBundle {
    /** Local file header of a zip entry: `PK\u0003\u0004`. */
    private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B, 0x03, 0x04)

    /**
     * How far in to look for the archive. Generous: the point is to tell a
     * model apart from an error page, not to police the container format.
     */
    const val HEADER_WINDOW = 4096

    /**
     * Smallest file worth trying. The smallest model in the catalog is about
     * 550 MB, and an error page or a login page is a few kilobytes, so
     * anything under this is not a model however it is shaped.
     */
    const val MIN_BYTES = 16L * 1024 * 1024

    /** Why [check] refused, or null when the file looks fine. */
    fun check(file: File): String? {
        if (!file.isFile) return "The file is not there."
        val length = file.length()
        if (length < MIN_BYTES) {
            return "The file is only ${length / 1024} KB, which is far too " +
                "small to be a model. The download probably returned a page " +
                "instead of the weights."
        }
        if (ModelFileNames.extensionOf(file.name) == "task" && !holdsZip(file)) {
            // The first bytes say what it is instead: "<!DOCTYPE" for an
            // error page, "{" for a refusal in JSON, "version http" for a
            // Git LFS pointer. Without them this is a dead end.
            return "The file is not a .task bundle: a .task holds a zip " +
                "archive and no archive was found in this one, which is " +
                "${describe(length)} starting with ${head(file)}."
        }
        return null
    }

    /** Size in the units a person reads. */
    private fun describe(bytes: Long): String {
        val mb = bytes / (1024.0 * 1024.0)
        return if (mb >= 1024) {
            String.format(java.util.Locale.US, "%.1f GB", mb / 1024)
        } else {
            String.format(java.util.Locale.US, "%.0f MB", mb)
        }
    }

    /**
     * The first bytes, as text where they are printable and as hex where
     * they are not, so the message names what arrived.
     */
    internal fun head(file: File, count: Int = 12): String {
        val bytes = try {
            file.inputStream().use { input ->
                val buffer = ByteArray(count)
                val read = input.read(buffer)
                if (read <= 0) return "nothing" else buffer.copyOf(read)
            }
        } catch (error: Exception) {
            return "unreadable bytes"
        }
        val printable = bytes.all { it >= 0x20 && it < 0x7F }
        return if (printable) {
            "text, \"" + String(bytes, Charsets.US_ASCII) + "\""
        } else {
            "bytes " + bytes.joinToString(" ") { String.format("%02x", it) }
        }
    }

    /** Whether a zip header appears within the first [HEADER_WINDOW] bytes. */
    private fun holdsZip(file: File): Boolean = try {
        file.inputStream().use { input ->
            val window = ByteArray(HEADER_WINDOW)
            val read = input.read(window)
            read >= ZIP_MAGIC.size && indexOfMagic(window, read) >= 0
        }
    } catch (error: Exception) {
        false
    }

    /** Where [ZIP_MAGIC] starts inside the first [read] bytes, or -1. */
    private fun indexOfMagic(window: ByteArray, read: Int): Int {
        for (start in 0..read - ZIP_MAGIC.size) {
            var matched = true
            for (i in ZIP_MAGIC.indices) {
                if (window[start + i] != ZIP_MAGIC[i]) {
                    matched = false
                    break
                }
            }
            if (matched) return start
        }
        return -1
    }
}
