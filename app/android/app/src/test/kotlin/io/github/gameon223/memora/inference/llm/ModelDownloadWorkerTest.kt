package io.github.gameon223.memora.inference.llm

import java.net.HttpURLConnection
import org.junit.Assert.assertEquals
import org.junit.Test

class ModelDownloadWorkerTest {
    @Test
    fun aTokenTheServerWillNotTakeIsAboutTheToken() {
        assertEquals(
            ModelDownloadWorker.ERROR_UNAUTHORIZED,
            ModelDownloadWorker.errorForStatus(HttpURLConnection.HTTP_UNAUTHORIZED),
        )
    }

    @Test
    fun aRefusalFromAGatedRepositoryIsAboutTheLicence() {
        // A gated repository answers a request it will not serve with a 404
        // as readily as a 403, and both mean the same thing to the user:
        // this account has not been granted these files.
        assertEquals(
            ModelDownloadWorker.ERROR_FORBIDDEN,
            ModelDownloadWorker.errorForStatus(HttpURLConnection.HTTP_FORBIDDEN),
        )
        assertEquals(
            ModelDownloadWorker.ERROR_FORBIDDEN,
            ModelDownloadWorker.errorForStatus(HttpURLConnection.HTTP_NOT_FOUND),
        )
    }

    @Test
    fun anythingElseIsJustAFailedDownload() {
        for (status in intArrayOf(500, 502, 418, 301)) {
            assertEquals(
                "status $status",
                ModelDownloadWorker.ERROR_FAILED,
                ModelDownloadWorker.errorForStatus(status),
            )
        }
    }

    @Test
    fun theTokenKeyMatchesTheOneSettingsWritesTo() {
        // The worker reads the token itself rather than taking it through
        // WorkManager's database, so the two names have to agree. The Dart
        // side writes LocalLlmController.tokenKey.
        assertEquals("huggingface.token", ModelDownloadWorker.TOKEN_KEY)
    }
}
