package io.github.gameon223.memora.inference.llm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelFileNamesTest {
    @Test
    fun acceptsTheThreeModelExtensions() {
        assertTrue(ModelFileNames.isSupported("gemma-3-1b-it-int4.task"))
        assertTrue(ModelFileNames.isSupported("gemma-3n-E2B-it-int4.litertlm"))
        assertTrue(ModelFileNames.isSupported("model.bin"))
    }

    @Test
    fun extensionCheckIgnoresCase() {
        assertTrue(ModelFileNames.isSupported("Gemma.TASK"))
        assertTrue(ModelFileNames.isSupported("Gemma.LiteRTLM"))
    }

    @Test
    fun refusesAnythingElse() {
        assertFalse(ModelFileNames.isSupported("holiday.jpg"))
        assertFalse(ModelFileNames.isSupported("model.gguf"))
        assertFalse(ModelFileNames.isSupported("model.tflite"))
        assertFalse(ModelFileNames.isSupported("model.zip"))
        assertFalse(ModelFileNames.isSupported("README"))
        assertFalse(ModelFileNames.isSupported(""))
        assertFalse(ModelFileNames.isSupported(".task"))
        assertFalse(ModelFileNames.isSupported("model."))
    }

    @Test
    fun refusesAHalfCopiedFile() {
        // The copy writes `<name>.part` and renames it. A listing that picked
        // the part file up would offer an incomplete model.
        assertFalse(ModelFileNames.isSupported("gemma.task.part"))
    }

    @Test
    fun theRefusalNamesWhatIsAllowed() {
        val message = try {
            ModelFileNames.requireSupported("model.gguf")
            ""
        } catch (error: IllegalArgumentException) {
            error.message.orEmpty()
        }

        assertTrue(message, message.contains(".task"))
        assertTrue(message, message.contains(".litertlm"))
        assertTrue(message, message.contains(".bin"))
        assertTrue(message, message.contains("model.gguf"))
    }

    @Test
    fun sanitizeKeepsAUsableNameAndDropsDirectories() {
        assertEquals("gemma-3-1b-it-int4.task", ModelFileNames.sanitize("gemma-3-1b-it-int4.task"))
        assertEquals("gemma.task", ModelFileNames.sanitize("/sdcard/Download/gemma.task"))
        assertEquals("gemma.task", ModelFileNames.sanitize("..\\..\\gemma.task"))
        assertEquals("my-model.litertlm", ModelFileNames.sanitize("my model.litertlm"))
        assertEquals("a-b.task", ModelFileNames.sanitize("a:b.task"))
    }

    @Test
    fun sanitizeNeverReturnsAnEmptyStem() {
        assertEquals("model", ModelFileNames.sanitize(null))
        assertEquals("model", ModelFileNames.sanitize("   "))
        assertEquals("model.task", ModelFileNames.sanitize("---.task"))
    }

    @Test
    fun aDotFileHasNoExtensionAndIsRefused() {
        // `.task` is a hidden file called "task", not a model bundle.
        val name = ModelFileNames.sanitize(".task")

        assertEquals("task", name)
        assertFalse(ModelFileNames.isSupported(name))
    }

    @Test
    fun deduplicateCountsUpBeforeTheExtension() {
        val taken = setOf("gemma.task", "gemma-2.task")

        assertEquals("gemma-3.task", ModelFileNames.deduplicate("gemma.task", taken))
        assertEquals("other.task", ModelFileNames.deduplicate("other.task", taken))
    }

    @Test
    fun importedPathsStayInOneFolder() {
        assertTrue(ModelFileNames.isImportedPath("models/imported/gemma.task"))
        assertEquals(
            "models/imported/gemma.task",
            ModelFileNames.relativePath("gemma.task"),
        )
    }

    @Test
    fun importedPathRefusesAnythingThatLeavesTheFolder() {
        assertFalse(ModelFileNames.isImportedPath("models/imported/../../databases/memora.db"))
        assertFalse(ModelFileNames.isImportedPath("models/imported/sub/gemma.task"))
        assertFalse(ModelFileNames.isImportedPath("models/imported/"))
        assertFalse(ModelFileNames.isImportedPath("models/bge-small-en-v1.5/model.onnx"))
        assertFalse(ModelFileNames.isImportedPath("originals/a.png"))
        assertFalse(ModelFileNames.isImportedPath("/data/data/other/models/imported/gemma.task"))
        assertFalse(ModelFileNames.isImportedPath(""))
    }

    @Test
    fun importedPathTreatsBackslashesAsSeparators() {
        assertFalse(ModelFileNames.isImportedPath("models\\imported\\sub\\gemma.task"))
        assertTrue(ModelFileNames.isImportedPath("models\\imported\\gemma.task"))
    }
}
