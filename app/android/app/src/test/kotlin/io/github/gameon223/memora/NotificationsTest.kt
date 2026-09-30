package io.github.gameon223.memora

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationsTest {
    @Test
    fun captureIdsWalkThroughTheirRange() {
        assertEquals(2001, Notifications.nextCaptureId(2000))
        assertEquals(2002, Notifications.nextCaptureId(2001))
    }

    @Test
    fun captureIdsWrapAtTheEndOfTheRange() {
        assertEquals(2000, Notifications.nextCaptureId(2999))
    }

    @Test
    fun captureIdsRecoverFromAValueOutsideTheRange() {
        assertEquals(2000, Notifications.nextCaptureId(0))
        assertEquals(2000, Notifications.nextCaptureId(99999))
    }

    @Test
    fun pendingIdsAreCappedOldestFirst() {
        var pending = emptyList<Int>()
        for (id in 1..25) {
            pending = Notifications.trimPending(pending, id, max = 20)
        }

        assertEquals(20, pending.size)
        assertEquals(6, pending.first())
        assertEquals(25, pending.last())
    }

    @Test
    fun pendingIdsAreNotDuplicated() {
        val pending = Notifications.trimPending(listOf(1, 2, 3), 2)

        assertEquals(listOf(1, 2, 3), pending)
        assertTrue(pending.size == 3)
    }
}
