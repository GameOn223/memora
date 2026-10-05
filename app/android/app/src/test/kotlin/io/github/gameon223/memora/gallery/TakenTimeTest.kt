package io.github.gameon223.memora.gallery

import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TakenTimeTest {
    private val kolkata = ZoneId.of("Asia/Kolkata")

    @Test
    fun parsesExifDateInTheDeviceZone() {
        val expected = ZonedDateTime.of(2026, 8, 14, 9, 30, 5, 0, kolkata).toInstant().toEpochMilli()

        assertEquals(expected, ExifDates.parse("2026:08:14 09:30:05", null, kolkata))
    }

    @Test
    fun prefersTheExifOffsetWhenPresent() {
        val expected = ZonedDateTime.of(2026, 8, 14, 9, 30, 5, 0, ZoneId.of("+02:00"))
            .toInstant().toEpochMilli()

        assertEquals(expected, ExifDates.parse("2026:08:14 09:30:05", "+02:00", kolkata))
    }

    @Test
    fun acceptsDashesAndSubseconds() {
        val expected = ZonedDateTime.of(2026, 1, 2, 3, 4, 5, 0, kolkata).toInstant().toEpochMilli()

        assertEquals(expected, ExifDates.parse("2026-01-02 03:04:05.123", null, kolkata))
    }

    @Test
    fun rejectsBlankZeroedAndInvalidValues() {
        assertNull(ExifDates.parse(null, null, kolkata))
        assertNull(ExifDates.parse("", null, kolkata))
        assertNull(ExifDates.parse("0000:00:00 00:00:00", null, kolkata))
        assertNull(ExifDates.parse("2026:13:40 25:61:00", null, kolkata))
        assertNull(ExifDates.parse("yesterday", null, kolkata))
    }

    @Test
    fun ignoresAMalformedOffset() {
        val expected = ZonedDateTime.of(2026, 8, 14, 9, 30, 5, 0, kolkata).toInstant().toEpochMilli()

        assertEquals(expected, ExifDates.parse("2026:08:14 09:30:05", "local", kolkata))
    }

    @Test
    fun choosesTheFirstKnownTime() {
        assertEquals(100L, TakenTime.choose(100L, 200L, 300L, 400L))
        assertEquals(200L, TakenTime.choose(null, 200L, 300L, 400L))
        assertEquals(300L, TakenTime.choose(0L, null, 300L, 400L))
        assertEquals(400L, TakenTime.choose(null, -5L, null, 400L))
    }
}
