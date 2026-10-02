package io.github.gameon223.memora.inference

import kotlin.math.sqrt

/** Turns model output into one vector per input. */
object Pooling {
    /**
     * Reads the vector size from the output shape, which has to be
     * `[batch, sequence, dim]`. A model whose first output is already pooled
     * has a different rank, and guessing the size from the element count
     * would store nonsense under a model id that claims otherwise.
     */
    fun dimensionsFrom(shape: LongArray, rows: Int, sequenceLength: Int): Int {
        require(shape.size == 3) {
            "Expected a [batch, sequence, dim] output, got rank ${shape.size}"
        }
        require(shape[0].toInt() == rows) {
            "Model returned ${shape[0]} rows for $rows inputs"
        }
        require(shape[1].toInt() == sequenceLength) {
            "Model returned ${shape[1]} tokens for $sequenceLength"
        }
        val dimensions = shape[2].toInt()
        require(dimensions > 0) { "Model returned empty vectors" }
        return dimensions
    }

    /**
     * Takes the `[CLS]` token of every row from a `[batch, sequence, dim]`
     * tensor and L2-normalizes it, which is what bge-small-en expects.
     */
    fun clsNormalized(values: FloatArray, rows: Int, sequenceLength: Int, dimensions: Int): DoubleArray {
        require(rows > 0 && sequenceLength > 0 && dimensions > 0) { "Empty model output" }
        require(values.size >= rows * sequenceLength * dimensions) { "Model output is too small" }
        val out = DoubleArray(rows * dimensions)
        for (row in 0 until rows) {
            val source = row * sequenceLength * dimensions
            val target = row * dimensions
            var squared = 0.0
            for (index in 0 until dimensions) {
                val value = values[source + index].toDouble()
                out[target + index] = value
                squared += value * value
            }
            val length = sqrt(squared)
            if (length > 0) {
                for (index in 0 until dimensions) out[target + index] /= length
            }
        }
        return out
    }
}
