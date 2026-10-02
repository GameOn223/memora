package io.github.gameon223.memora.background

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.max

/** Which network a processing run needs. */
enum class NetworkNeed { NONE, CONNECTED, UNMETERED }

/** Pure scheduling rules, kept apart from WorkManager so they can be tested. */
object ScheduleMath {
    private const val MINUTES_PER_DAY = 24 * 60

    /** Wait at least this long before retrying a run that made no progress. */
    const val IDLE_RETRY_MILLIS = 15 * 60 * 1000L

    /** Same rule as `QueuePolicy.isInsideWindow` in memora_core. */
    fun isInsideWindow(minutesOfDay: Int, windowStart: Int, windowEnd: Int): Boolean {
        val start = normalize(windowStart)
        val end = normalize(windowEnd)
        return if (start <= end) {
            minutesOfDay >= start && minutesOfDay < end
        } else {
            minutesOfDay >= start || minutesOfDay < end
        }
    }

    /**
     * Milliseconds until processing may start. Zero in immediate mode or
     * inside the window, otherwise the real time until the next local window
     * start. Uses the zone's rules, so a DST change on the way is counted.
     */
    fun initialDelayMillis(
        nowMillis: Long,
        zone: ZoneId,
        windowStartMinutes: Int,
        windowEndMinutes: Int,
        immediate: Boolean,
    ): Long {
        if (immediate) return 0
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val minutes = now.hour * 60 + now.minute
        if (isInsideWindow(minutes, windowStartMinutes, windowEndMinutes)) return 0
        val start = normalize(windowStartMinutes)
        val startTime = LocalTime.of(start / 60, start % 60)
        // atZone moves a time that falls in a DST gap forward, which is what
        // we want: the window opens as soon as that local time exists.
        var next = now.toLocalDate().atTime(startTime).atZone(zone)
        if (!next.isAfter(now)) {
            next = now.toLocalDate().plusDays(1).atTime(startTime).atZone(zone)
        }
        return max(0L, next.toInstant().toEpochMilli() - nowMillis)
    }

    /**
     * Overnight runs with an off-device provider wait for Wi-Fi. "As you
     * add" only needs a connection. On-device providers need no network.
     */
    fun networkNeed(immediate: Boolean, usesNetwork: Boolean): NetworkNeed = when {
        !usesNetwork -> NetworkNeed.NONE
        immediate -> NetworkNeed.CONNECTED
        else -> NetworkNeed.UNMETERED
    }

    /**
     * When to run again after a run that ended. Null means nothing is left.
     * A run that processed nothing was blocked (no provider, paused, outside
     * the window), so it waits instead of spinning.
     */
    fun followUpDelayMillis(processed: Long, remaining: Boolean, scheduledDelayMillis: Long): Long? = when {
        !remaining -> null
        processed <= 0 -> max(scheduledDelayMillis, IDLE_RETRY_MILLIS)
        else -> scheduledDelayMillis
    }

    private fun normalize(minutes: Int): Int = ((minutes % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY
}
