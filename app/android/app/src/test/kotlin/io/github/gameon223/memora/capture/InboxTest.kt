package io.github.gameon223.memora.capture

import io.github.gameon223.memora.gallery.StoredImageFacts
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class InboxTest {
    private val root: File = Files.createTempDirectory("memora-inbox").toFile()
    private val inbox get() = File(root, Inbox.INBOX_DIR)
    private val originals get() = File(root, "originals")
    private val copies = AtomicInteger()

    @After
    fun cleanUp() {
        root.deleteRecursively()
    }

    private val facts: FactsReader = { StoredImageFacts("image/png", 1080, 2400, null) }

    private fun drain(now: Long = System.currentTimeMillis()) = runBlocking {
        Inbox.drain(root, facts, { "copy${copies.incrementAndGet()}" }, now)
    }

    private fun writeEntry(
        id: String,
        extension: String = "png",
        source: String = CaptureSidecar.SOURCE_TILE,
        capturedAt: Long = 1_700_000_000_000L,
        bytes: ByteArray = "a capture".toByteArray(),
        fileName: String? = null,
    ) {
        inbox.mkdirs()
        File(inbox, "$id.$extension").writeBytes(bytes)
        File(inbox, "$id${Inbox.SIDECAR_SUFFIX}")
            .writeText(CaptureSidecar(source, capturedAt, fileName ?: "$id.$extension").toJson())
    }

    @Test
    fun copiesIntoOriginalsAndKeepsTheEntryUntilConfirmed() {
        writeEntry("cap1")

        val items = drain()

        assertEquals(1, items.size)
        val item = items.single()
        assertEquals("cap1", item.id)
        assertEquals("originals/copy1.png", item.relativePath)
        assertEquals(CaptureSidecar.SOURCE_TILE, item.source)
        assertEquals(1_700_000_000_000L, item.capturedAtMillis)
        assertEquals("image/png", item.mimeType)
        assertEquals(1080L, item.width)
        assertEquals(2400L, item.height)
        assertEquals("a capture".toByteArray().size.toLong(), item.byteSize)
        assertTrue(File(originals, "copy1.png").isFile)
        // The capture is still in the inbox, because no row exists yet.
        assertTrue(File(inbox, "cap1.png").isFile)
        assertTrue(File(inbox, "cap1.json").isFile)
    }

    @Test
    fun anUnconfirmedCaptureComesBackWithAFreshCopy() {
        writeEntry("cap1")

        val first = drain().single()
        val second = drain().single()

        assertEquals("cap1", second.id)
        assertNotEquals(first.relativePath, second.relativePath)
        assertEquals(first.sha256, second.sha256)
        // The earlier copy is left alone: a memory may already point at it.
        assertTrue(File(originals, "copy1.png").isFile)
        assertTrue(File(originals, "copy2.png").isFile)
    }

    @Test
    fun confirmDropsTheEntryAndStopsTheReplay() {
        writeEntry("cap1")
        val item = drain().single()

        runBlocking { Inbox.confirm(root, listOf(item.id)) }

        assertFalse(File(inbox, "cap1.png").exists())
        assertFalse(File(inbox, "cap1.json").exists())
        assertTrue(File(originals, "copy1.png").isFile)
        assertTrue(drain().isEmpty())
    }

    @Test
    fun confirmLeavesOtherCapturesAlone() {
        writeEntry("cap1")
        writeEntry("cap2")
        drain()

        runBlocking { Inbox.confirm(root, listOf("cap1")) }

        assertFalse(File(inbox, "cap1.json").exists())
        assertTrue(File(inbox, "cap2.json").isFile)
        assertEquals(listOf("cap2"), drain().map { it.id })
    }

    @Test
    fun sharedImagesKeepTheirSourceAndExtension() {
        writeEntry("cap9", extension = "jpg", source = CaptureSidecar.SOURCE_SHARE)

        val item = drain().single()

        assertEquals(CaptureSidecar.SOURCE_SHARE, item.source)
        assertEquals("originals/copy1.jpg", item.relativePath)
    }

    @Test
    fun pairsByIdWhenTheSidecarNamesAMissingFile() {
        writeEntry("cap1", fileName = "gone.png")

        val items = drain()

        assertEquals(1, items.size)
        assertEquals("cap1", items.single().id)
    }

    @Test
    fun dropsASidecarWithNoImage() {
        inbox.mkdirs()
        File(inbox, "lonely.json")
            .writeText(CaptureSidecar(CaptureSidecar.SOURCE_TILE, 1L, "lonely.png").toJson())

        assertTrue(drain().isEmpty())
        assertFalse(File(inbox, "lonely.json").exists())
    }

    @Test
    fun dropsAnImageAndroidCannotRead() {
        writeEntry("broken")
        val failing: FactsReader = { throw IOException("Not a readable image") }

        val items = runBlocking { Inbox.drain(root, failing, { "copy" }) }

        assertTrue(items.isEmpty())
        assertFalse(File(inbox, "broken.png").exists())
        assertFalse(File(inbox, "broken.json").exists())
    }

    @Test
    fun sweepsUnpairedFilesOlderThanADay() {
        inbox.mkdirs()
        val orphan = File(inbox, "old.png").apply { writeBytes(byteArrayOf(1)) }
        val fresh = File(inbox, "new.png").apply { writeBytes(byteArrayOf(1)) }
        val part = File(inbox, "half.png.part").apply { writeBytes(byteArrayOf(1)) }
        writeEntry("kept")
        val twoDays = 2 * 24 * 60 * 60 * 1000L
        orphan.setLastModified(System.currentTimeMillis() - twoDays)
        part.setLastModified(System.currentTimeMillis() - twoDays)

        drain()

        assertFalse(orphan.exists())
        assertFalse(part.exists())
        assertTrue(fresh.isFile)
        assertTrue(File(inbox, "kept.png").isFile)
    }

    @Test
    fun keepsAPairedImageHoweverOldItIs() {
        writeEntry("cap1")
        val twoDays = 2 * 24 * 60 * 60 * 1000L
        File(inbox, "cap1.png").setLastModified(System.currentTimeMillis() - twoDays)

        drain()

        assertTrue(File(inbox, "cap1.png").isFile)
    }
}
