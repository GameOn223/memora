package io.github.gameon223.memora.bridge

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Opens a web page in whatever the phone uses for links.
 *
 * Only http and https get through. Every link Memora opens is a page it
 * names itself, a model page or a provider's key settings, so anything else
 * arriving here is either a mistake or a way to start an arbitrary activity
 * on the strength of a string.
 */
class LinksHostApiImpl(private val context: Context) : LinksHostApi {
    override suspend fun openUrl(url: String): Boolean {
        val uri = try {
            Uri.parse(url)
        } catch (error: RuntimeException) {
            throw FlutterError("bad_url", "That is not a link Memora can open.", null)
        }
        if (uri.scheme?.lowercase() !in ALLOWED_SCHEMES) {
            throw FlutterError(
                "bad_url",
                "Only http and https links can be opened.",
                null,
            )
        }
        val intent = Intent(Intent.ACTION_VIEW, uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (error: ActivityNotFoundException) {
            // No browser. Worth telling the user rather than failing silently.
            false
        }
    }

    private companion object {
        val ALLOWED_SCHEMES = setOf("http", "https")
    }
}
