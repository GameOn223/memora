package io.github.gameon223.memora.inference

import android.content.Context
import android.graphics.Rect
import android.net.Uri
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.github.gameon223.memora.bridge.FlutterError
import io.github.gameon223.memora.bridge.OcrBlockMessage
import io.github.gameon223.memora.bridge.OcrHostApi
import io.github.gameon223.memora.bridge.OcrLineMessage
import io.github.gameon223.memora.files.SafePaths
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * On-device text recognition with the bundled ML Kit Latin model. Recognized
 * text stays on the device and is never logged.
 */
class MlKitOcr private constructor(private val context: Context) : OcrHostApi {
    private val recognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override suspend fun recognize(absolutePath: String): List<OcrBlockMessage> {
        val file = File(absolutePath)
        try {
            SafePaths.requireInside(file, listOf(context.filesDir, context.cacheDir))
        } catch (error: IllegalArgumentException) {
            throw FlutterError("invalid_path", error.message, null)
        }
        if (!file.isFile) throw FlutterError("not_found", "The image file is missing.", null)

        val image = try {
            withContext(Dispatchers.IO) { InputImage.fromFilePath(context, Uri.fromFile(file)) }
        } catch (error: IOException) {
            throw FlutterError("decode_failed", "Couldn't read the image.", null)
        }
        val text = try {
            recognizer.process(image).await()
        } catch (error: Exception) {
            throw FlutterError("ocr_failed", "Text recognition failed on this device.", null)
        }
        return text.textBlocks.map { block ->
            OcrBlockMessage(
                lines = block.lines.map { line ->
                    val box = line.boundingBox ?: EMPTY_BOX
                    OcrLineMessage(
                        text = line.text,
                        left = box.left.toLong(),
                        top = box.top.toLong(),
                        right = box.right.toLong(),
                        bottom = box.bottom.toLong(),
                    )
                },
            )
        }
    }

    companion object {
        private val EMPTY_BOX = Rect(0, 0, 0, 0)

        @Volatile
        private var instance: MlKitOcr? = null

        fun get(context: Context): MlKitOcr =
            instance ?: synchronized(this) {
                instance ?: MlKitOcr(context.applicationContext).also { instance = it }
            }
    }
}

/** Bridges a Play services [Task] to a coroutine without another dependency. */
private suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { result -> if (continuation.isActive) continuation.resume(result) }
    addOnFailureListener { error -> if (continuation.isActive) continuation.resumeWithException(error) }
    addOnCanceledListener { continuation.cancel() }
}
