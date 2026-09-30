package io.github.gameon223.memora.files

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SafePathsTest {
    private val root: File = Files.createTempDirectory("memora-files").toFile()

    @After
    fun cleanUp() {
        root.deleteRecursively()
    }

    @Test
    fun resolvesRelativePathsInsideRoot() {
        val file = SafePaths.resolve(root, "originals/a.png")

        assertEquals(File(root, "originals/a.png").canonicalPath, file.canonicalPath)
    }

    @Test
    fun refusesEscapes() {
        assertThrows { SafePaths.resolve(root, "../databases/memora.db") }
        assertThrows { SafePaths.resolve(root, "originals/../../x") }
        assertThrows { SafePaths.resolve(root, "/etc/hosts") }
        assertThrows { SafePaths.resolve(root, " ") }
    }

    @Test
    fun checksContainment() {
        val sibling = File(root.parentFile, root.name + "-other")

        assertTrue(SafePaths.isInside(File(root, "inbox/x.png"), root))
        assertTrue(SafePaths.isInside(root, root))
        assertFalse(SafePaths.isInside(sibling, root))
    }

    private fun assertThrows(block: () -> Unit) {
        val threw = try {
            block()
            false
        } catch (expected: IllegalArgumentException) {
            true
        }
        assertTrue("Expected IllegalArgumentException", threw)
    }
}
