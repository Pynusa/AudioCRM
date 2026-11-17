package com.echoscriptai.transcriber

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.CallLog
import android.provider.MediaStore

object CallBridge {
    const val CHANNEL = "echoscript/calls"
    const val ACTION_OPEN_CALLS = "com.echoscriptai.transcriber.OPEN_CALLS"

    fun permissions(): Array<String> {
        val p = mutableListOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_PHONE_STATE
        )
        if (Build.VERSION.SDK_INT >= 33) {
            p.add(Manifest.permission.READ_MEDIA_AUDIO)
            p.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            p.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        return p.toTypedArray()
    }

    fun hasPermissions(ctx: Context): Boolean = permissions()
        .filter { it != Manifest.permission.POST_NOTIFICATIONS }
        .all { ctx.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    fun recentCalls(ctx: Context, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        ctx.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(
                CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DATE,
                CallLog.Calls.DURATION, CallLog.Calls.CACHED_NAME
            ),
            null, null, CallLog.Calls.DATE + " DESC"
        )?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "number" to (c.getString(0) ?: ""),
                        "type" to c.getInt(1),
                        "date" to c.getLong(2),
                        "duration" to c.getLong(3),
                        "name" to (c.getString(4) ?: "")
                    )
                )
            }
        }
        return out
    }

    fun recordings(ctx: Context, sinceMs: Long): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val base = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        @Suppress("DEPRECATION")
        val pathCol = if (Build.VERSION.SDK_INT >= 29)
            MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
        ctx.contentResolver.query(
            base,
            arrayOf(
                MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_ADDED, MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.MIME_TYPE, pathCol
            ),
            MediaStore.MediaColumns.DATE_ADDED + " >= ?",
            arrayOf((sinceMs / 1000).toString()),
            MediaStore.MediaColumns.DATE_ADDED + " DESC"
        )?.use { c ->
            while (c.moveToNext() && out.size < 200) {
                out.add(
                    mapOf(
                        "uri" to ContentUris.withAppendedId(base, c.getLong(0)).toString(),
                        "name" to (c.getString(1) ?: ""),
                        "date" to maxOf(c.getLong(2), c.getLong(3)) * 1000,
                        "size" to c.getLong(4),
                        "mime" to (c.getString(5) ?: ""),
                        "folder" to (c.getString(6) ?: "")
                    )
                )
            }
        }
        return out
    }
}
