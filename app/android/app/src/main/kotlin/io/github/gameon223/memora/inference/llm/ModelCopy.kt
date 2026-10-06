package io.github.gameon223.memora.inference.llm

import java.io.InputStream
import java.io.OutputStream

/**
 * Copies a picked model file across, reporting how far it has got.
 *
 * A model runs from half a gigabyte to three, so the copy takes minutes and
 * has to say something while it runs. It must not say it on every buffer
 * either: three thousand events for one import would cost more than the copy.
 * So reports are spaced out by [REPORT_STEP_BYTES], or by a hundredth of the
 * file when that is larger, and the last byte always reports.
 */
object ModelCopy {
    const val BUFFER_BYTES = 1 shl 20

    /** Smallest gap between two reports. */
    const val REPORT_STEP_BYTES = 8L shl 20

    /**
     * Streams [input] into [output] and returns the number of bytes copied,
     * handing [report] a running count. [totalBytes] is what the source
     * claimed, or zero when it would not say.
     */
    fun copy(
        input: InputStream,
        output: OutputStream,
        totalBytes: Long,
        report: (Long) -> Unit,
    ): Long {
        val reporter = Reporter(totalBytes, report)
        val buffer = ByteArray(BUFFER_BYTES)
        var copied = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            output.write(buffer, 0, read)
            copied += read
            reporter.copied(copied)
        }
        reporter.finished(copied)
        return copied
    }

    /** Decides which byte counts are worth reporting. */
    class Reporter(totalBytes: Long, private val report: (Long) -> Unit) {
        private val step = maxOf(REPORT_STEP_BYTES, totalBytes / REPORTS_PER_FILE)
        private var nextAt = step
        private var last = -1L

        /** Reports [copied] if it has moved far enough since the last one. */
        fun copied(copied: Long) {
            if (copied < nextAt) return
            emit(copied)
            nextAt = copied + step
        }

        /** Reports the final count, unless it has just been reported. */
        fun finished(copied: Long) = emit(copied)

        private fun emit(copied: Long) {
            if (copied == last) return
            last = copied
            report(copied)
        }

        private companion object {
            const val REPORTS_PER_FILE = 100
        }
    }
}
