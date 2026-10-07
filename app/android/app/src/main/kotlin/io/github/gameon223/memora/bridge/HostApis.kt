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
import io.github.gameon223.memora.inference.llm.GemmaRuntime
import io.github.gameon223.memora.inference.llm.LlmChunks
import io.github.gameon223.memora.inference.llm.LlmHostApiImpl
import io.github.gameon223.memora.inference.llm.ModelDownloads
import io.github.gameon223.memora.inference.llm.ModelImportEvents
import io.github.gameon223.memora.inference.llm.ModelImportHostApiImpl
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
        LlmHostApi.setUp(messenger, LlmHostApiImpl(app))
        ModelImportHostApi.setUp(messenger, ModelImportHostApiImpl(app, activity))
        LlmChunks.register(messenger)
        ModelImportEvents.register(messenger)
        ModelDownloads.register(messenger)
        FilesHostApi.setUp(messenger, FilesHostApiImpl(app, activity))
        LinksHostApi.setUp(messenger, LinksHostApiImpl(app))
    }

    fun unregister(messenger: BinaryMessenger) {
        GalleryHostApi.setUp(messenger, null)
        CaptureHostApi.setUp(messenger, null)
        SchedulerHostApi.setUp(messenger, null)
        SecretHostApi.setUp(messenger, null)
        OcrHostApi.setUp(messenger, null)
        EmbeddingHostApi.setUp(messenger, null)
        LlmHostApi.setUp(messenger, null)
        ModelImportHostApi.setUp(messenger, null)
        LlmChunks.unregister(messenger)
        ModelImportEvents.unregister(messenger)
        ModelDownloads.unregister(messenger)
        // A worker's engine is destroyed when the worker ends. With no engine
        // left there is nobody to generate for, and a model that stays
        // resident in a background process is what gets Memora killed.
        if (!LlmChunks.hasEngines()) GemmaRuntime.requestUnload()
        FilesHostApi.setUp(messenger, null)
        LinksHostApi.setUp(messenger, null)
    }
}
