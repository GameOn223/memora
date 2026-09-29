package io.github.gameon223.memora.capture

import android.Manifest
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import io.github.gameon223.memora.Notifications
import io.github.gameon223.memora.R
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.CaptureHostApi
import io.github.gameon223.memora.bridge.CaptureStatus
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.InboxItem
import io.github.gameon223.memora.bridge.awaitActivityResult
import java.util.function.Consumer
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class CaptureHostApiImpl(
    private val context: Context,
    private val activity: ActivityHolder,
) : CaptureHostApi {

    override fun status(): CaptureStatus = CaptureStatus(
        accessibilitySupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R,
        accessibilityEnabled = isAccessibilityEnabled(),
        canRequestTile = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
        notificationsAllowed = Notifications.canPost(context),
    )

    override fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        val host = activity.current
        try {
            if (host != null) {
                host.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } catch (error: RuntimeException) {
            // Some builds have no accessibility settings screen.
            throw FlutterError(
                "no_settings",
                "This device has no accessibility settings screen.",
                null,
            )
        }
    }

    override suspend fun requestAddTile(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val host = activity.current ?: context
        val statusBar = host.getSystemService(StatusBarManager::class.java) ?: return false
        return suspendCancellableCoroutine { continuation ->
            try {
                statusBar.requestAddTileService(
                    ComponentName(context, MemoraTileService::class.java),
                    context.getString(R.string.tile_label),
                    Icon.createWithResource(context, R.drawable.ic_tile),
                    context.mainExecutor,
                    Consumer { result ->
                        if (continuation.isActive) continuation.resume(isTileAdded(result))
                    },
                )
            } catch (error: RuntimeException) {
                // Asking twice in a row, or asking from the background.
                if (continuation.isActive) continuation.resume(false)
            }
        }
    }

    override suspend fun requestNotificationPermission(): Boolean {
        if (Notifications.canPost(context)) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val host = activity.require()
        return host.awaitActivityResult(
            ActivityResultContracts.RequestPermission(),
            Manifest.permission.POST_NOTIFICATIONS,
        )
    }

    override suspend fun drainInbox(): List<InboxItem> = Inbox.drain(context)

    override suspend fun confirmInbox(ids: List<String>) {
        if (ids.isEmpty()) return
        Inbox.confirm(context, ids)
        // The same update whether the UI or a worker did the filing.
        Notifications.captureFiled(context)
    }

    private fun isAccessibilityEnabled(): Boolean {
        if (CaptureAccessibilityService.instance != null) return true
        val setting = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            )
        } catch (error: SecurityException) {
            null
        }
        return AccessibilitySettings.isEnabled(
            setting,
            context.packageName,
            CaptureAccessibilityService::class.java.name,
        )
    }

    private fun isTileAdded(result: Int): Boolean =
        result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
            result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
}
