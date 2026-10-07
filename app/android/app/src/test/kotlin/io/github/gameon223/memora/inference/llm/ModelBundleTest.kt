package io.github.gameon223.memora.inference.llm

import java.io.File
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ModelBundleTest {
    @get:Rule
    val folder = TemporaryFolder()

    /** A file of [bytes] length starting with [head]. */
    private fun file(name: String, bytes: Int, head: ByteArray = ByteArray(4)): File {
        val target = folder.newFile(name)
        target.outputStream().use { out ->
            out.write(head)
            out.write(ByteArray((bytes - head.size).coerceAtLeast(0)))
        }
        return target
    }

    private val zipHead = byteArrayOf(0x50, 0x4B, 0x03, 0x04)

    @Test
    fun aZipOfAPlausibleSizePasses() {
        val model = file("gemma.task", (ModelBundle.MIN_BYTES + 1).toInt(), zipHead)
        assertNull(ModelBundle.check(model))
    }

    @Test
    fun theRealGemmaBundleIsAccepted() {
        // The exact first bytes of the Gemma 3 1B .task: four zeros, then
        // the zip header at offset 4. Matching at offset zero rejected a
        // perfectly good 529 MB model.
        val real = file(
            "gemma3-1b-it-int4.task",
            (ModelBundle.MIN_BYTES + 1).toInt(),
            byteArrayOf(
                0x00, 0x00, 0x00, 0x00,
                0x50, 0x4B, 0x03, 0x04,
                0x14, 0x00, 0x00, 0x00,
            ),
        )
        assertNull(ModelBundle.check(real))
    }

    @Test
    fun anArchiveFurtherInIsStillFound() {
        val padded = file(
            "gemma.task",
            (ModelBundle.MIN_BYTES + 1).toInt(),
            ByteArray(600) + byteArrayOf(0x50, 0x4B, 0x03, 0x04),
        )
        assertNull(ModelBundle.check(padded))
    }

    @Test
    fun anErrorPageIsCaughtBySize() {
        // What a gated download hands back when it goes wrong: a few KB of
        // HTML that would otherwise sit there looking like a model.
        val page = file("gemma.task", 3_000, "<!DO".toByteArray())
        val reason = ModelBundle.check(page)
        assertTrue(reason, reason!!.contains("too"))
        assertTrue(reason, reason.contains("KB"))
    }

    @Test
    fun aLargeFileWithNoArchiveAnywhereIsCaught() {
        // Zero-filled past the search window, so no header to find.
        val notZip = file("gemma.task", (ModelBundle.MIN_BYTES + 1).toInt(), "junk".toByteArray())
        val reason = ModelBundle.check(notZip)
        assertTrue(reason, reason!!.contains("zip"))
    }

    @Test
    fun litertlmIsNotExpectedToBeAZip() {
        val litertlm =
            file("gemma.litertlm", (ModelBundle.MIN_BYTES + 1).toInt(), "junk".toByteArray())
        assertNull(ModelBundle.check(litertlm))
    }

    @Test
    fun theMessageNamesWhatArrivedInstead() {
        val page = file("gemma.task", (ModelBundle.MIN_BYTES + 1).toInt(), "<!DOCTYPE htm".toByteArray())
        val reason = ModelBundle.check(page)!!

        // The whole point: say what the file is, not only what it is not.
        assertTrue(reason, reason.contains("<!DOCTYPE"))
        assertTrue(reason, reason.contains("MB"))
    }

    @Test
    fun unprintableBytesAreShownAsHex() {
        val gzip = file("gemma.task", (ModelBundle.MIN_BYTES + 1).toInt(), byteArrayOf(0x1f, 0x8b.toByte(), 0x08, 0x00))
        val reason = ModelBundle.check(gzip)!!

        assertTrue(reason, reason.contains("1f 8b"))
    }

    @Test
    fun aMissingFileSaysSo() {
        val reason = ModelBundle.check(File(folder.root, "nothing.task"))
        assertTrue(reason, reason!!.contains("not there"))
    }
}
