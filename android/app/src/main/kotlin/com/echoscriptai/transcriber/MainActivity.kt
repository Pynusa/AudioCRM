package com.echoscriptai.transcriber

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Receives audio files shared from other apps (Samsung Voice Recorder, Telegram,
 * WhatsApp, file managers) via ACTION_SEND / ACTION_SEND_MULTIPLE and hands
 * local cache copies over to Flutter.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "echoscript/share"
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Map<String, String>>()
    private val worker = Executors.newSingleThreadExecutor()
    private var callsChannel: MethodChannel? = null
    private var permResult: MethodChannel.Result? = null
    private var openCalls = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedFiles" -> {
                    handleIntent(intent)
                    intent?.action = null
                    result.success(ArrayList(pending))
                    pending.clear()
                }
                
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "echoscript/audio")
            .setMethodCallHandler { call, result ->
                if (call.method != "decodeToWavChunks") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val seconds = call.argument<Int>("chunkSeconds") ?: 30
                if (path == null) {
                    result.error("ARG", "path is required", null)
                    return@setMethodCallHandler
                }
                worker.execute {
                    try {
                        val out = File(cacheDir, "nvidia_chunks")
                        val chunks = AudioDecoder.decodeToWavChunks(path, out, seconds)
                        runOnUiThread { result.success(chunks) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("DECODE", e.message ?: e.toString(), null) }
                    }
                }
            }
                  callsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CallBridge.CHANNEL)
        callsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(CallBridge.hasPermissions(this))
                "requestPermissions" -> {
                    permResult = result
                    requestPermissions(CallBridge.permissions(), 4711)
                }
                "consumeOpenCalls" -> {
                    val v = openCalls || intent?.action == CallBridge.ACTION_OPEN_CALLS
                    openCalls = false
                    if (intent?.action == CallBridge.ACTION_OPEN_CALLS) intent?.action = null
                    result.success(v)
                }
                "recentCalls" -> worker.execute {
                    try {
                        val r = CallBridge.recentCalls(this, call.argument<Int>("limit") ?: 50)
                        runOnUiThread { result.success(r) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("CALLS", e.message ?: e.toString(), null) }
                    }
                }
                "recordings" -> worker.execute {
                    try {
                        val since = (call.argument<Number>("since") ?: 0).toLong()
                        val r = CallBridge.recordings(this, since)
                        runOnUiThread { result.success(r) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("REC", e.message ?: e.toString(), null) }
                    }
                }
                "importRecording" -> worker.execute {
                    try {
                        val m = copyToCache(Uri.parse(call.argument<String>("uri")))
                        runOnUiThread {
                            if (m == null) result.error("REC", "Не удалось прочитать запись", null)
                            else result.success(m)
                        }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("REC", e.message ?: e.toString(), null) }
                    }
                }
                "canOverlay" -> result.success(android.provider.Settings.canDrawOverlays(this))
                "requestOverlay" -> {
                    startActivity(
                        Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
  
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == CallBridge.ACTION_OPEN_CALLS) {
            callsChannel?.invokeMethod("openCalls", null)
        }

        setIntent(intent)
        handleIntent(intent)
        intent.action = null
        if (pending.isNotEmpty()) {
            channel?.invokeMethod("onSharedFiles", ArrayList(pending))
            pending.clear()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            permResult?.success(CallBridge.hasPermissions(this))
            permResult = null
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
                if (uri != null) uris.add(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                if (list != null) uris.addAll(list)
            }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
        }
        for (uri in uris) {
            try {
                copyToCache(uri)?.let { pending.add(it) }
            } catch (_: Exception) {
            }
        }
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        var name = "shared_audio_${System.currentTimeMillis()}"
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) c.getString(idx)?.let { name = it }
        }
        val mime = contentResolver.getType(uri) ?: ""
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val out = File(dir, "${System.currentTimeMillis()}_$safe")
        contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { input.copyTo(it) }
        } ?: return null
        return mapOf("path" to out.absolutePath, "name" to name, "mimeType" to mime)
    }
}
