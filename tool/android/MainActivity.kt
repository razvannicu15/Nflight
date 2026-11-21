package ro.noraz.nflight

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Shared / opened files (PDF, image, .pkpass) and screen brightness for Nflight. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialFile: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialFile = fileFrom(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nflight/native").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialFile" -> {
                        result.success(initialFile)
                        initialFile = null
                    }
                    "brightness" -> {
                        val v = (call.arguments as? Number)?.toFloat() ?: -1f
                        window.attributes = window.attributes.apply {
                            screenBrightness = if (v < 0) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else v
                        }
                        result.success(null)
                    }
                    "keepOn" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = fileFrom(intent) ?: return
        channel?.invokeMethod("file", path)
    }

    private fun fileFrom(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        return uri?.let { copyToCache(it) }
    }

    private fun copyToCache(uri: Uri): String? = try {
        var name = "import"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { name = it }
        }
        if (!name.contains('.')) {
            val type = contentResolver.getType(uri) ?: ""
            name += when {
                type.contains("pdf") -> ".pdf"
                type.contains("pkpass") -> ".pkpass"
                type.startsWith("image/") -> ".png"
                else -> ""
            }
        }
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val out = File(cacheDir, "shared_${System.currentTimeMillis()}_$safe")
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
        }
        out.absolutePath
    } catch (e: Exception) {
        null
    }
}
