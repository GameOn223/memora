package io.github.gameon223.memora.gallery

import android.Manifest
import io.github.gameon223.memora.bridge.GalleryPermission

/** Which permissions give gallery access on each Android version. */
object GalleryPermissions {
    private const val TIRAMISU = 33
    private const val UPSIDE_DOWN_CAKE = 34

    /** The permission that means full access. */
    fun fullAccessPermission(sdk: Int): String =
        if (sdk >= TIRAMISU) Manifest.permission.READ_MEDIA_IMAGES
        else Manifest.permission.READ_EXTERNAL_STORAGE

    /** What to ask for. Android 14 also offers "select photos" access. */
    fun toRequest(sdk: Int): Array<String> = when {
        sdk >= UPSIDE_DOWN_CAKE -> arrayOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
        )
        sdk >= TIRAMISU -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    fun supportsPartialAccess(sdk: Int): Boolean = sdk >= UPSIDE_DOWN_CAKE

    /**
     * Android doesn't say whether a prompt will still show. After at least
     * one request, a denied permission with no rationale to show means the
     * system stopped asking.
     */
    fun resolve(
        fullGranted: Boolean,
        partialGranted: Boolean,
        askedBefore: Boolean,
        shouldShowRationale: Boolean,
    ): GalleryPermission = when {
        fullGranted -> GalleryPermission.GRANTED
        partialGranted -> GalleryPermission.PARTIAL
        askedBefore && !shouldShowRationale -> GalleryPermission.PERMANENTLY_DENIED
        else -> GalleryPermission.DENIED
    }
}
