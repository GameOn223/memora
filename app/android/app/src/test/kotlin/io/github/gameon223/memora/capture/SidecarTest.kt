package io.github.gameon223.memora.capture

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SidecarTest {
    @Test
    fun roundTripsThroughJson() {
        val sidecar = CaptureSidecar(CaptureSidecar.SOURCE_SHARE, 1789000000000L, "a1b2.jpg")

        val parsed = CaptureSidecar.parse(sidecar.toJson(), "fallback.png")

        assertEquals(sidecar, parsed)
    }

    @Test
    fun writesTheDocumentedKeys() {
        val json = JSONObject(CaptureSidecar(CaptureSidecar.SOURCE_TILE, 42L, "x.png").toJson())

        assertEquals("tile", json.getString("source"))
        assertEquals(42L, json.getLong("captured_at_millis"))
        assertEquals("x.png", json.getString("file_name"))
    }

    @Test
    fun fillsInMissingFields() {
        val parsed = CaptureSidecar.parse("{}", "fallback.png")!!

        assertEquals(CaptureSidecar.SOURCE_TILE, parsed.source)
        assertEquals("fallback.png", parsed.fileName)
        // Zero means the caller should use the file's modified time.
        assertEquals(0L, parsed.capturedAtMillis)
    }

    @Test
    fun unknownSourcesCountAsTileCaptures() {
        val parsed = CaptureSidecar.parse("""{"source":"something-new"}""", "f.png")!!

        assertEquals(CaptureSidecar.SOURCE_TILE, parsed.source)
    }

    @Test
    fun rejectsBrokenJson() {
        assertNull(CaptureSidecar.parse("not json", "f.png"))
        assertNull(CaptureSidecar.parse("", "f.png"))
    }

    @Test
    fun readsEnabledAccessibilityServices() {
        val enabled = "com.other/.Service:io.github.gameon223.memora/" +
            "io.github.gameon223.memora.capture.CaptureAccessibilityService"

        assertTrue(
            AccessibilitySettings.isEnabled(
                enabled,
                "io.github.gameon223.memora",
                "io.github.gameon223.memora.capture.CaptureAccessibilityService",
            ),
        )
        // The system also stores the short form.
        assertTrue(
            AccessibilitySettings.isEnabled(
                "io.github.gameon223.memora/.capture.CaptureAccessibilityService",
                "io.github.gameon223.memora",
                "io.github.gameon223.memora.capture.CaptureAccessibilityService",
            ),
        )
        assertFalse(
            AccessibilitySettings.isEnabled(
                "com.other/.Service",
                "io.github.gameon223.memora",
                "io.github.gameon223.memora.capture.CaptureAccessibilityService",
            ),
        )
        assertFalse(AccessibilitySettings.isEnabled(null, "p", "p.C"))
        assertFalse(AccessibilitySettings.isEnabled("", "p", "p.C"))
    }
}
