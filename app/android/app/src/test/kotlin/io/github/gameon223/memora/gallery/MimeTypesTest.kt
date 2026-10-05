package io.github.gameon223.memora.gallery

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MimeTypesTest {
    @Test
    fun mapsKnownMimeTypesToExtensions() {
        assertEquals("jpg", MimeTypes.extensionFor("image/jpeg"))
        assertEquals("png", MimeTypes.extensionFor("image/png"))
        assertEquals("webp", MimeTypes.extensionFor("image/webp"))
        assertEquals("heic", MimeTypes.extensionFor("image/heic"))
        assertEquals("gif", MimeTypes.extensionFor("Image/GIF; charset=binary"))
    }

    @Test
    fun fallsBackToDisplayNameThenGenericExtension() {
        assertEquals("jpg", MimeTypes.extensionFor(null, "IMG_2041.JPEG"))
        assertEquals("png", MimeTypes.extensionFor("application/octet-stream", "shot.png"))
        assertEquals("img", MimeTypes.extensionFor("image/x-unknown", "noextension"))
        assertEquals("img", MimeTypes.extensionFor(null, null))
    }

    @Test
    fun normalizesAndRecognizesImages() {
        assertEquals("image/png", MimeTypes.normalize(" IMAGE/PNG ;q=1"))
        assertNull(MimeTypes.normalize("  "))
        assertTrue(MimeTypes.isImage("image/avif"))
        assertFalse(MimeTypes.isImage("video/mp4"))
        assertFalse(MimeTypes.isImage(null))
        assertEquals("image/jpeg", MimeTypes.mimeForExtension("JPG"))
        assertNull(MimeTypes.mimeForExtension("txt"))
    }
}
