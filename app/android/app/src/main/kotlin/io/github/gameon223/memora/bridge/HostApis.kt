package io.github.gameon223.memora.bridge

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.github.gameon223.memora.files.FilesHostApiImpl
import io.github.gameon223.memora.secure.KeystoreSecretStore

/** Wires every Dart-to-Kotlin API onto one engine. */
object HostApis {
    fun register(engine: FlutterEngine, context: Context, activity: ActivityHolder) =
        register(engine.dartExecutor.binaryMessenger, context, activity)

    fun register(messenger: BinaryMessenger, context: Context, activity: ActivityHolder) {
        val app = context.applicationContext
        SecretHostApi.setUp(messenger, KeystoreSecretStore.get(app))
        FilesHostApi.setUp(messenger, FilesHostApiImpl(app, activity))
    }

    fun unregister(messenger: BinaryMessenger) {
        SecretHostApi.setUp(messenger, null)
        FilesHostApi.setUp(messenger, null)
    }
}
