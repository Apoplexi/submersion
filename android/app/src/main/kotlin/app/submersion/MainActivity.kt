package app.submersion

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity): local_auth's biometric
// prompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private var metadataHandler: MetadataWriteHandler? = null
    private var localMediaHandler: LocalMediaHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register platform channel handlers
        metadataHandler = MetadataWriteHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )

        val localMediaChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LocalMediaHandler.CHANNEL,
        )
        localMediaHandler = LocalMediaHandler(applicationContext, localMediaChannel)
    }
}
