package io.github.gameon223.memora.gallery

import kotlin.math.max
import kotlin.math.roundToInt

/** How to turn stored pixels upright, from the EXIF orientation tag. */
data class Orientation(val rotationDegrees: Int, val flipHorizontal: Boolean) {
    /** True when width and height trade places once upright. */
    val swapsDimensions: Boolean get() = rotationDegrees == 90 || rotationDegrees == 270

    val isIdentity: Boolean get() = rotationDegrees == 0 && !flipHorizontal

    companion object {
        val NORMAL = Orientation(0, false)

        /** EXIF orientation values 1 to 8. Anything else is treated as normal. */
        fun fromExif(value: Int): Orientation = when (value) {
            2 -> Orientation(0, true)
            3 -> Orientation(180, false)
            4 -> Orientation(180, true)
            5 -> Orientation(90, true)
            6 -> Orientation(90, false)
            7 -> Orientation(270, true)
            8 -> Orientation(270, false)
            else -> NORMAL
        }

        /** MediaStore stores orientation as degrees. */
        fun fromDegrees(degrees: Int): Orientation = when (((degrees % 360) + 360) % 360) {
            90 -> Orientation(90, false)
            180 -> Orientation(180, false)
            270 -> Orientation(270, false)
            else -> NORMAL
        }
    }
}

object ImageMath {
    /**
     * Largest power-of-two sample size that still leaves the long edge at
     * least [maxEdge] pixels, so decoding never goes below the target.
     */
    fun sampleSize(width: Int, height: Int, maxEdge: Int): Int {
        val longEdge = max(width, height)
        if (maxEdge <= 0 || longEdge <= maxEdge) return 1
        var sample = 1
        while (longEdge / (sample * 2) >= maxEdge) sample *= 2
        return sample
    }

    /** Size that fits [maxEdge] on the long edge, keeping the aspect ratio. */
    fun scaledSize(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
        val longEdge = max(width, height)
        if (maxEdge <= 0 || longEdge <= maxEdge) return width to height
        val scale = maxEdge.toDouble() / longEdge
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    /** Width and height as displayed, after applying [orientation]. */
    fun displaySize(width: Int, height: Int, orientation: Orientation): Pair<Int, Int> =
        if (orientation.swapsDimensions) height to width else width to height

    /**
     * Bitmap width to allocate for an `ImageReader` frame. Row stride can be
     * wider than `pixelStride * width`; the extra bytes are padding that has
     * to be cropped off after copying.
     */
    fun paddedBitmapWidth(width: Int, rowStride: Int, pixelStride: Int): Int {
        require(width > 0 && pixelStride > 0) { "Invalid frame geometry" }
        val rowPadding = rowStride - pixelStride * width
        require(rowPadding >= 0) { "Row stride is smaller than the frame" }
        return width + rowPadding / pixelStride
    }
}
