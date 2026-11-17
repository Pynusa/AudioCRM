package com.echoscriptai.transcriber

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.TelephonyManager

/** Показывает уведомление «Звонок завершён» после окончания разговора. */
class CallReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val prefs = ctx.getSharedPreferences("call_state", Context.MODE_PRIVATE)
        val prev = prefs.getString("prev", TelephonyManager.EXTRA_STATE_IDLE)
        if (state == prev) return
        prefs.edit().putString("prev", state).apply()
        if (state == TelephonyManager.EXTRA_STATE_IDLE &&
            prev == TelephonyManager.EXTRA_STATE_OFFHOOK
        ) notifyCallEnded(ctx)
    }

    private fun notifyCallEnded(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val open = Intent(ctx, MainActivity::class.java)
            .setAction(CallBridge.ACTION_OPEN_CALLS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pi = PendingIntent.getActivity(
            ctx, 1, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel("calls", "Звонки", NotificationManager.IMPORTANCE_HIGH)
            )
            Notification.Builder(ctx, "calls")
        } else {
            @Suppress("DEPRECATION") Notification.Builder(ctx)
        }
        nm.notify(
            4711,
            builder.setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle("Звонок завершён")
                .setContentText("Нажмите, чтобы сохранить результат в amoCRM")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
        )
    }
}
