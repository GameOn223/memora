package io.github.gameon223.memora.background

import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleMathTest {
    private val kolkata = ZoneId.of("Asia/Kolkata")
    private val london = ZoneId.of("Europe/London")

    private fun millis(zone: ZoneId, year: Int, month: Int, day: Int, hour: Int, minute: Int = 0): Long =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, zone).toInstant().toEpochMilli()

    private val hour = 60 * 60 * 1000L
    private val minute = 60 * 1000L

    @Test
    fun immediateModeNeverWaits() {
        val now = millis(kolkata, 2026, 9, 15, 12)

        assertEquals(0L, ScheduleMath.initialDelayMillis(now, kolkata, 60, 420, immediate = true))
    }

    @Test
    fun insideTheWindowStartsNow() {
        val now = millis(kolkata, 2026, 9, 15, 3, 30)

        assertEquals(0L, ScheduleMath.initialDelayMillis(now, kolkata, 60, 420, immediate = false))
    }

    @Test
    fun waitsForTodaysWindowBeforeItOpens() {
        val now = millis(kolkata, 2026, 9, 15, 0, 30)

        assertEquals(30 * minute, ScheduleMath.initialDelayMillis(now, kolkata, 60, 420, immediate = false))
    }

    @Test
    fun waitsForTomorrowsWindowAfterItCloses() {
        val now = millis(kolkata, 2026, 9, 15, 12)

        assertEquals(13 * hour, ScheduleMath.initialDelayMillis(now, kolkata, 60, 420, immediate = false))
    }

    @Test
    fun windowEndIsExclusive() {
        val now = millis(kolkata, 2026, 9, 15, 7)

        assertEquals(18 * hour, ScheduleMath.initialDelayMillis(now, kolkata, 60, 420, immediate = false))
    }

    @Test
    fun handlesWindowsThatCrossMidnight() {
        // 23:00 to 06:00.
        assertEquals(0L, ScheduleMath.initialDelayMillis(millis(kolkata, 2026, 9, 15, 23, 30), kolkata, 1380, 360, false))
        assertEquals(0L, ScheduleMath.initialDelayMillis(millis(kolkata, 2026, 9, 16, 5, 59), kolkata, 1380, 360, false))
        assertEquals(
            17 * hour,
            ScheduleMath.initialDelayMillis(millis(kolkata, 2026, 9, 16, 6), kolkata, 1380, 360, false),
        )
        assertTrue(ScheduleMath.isInsideWindow(0, 1380, 360))
        assertFalse(ScheduleMath.isInsideWindow(720, 1380, 360))
    }

    @Test
    fun countsTheLostHourWhenClocksGoForward() {
        // Europe/London moves from 01:00 GMT to 02:00 BST on 29 March 2026.
        // From noon on the 28th to 03:00 local on the 29th is 14 real hours.
        val now = millis(london, 2026, 3, 28, 12)

        assertEquals(14 * hour, ScheduleMath.initialDelayMillis(now, london, 180, 420, immediate = false))
    }

    @Test
    fun countsTheExtraHourWhenClocksGoBack() {
        // Europe/London moves from 02:00 BST back to 01:00 GMT on 25 October 2026.
        // From noon on the 24th to 03:00 local on the 25th is 16 real hours.
        val now = millis(london, 2026, 10, 24, 12)

        assertEquals(16 * hour, ScheduleMath.initialDelayMillis(now, london, 180, 420, immediate = false))
    }

    @Test
    fun aWindowStartInsideTheDstGapOpensWhenTheGapEnds() {
        // 01:30 doesn't exist in London on 29 March 2026; the window opens at
        // 02:30 BST, which is 01:30 UTC.
        val now = millis(london, 2026, 3, 29, 0, 30)

        assertEquals(hour, ScheduleMath.initialDelayMillis(now, london, 90, 420, immediate = false))
    }

    @Test
    fun choosesNetworkConstraints() {
        assertEquals(NetworkNeed.NONE, ScheduleMath.networkNeed(immediate = false, usesNetwork = false))
        assertEquals(NetworkNeed.NONE, ScheduleMath.networkNeed(immediate = true, usesNetwork = false))
        assertEquals(NetworkNeed.UNMETERED, ScheduleMath.networkNeed(immediate = false, usesNetwork = true))
        assertEquals(NetworkNeed.CONNECTED, ScheduleMath.networkNeed(immediate = true, usesNetwork = true))
    }

    @Test
    fun followUpWaitsWhenARunMadeNoProgress() {
        assertNull(ScheduleMath.followUpDelayMillis(processed = 4, remaining = false, scheduledDelayMillis = 0))
        assertEquals(0L, ScheduleMath.followUpDelayMillis(processed = 4, remaining = true, scheduledDelayMillis = 0))
        assertEquals(
            ScheduleMath.IDLE_RETRY_MILLIS,
            ScheduleMath.followUpDelayMillis(processed = 0, remaining = true, scheduledDelayMillis = 0),
        )
        assertEquals(
            13 * hour,
            ScheduleMath.followUpDelayMillis(processed = 0, remaining = true, scheduledDelayMillis = 13 * hour),
        )
        // With progress inside the window, the next run follows at once.
        assertEquals(
            0L,
            ScheduleMath.followUpDelayMillis(processed = 1, remaining = true, scheduledDelayMillis = 0),
        )
        // Nothing left, even with the window still open.
        assertNull(
            ScheduleMath.followUpDelayMillis(processed = 0, remaining = false, scheduledDelayMillis = 0),
        )
    }
}
