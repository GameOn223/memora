package io.github.gameon223.memora.gallery

import io.github.gameon223.memora.bridge.GalleryPermission
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class GalleryPermissionsTest {
    @Test
    fun requestsTheRightPermissionsPerVersion() {
        assertArrayEquals(
            arrayOf("android.permission.READ_EXTERNAL_STORAGE"),
            GalleryPermissions.toRequest(32),
        )
        assertArrayEquals(
            arrayOf("android.permission.READ_MEDIA_IMAGES"),
            GalleryPermissions.toRequest(33),
        )
        assertArrayEquals(
            arrayOf(
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            ),
            GalleryPermissions.toRequest(34),
        )
    }

    @Test
    fun resolvesAccessState() {
        assertEquals(GalleryPermission.GRANTED, GalleryPermissions.resolve(true, true, true, false))
        assertEquals(GalleryPermission.PARTIAL, GalleryPermissions.resolve(false, true, true, false))
        assertEquals(GalleryPermission.DENIED, GalleryPermissions.resolve(false, false, false, false))
        assertEquals(GalleryPermission.DENIED, GalleryPermissions.resolve(false, false, true, true))
        assertEquals(
            GalleryPermission.PERMANENTLY_DENIED,
            GalleryPermissions.resolve(false, false, true, false),
        )
    }
}
