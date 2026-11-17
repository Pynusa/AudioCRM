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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        intent.action = null
        if (pending.isNotEmpty()) {
            channel?.invokeMethod("onSharedFiles", ArrayList(pending))
            pending.clear()
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
