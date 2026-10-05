package io.github.gameon223.memora.inference.llm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MemoryHeadroomTest {
    @Test
    fun aSmallModelFitsOnAnOrdinaryPhone() {
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(0.55),
            availableBytes = gb(2.5),
            totalBytes = gb(8),
            lowRamDevice = false,
        )

        assertEquals(Headroom.Allowed, decision)
    }

    @Test
    fun aVisionModelFitsWhenThereIsRoomForIt() {
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(3),
            availableBytes = gb(4.5),
            totalBytes = gb(8),
            lowRamDevice = false,
        )

        assertEquals(Headroom.Allowed, decision)
    }

    @Test
    fun aLowRamDeviceIsRefusedBeforeAnythingElse() {
        val decision = MemoryHeadroom.decide(
            modelBytes = 1,
            availableBytes = gb(8),
            totalBytes = gb(16),
            lowRamDevice = true,
        )

        assertEquals(MemoryHeadroom.LOW_RAM_DEVICE, refusal(decision).code)
    }

    @Test
    fun aModelTooLargeForTheDeviceIsRefusedEvenWhenMemoryLooksFree() {
        // Free memory right after a reclaim flatters the device. A 3 GB model
        // on a 4 GB phone is never going to hold.
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(3),
            availableBytes = gb(3.9),
            totalBytes = gb(4),
            lowRamDevice = false,
        )

        assertEquals(MemoryHeadroom.MODEL_TOO_LARGE, refusal(decision).code)
    }

    @Test
    fun aBusyPhoneIsToldToCloseApps() {
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(3),
            availableBytes = gb(2),
            totalBytes = gb(12),
            lowRamDevice = false,
        )

        val refused = refusal(decision)
        assertEquals(MemoryHeadroom.NOT_ENOUGH_MEMORY, refused.code)
        assertTrue(refused.message, refused.message.contains("Close some apps"))
    }

    @Test
    fun theRefusalCarriesTheNumbersInMegabytes() {
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(3),
            availableBytes = gb(2),
            totalBytes = gb(12),
            lowRamDevice = false,
        )

        val message = refusal(decision).message
        assertTrue(message, message.contains("3993 MB"))
        assertTrue(message, message.contains("2048 MB"))
    }

    @Test
    fun overheadIsAShareOfTheWeightsWithAFloor() {
        // 10 MB of weights still needs the floor.
        val small = 10L * 1024 * 1024
        assertEquals(
            small + MemoryHeadroom.MIN_OVERHEAD_BYTES,
            MemoryHeadroom.requiredBytes(small),
        )

        // 4 GB of weights needs the share, which is larger than the floor.
        val overhead = MemoryHeadroom.requiredBytes(gb(4)) - gb(4)
        assertTrue(overhead > MemoryHeadroom.MIN_OVERHEAD_BYTES)
        assertTrue(Math.abs(overhead - gb(1.2)) < 1024 * 1024)
    }

    @Test
    fun anUnknownTotalDoesNotRefuseOnTheShareRule() {
        // getMemoryInfo has reported zero on odd builds. Fall through to the
        // free-memory check rather than refusing every model.
        val decision = MemoryHeadroom.decide(
            modelBytes = gb(0.55),
            availableBytes = gb(3),
            totalBytes = 0,
            lowRamDevice = false,
        )

        assertEquals(Headroom.Allowed, decision)
    }

    @Test
    fun anExactFitIsAllowed() {
        val model = gb(0.55)
        val decision = MemoryHeadroom.decide(
            modelBytes = model,
            availableBytes = MemoryHeadroom.requiredBytes(model),
            totalBytes = gb(8),
            lowRamDevice = false,
        )

        assertEquals(Headroom.Allowed, decision)
    }

    @Test
    fun oneByteShortIsRefused() {
        val model = gb(0.55)
        val decision = MemoryHeadroom.decide(
            modelBytes = model,
            availableBytes = MemoryHeadroom.requiredBytes(model) - 1,
            totalBytes = gb(8),
            lowRamDevice = false,
        )

        assertEquals(MemoryHeadroom.NOT_ENOUGH_MEMORY, refusal(decision).code)
    }

    private fun refusal(decision: Headroom): Headroom.Refused =
        decision as? Headroom.Refused ?: throw AssertionError("Expected a refusal, got $decision")

    private fun gb(value: Double): Long = (value * 1024 * 1024 * 1024).toLong()

    private fun gb(value: Int): Long = value.toLong() * 1024 * 1024 * 1024
}
