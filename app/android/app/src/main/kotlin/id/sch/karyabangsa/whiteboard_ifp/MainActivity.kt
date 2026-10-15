package id.sch.karyabangsa.whiteboard_ifp

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "whiteboard_ifp/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPackageInstalled" -> {
                        val name = call.argument<String>("name")
                        if (name == null) {
                            result.error("bad_args", "name is required", null)
                        } else {
                            result.success(isInstalled(name))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isInstalled(name: String): Boolean = try {
        packageManager.getPackageInfo(name, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }
}
