package io.github.gameon223.memora.inference

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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

    @Test
    fun readsTheVectorSizeFromTheOutputShape() {
        val dimensions = Pooling.dimensionsFrom(longArrayOf(2, 512, 384), rows = 2, sequenceLength = 512)

        assertEquals(384, dimensions)
    }

    @Test
    fun refusesAnAlreadyPooledOutput() {
        // A [batch, dim] output means the model pooled for us, and reading
        // the first 384 floats of that is a different vector space.
        assertRejects { Pooling.dimensionsFrom(longArrayOf(2, 384), rows = 2, sequenceLength = 512) }
    }

    @Test
    fun refusesAShapeThatDoesNotMatchTheBatch() {
        assertRejects { Pooling.dimensionsFrom(longArrayOf(1, 512, 384), rows = 2, sequenceLength = 512) }
        assertRejects { Pooling.dimensionsFrom(longArrayOf(2, 128, 384), rows = 2, sequenceLength = 512) }
        assertRejects { Pooling.dimensionsFrom(longArrayOf(2, 512, 0), rows = 2, sequenceLength = 512) }
    }

    private fun assertRejects(block: () -> Unit) {
        val threw = try {
            block()
            false
        } catch (expected: IllegalArgumentException) {
            true
        }
        assertTrue("Expected the shape to be refused", threw)
    }
}
