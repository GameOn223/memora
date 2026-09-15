package io.github.gameon223.memora.gallery

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Size and SHA-256 of bytes that were copied or read. */
data class HashedBytes(val sha256: String, val byteCount: Long)

object Hashing {
    private const val BUFFER_BYTES = 64 * 1024

    /** Copies [input] to [output] and hashes the bytes on the way through. */
    fun copy(input: InputStream, output: OutputStream): HashedBytes {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(BUFFER_BYTES)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            if (read == 0) continue
            output.write(buffer, 0, read)
            digest.update(buffer, 0, read)
            total += read
        }
        output.flush()
        return HashedBytes(hex(digest.digest()), total)
    }

    fun hashFile(file: File): HashedBytes = file.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(BUFFER_BYTES)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
            total += read
        }
        HashedBytes(hex(digest.digest()), total)
    }

    fun hex(bytes: ByteArray): String {
        val chars = CharArray(bytes.size * 2)
        for (i in bytes.indices) {
            val value = bytes[i].toInt() and 0xff
            chars[i * 2] = HEX[value ushr 4]
            chars[i * 2 + 1] = HEX[value and 0x0f]
        }
        return String(chars)
    }

    private val HEX = "0123456789abcdef".toCharArray()
}
