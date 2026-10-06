package io.github.gameon223.memora.inference.llm

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelCopyTest {
    @Test
    fun copiesTheWholeStream() {
        val source = ByteArray(ModelCopy.BUFFER_BYTES * 2 + 17) { (it % 251).toByte() }
        val out = ByteArrayOutputStream()

        val copied = ModelCopy.copy(ByteArrayInputStream(source), out, source.size.toLong()) {}

        assertEquals(source.size.toLong(), copied)
        assertArrayEquals(source, out.toByteArray())
    }

    @Test
    fun anEmptySourceCopiesNothingAndReportsZeroOnce() {
        val reports = mutableListOf<Long>()

        val copied =
            ModelCopy.copy(ByteArrayInputStream(ByteArray(0)), ByteArrayOutputStream(), 0L) {
                reports.add(it)
            }

        assertEquals(0L, copied)
        assertEquals(listOf(0L), reports)
    }

    @Test
    fun aSmallFileReportsOnceAtTheEnd() {
        val source = ByteArray(4096)
        val reports = mutableListOf<Long>()

        ModelCopy.copy(ByteArrayInputStream(source), ByteArrayOutputStream(), source.size.toLong()) {
            reports.add(it)
        }

        assertEquals(listOf(4096L), reports)
    }

    @Test
    fun theLastReportIsTheFullCount() {
        val source = ByteArray(ModelCopy.BUFFER_BYTES * 3)
        val reports = mutableListOf<Long>()

        ModelCopy.copy(ByteArrayInputStream(source), ByteArrayOutputStream(), source.size.toLong()) {
            reports.add(it)
        }

        assertEquals(source.size.toLong(), reports.last())
    }

    @Test
    fun aThreeGigabyteFileReportsAboutAHundredTimesNotEveryBuffer() {
        val total = 3L shl 30
        val reports = mutableListOf<Long>()
        val reporter = ModelCopy.Reporter(total) { reports.add(it) }

        var copied = 0L
        while (copied < total) {
            copied += ModelCopy.BUFFER_BYTES
            reporter.copied(copied)
        }
        reporter.finished(copied)

        assertTrue("reported ${reports.size} times", reports.size in 90..110)
        assertEquals(total, reports.last())
    }

    @Test
    fun reportsClimbAndNeverRepeatACount() {
        val reports = mutableListOf<Long>()
        val reporter = ModelCopy.Reporter(600L shl 20) { reports.add(it) }

        var copied = 0L
        repeat(600) {
            copied += 1L shl 20
            reporter.copied(copied)
        }
        reporter.finished(copied)

        assertEquals(reports.sorted(), reports)
        assertEquals(reports.distinct(), reports)
    }

    @Test
    fun aFileOfUnknownSizeStillReportsAsItGoes() {
        val reports = mutableListOf<Long>()
        val reporter = ModelCopy.Reporter(0L) { reports.add(it) }

        var copied = 0L
        repeat(40) {
            copied += 1L shl 20
            reporter.copied(copied)
        }
        reporter.finished(copied)

        // One per 8 MB step, and the closing count lands on a step as well.
        assertEquals(5, reports.size)
        assertEquals(40L shl 20, reports.last())
    }
}
