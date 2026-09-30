package io.github.gameon223.memora.share

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.core.content.IntentCompat
import io.github.gameon223.memora.MemoraApplication
import io.github.gameon223.memora.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Receives images shared to Memora. The activity stays alive until the copy
 * finishes, because the read permission on a shared URI ends with it.
 */
class ShareReceiverActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) {
            finish()
            return
        }
        val uris = extractUris(intent)
        if (uris.isEmpty()) {
            Toast.makeText(this, R.string.share_nothing, Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        MemoraApplication.from(this).appScope.launch {
            val saved = ShareImporter.saveToInbox(applicationContext, uris)
            withContext(Dispatchers.Main) {
                showResult(saved)
                finish()
            }
        }
    }

    private fun showResult(saved: Int) {
        val message = when (saved) {
            0 -> getString(R.string.share_nothing)
            1 -> getString(R.string.share_saved_one)
            else -> getString(R.string.share_saved_many, saved)
        }
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
    }

    private fun extractUris(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val found = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND ->
                IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                    ?.let { found.add(it) }
            Intent.ACTION_SEND_MULTIPLE ->
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                    ?.let { found.addAll(it) }
        }
        if (found.isEmpty()) {
            val clip = intent.clipData
            if (clip != null) {
                for (index in 0 until clip.itemCount) {
                    clip.getItemAt(index).uri?.let { found.add(it) }
                }
            }
        }
        return found
    }
}
