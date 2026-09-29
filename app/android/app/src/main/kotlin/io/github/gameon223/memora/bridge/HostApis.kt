package io.github.gameon223.memora.bridge

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.background.ProcessingScheduler
import io.github.gameon223.memora.capture.CaptureHostApiImpl
import io.github.gameon223.memora.files.FilesHostApiImpl
import io.github.gameon223.memora.gallery.GalleryHostApiImpl
import io.github.gameon223.memora.inference.MlKitOcr
import io.github.gameon223.memora.inference.OnnxEmbedder
import io.github.gameon223.memora.secure.KeystoreSecretStore

/** Wires every Dart-to-Kotlin API onto one engine. */
object HostApis {
    fun register(engine: FlutterEngine, context: Context, activity: ActivityHolder) =
        register(engine.dartExecutor.binaryMessenger, context, activity)

    fun register(messenger: BinaryMessenger, context: Context, activity: ActivityHolder) {
        val app = context.applicationContext
        GalleryHostApi.setUp(messenger, GalleryHostApiImpl(app, activity))
        CaptureHostApi.setUp(messenger, CaptureHostApiImpl(app, activity))
        SchedulerHostApi.setUp(messenger, ProcessingScheduler.get(app))
        SecretHostApi.setUp(messenger, KeystoreSecretStore.get(app))
        OcrHostApi.setUp(messenger, MlKitOcr.get(app))
        EmbeddingHostApi.setUp(messenger, OnnxEmbedder)
        FilesHostApi.setUp(messenger, FilesHostApiImpl(app, activity))
    }

    fun unregister(messenger: BinaryMessenger) {
        GalleryHostApi.setUp(messenger, null)
        CaptureHostApi.setUp(messenger, null)
        SchedulerHostApi.setUp(messenger, null)
        SecretHostApi.setUp(messenger, null)
        OcrHostApi.setUp(messenger, null)
        EmbeddingHostApi.setUp(messenger, null)
        FilesHostApi.setUp(messenger, null)
    }
}
