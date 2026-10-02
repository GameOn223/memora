package io.github.gameon223.memora.background

import io.github.gameon223.memora.bridge.SchedulePolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SchedulePolicyCodecTest {
    private val overnight = SchedulePolicy(
        immediate = false,
        paused = false,
        windowStartMinutes = 1380,
        windowEndMinutes = 360,
        requiresUnmeteredNetwork = true,
        hasWork = true,
    )

    @Test
    fun roundTripsAPolicy() {
        val restored = SchedulePolicyCodec.fromMap(SchedulePolicyCodec.toMap(overnight))

        assertEquals(overnight, restored)
    }

    @Test
    fun roundTripsTheImmediateMode() {
        val immediate = overnight.copy(immediate = true, paused = true, requiresUnmeteredNetwork = false)

        val restored = SchedulePolicyCodec.fromMap(SchedulePolicyCodec.toMap(immediate))

        assertEquals(immediate, restored)
    }

    @Test
    fun writesEveryKeyItReadsBack() {
        val stored = SchedulePolicyCodec.toMap(overnight)

        assertEquals(SchedulePolicyCodec.keys.toSet(), stored.keys)
    }

    @Test
    fun missingValuesFallBackToOvernight() {
        val restored = SchedulePolicyCodec.fromMap(emptyMap())

        assertFalse(restored.immediate)
        assertFalse(restored.paused)
        assertEquals(SchedulePolicyCodec.DEFAULT_WINDOW_START, restored.windowStartMinutes)
        assertEquals(SchedulePolicyCodec.DEFAULT_WINDOW_END, restored.windowEndMinutes)
        assertFalse(restored.hasWork)
    }

    @Test
    fun acceptsIntegersFromAnOlderInstall() {
        val restored = SchedulePolicyCodec.fromMap(
            mapOf(
                SchedulePolicyCodec.KEY_WINDOW_START to 90,
                SchedulePolicyCodec.KEY_WINDOW_END to 400,
                SchedulePolicyCodec.KEY_HAS_WORK to true,
            ),
        )

        assertEquals(90L, restored.windowStartMinutes)
        assertEquals(400L, restored.windowEndMinutes)
        assertTrue(restored.hasWork)
    }

    @Test
    fun ignoresValuesOfTheWrongType() {
        val restored = SchedulePolicyCodec.fromMap(
            mapOf(
                SchedulePolicyCodec.KEY_WINDOW_START to "01:00",
                SchedulePolicyCodec.KEY_IMMEDIATE to "yes",
            ),
        )

        assertEquals(SchedulePolicyCodec.DEFAULT_WINDOW_START, restored.windowStartMinutes)
        assertFalse(restored.immediate)
    }
}
