package io.github.gameon223.memora

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationBytesTest {
    @Test
    fun readsMegabytesUpToAGigabyte() {
        assertEquals("550 MB", Notifications.readableBytes(550L * 1024 * 1024))
        assertEquals("1 MB", Notifications.readableBytes(1L * 1024 * 1024))
    }

    @Test
    fun readsGigabytesWithOneDecimal() {
        assertEquals("3.0 GB", Notifications.readableBytes(3L * 1024 * 1024 * 1024))
        assertEquals("1.5 GB", Notifications.readableBytes(1536L * 1024 * 1024))
    }

    @Test
    fun zeroDoesNotCrashTheNotification() {
        // A download reports its first progress before any bytes land.
        assertEquals("0 MB", Notifications.readableBytes(0))
    }
}
