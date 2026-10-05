package io.github.gameon223.memora.gallery

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageMathTest {
    @Test
    fun sampleSizeNeverDecodesBelowTheTarget() {
        assertEquals(1, ImageMath.sampleSize(400, 300, 512))
        assertEquals(1, ImageMath.sampleSize(1000, 800, 512))
        assertEquals(4, ImageMath.sampleSize(1080, 2400, 512))
        assertEquals(8, ImageMath.sampleSize(4096, 3072, 512))
        assertEquals(1, ImageMath.sampleSize(4096, 3072, 0))
    }

    @Test
    fun scaledSizeKeepsAspectRatio() {
        assertEquals(230 to 512, ImageMath.scaledSize(1080, 2400, 512))
        assertEquals(512 to 384, ImageMath.scaledSize(4096, 3072, 512))
        assertEquals(300 to 200, ImageMath.scaledSize(300, 200, 512))
        assertEquals(1 to 512, ImageMath.scaledSize(2, 4000, 512))
    }

    @Test
    fun mapsExifOrientation() {
        assertTrue(Orientation.fromExif(1).isIdentity)
        assertEquals(Orientation(90, false), Orientation.fromExif(6))
        assertEquals(Orientation(270, false), Orientation.fromExif(8))
        assertEquals(Orientation(180, true), Orientation.fromExif(4))
        assertEquals(Orientation(90, true), Orientation.fromExif(5))
        assertTrue(Orientation.fromExif(99).isIdentity)
        assertEquals(Orientation(270, false), Orientation.fromDegrees(-90))
    }

    @Test
    fun displaySizeSwapsForQuarterTurns() {
        assertEquals(3000 to 4000, ImageMath.displaySize(4000, 3000, Orientation.fromExif(6)))
        assertEquals(4000 to 3000, ImageMath.displaySize(4000, 3000, Orientation.fromExif(3)))
        assertFalse(Orientation.fromExif(2).swapsDimensions)
    }

    @Test
    fun paddedWidthCoversRowStride() {
        // 1080 px wide RGBA frame with no padding.
        assertEquals(1080, ImageMath.paddedBitmapWidth(1080, 4320, 4))
        // 16 bytes of padding per row is 4 extra pixels.
        assertEquals(1084, ImageMath.paddedBitmapWidth(1080, 4336, 4))
    }

    @Test(expected = IllegalArgumentException::class)
    fun paddedWidthRejectsImpossibleStride() {
        ImageMath.paddedBitmapWidth(1080, 4000, 4)
    }

    @Test
    fun hashingCopiesAndHashes() {
        val out = ByteArrayOutputStream()

        val hashed = Hashing.copy(ByteArrayInputStream("memora".toByteArray()), out)

        assertEquals("92a3ab086cf61bf313954c3e341c163756e536973f204ef1e732cbf550878111", hashed.sha256)
        assertEquals(6L, hashed.byteCount)
        assertArrayEquals("memora".toByteArray(), out.toByteArray())
    }

    @Test
    fun hashesFiles() {
        val file: File = Files.createTempFile("memora", ".bin").toFile()
        try {
            file.writeBytes(ByteArray(0))
            assertEquals(
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                Hashing.hashFile(file).sha256,
            )
        } finally {
            file.delete()
        }
    }
}
