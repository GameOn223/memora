package io.github.gameon223.memora.inference

import org.junit.Assert.assertEquals
import org.junit.Test

class PoolingTest {
    @Test
    fun takesTheClsTokenOfEveryRowAndNormalizes() {
        // Two rows, three tokens each, two dimensions. Only the first token
        // of each row is used.
        val values = floatArrayOf(
            3f, 4f, 9f, 9f, 9f, 9f,
            0f, 5f, 1f, 1f, 1f, 1f,
        )

        val out = Pooling.clsNormalized(values, rows = 2, sequenceLength = 3, dimensions = 2)

        assertEquals(4, out.size)
        assertEquals(0.6, out[0], 1e-9)
        assertEquals(0.8, out[1], 1e-9)
        assertEquals(0.0, out[2], 1e-9)
        assertEquals(1.0, out[3], 1e-9)
    }

    @Test
    fun leavesAZeroVectorAlone() {
        val out = Pooling.clsNormalized(floatArrayOf(0f, 0f), rows = 1, sequenceLength = 1, dimensions = 2)

        assertEquals(0.0, out[0], 1e-9)
        assertEquals(0.0, out[1], 1e-9)
    }

    @Test(expected = IllegalArgumentException::class)
    fun refusesOutputThatIsTooSmall() {
        Pooling.clsNormalized(floatArrayOf(1f, 2f), rows = 2, sequenceLength = 3, dimensions = 2)
    }
}
