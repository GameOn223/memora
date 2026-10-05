package io.github.gameon223.memora

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.gameon223.memora.bridge.ActivityHolder
import io.github.gameon223.memora.bridge.HostApis

class MainActivity : FlutterFragmentActivity() {
    private val activityHolder = ActivityHolder()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        activityHolder.attach(this)
        HostApis.register(flutterEngine, applicationContext, activityHolder)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        HostApis.unregister(flutterEngine.dartExecutor.binaryMessenger)
        activityHolder.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
