package com.echoscriptai.transcriber

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/** Плашка с данными клиента из amoCRM поверх экрана входящего звонка. */
object CallerOverlay {
    private val main = Handler(Looper.getMainLooper())
    private var view: View? = null
    @Volatile private var session = 0

    fun show(ctx: Context, number: String, done: () -> Unit) {
        val finished = AtomicBoolean(false)
        val finish: () -> Unit = { if (finished.compareAndSet(false, true)) done() }
        if (!Settings.canDrawOverlays(ctx)) {
            finish()
            return
        }
        session++
        val s = session
        main.postDelayed({ finish() }, 8000)
        thread {
            try {
                lookup(ctx, number, s)
            } catch (e: Exception) {
                // нет сети или ошибка amoCRM — плашку не показываем
            } finally {
                finish()
            }
        }
    }

    fun hide() {
        session++
        main.post { remove() }
    }

    private fun str(o: JSONObject, key: String): String =
        if (o.isNull(key)) "" else o.optString(key)

    private fun digits10(phone: String): String {
        val d = phone.filter { it.isDigit() }
        return if (d.length > 10) d.substring(d.length - 10) else d
    }

    private fun get(host: String, token: String, path: String): JSONObject? {
        val c = URL("https://$host$path").openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 3000
            c.readTimeout = 3000
            c.setRequestProperty("Authorization", "Bearer $token")
            if (c.responseCode != 200) return null
            return JSONObject(c.inputStream.bufferedReader().readText())
        } finally {
            c.disconnect()
        }
    }

    private fun values(f: JSONObject): String {
        val vs = f.optJSONArray("values") ?: return ""
        return (0 until vs.length()).mapNotNull { vs.optJSONObject(it) }
            .map { str(it, "value") }
            .filter { it.isNotEmpty() }
            .joinToString(", ")
    }

    private fun hasPhone(c: JSONObject, d: String): Boolean {
        val cf = c.optJSONArray("custom_fields_values") ?: return false
        for (i in 0 until cf.length()) {
            val f = cf.optJSONObject(i) ?: continue
            if (f.optString("field_code") != "PHONE") continue
            val vs = f.optJSONArray("values") ?: continue
            for (k in 0 until vs.length()) {
                val v = vs.optJSONObject(k) ?: continue
                if (digits10(str(v, "value")) == d) return true
            }
        }
        return false
    }

    private fun lookup(ctx: Context, number: String, s: Int) {
        val raw = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.amo_settings_v1", null) ?: return
        val cfg = JSONObject(raw)
        var host = cfg.optString("domain").trim()
            .replace(Regex("^https?://"), "").substringBefore("/")
        val token = cfg.optString("token").trim()
        if (host.isEmpty() || token.isEmpty()) return
        if (!host.contains(".")) host += ".amocrm.ru"
        val d = digits10(number)
        if (d.length < 6) return

        val found = get(host, token, "/api/v4/contacts?query=$d&with=leads&limit=10")
            ?.optJSONObject("_embedded")?.optJSONArray("contacts") ?: return
        val contact = (0 until found.length())
            .mapNotNull { found.optJSONObject(it) }
            .firstOrNull { hasPhone(it, d) } ?: return
        val name = str(contact, "name").ifEmpty { number }
        post(ctx, s, name, emptyList())

        val lines = ArrayList<String>()
        val emb = contact.optJSONObject("_embedded")

        val companyId = emb?.optJSONArray("companies")?.optJSONObject(0)?.optLong("id") ?: 0L
        if (companyId > 0) {
            val co = get(host, token, "/api/v4/companies/$companyId")
            if (co != null) {
                lines.add("Компания: " + str(co, "name"))
                val ids = HashSet<Long>()
                val only = cfg.optJSONArray("companyFields")
                if (only != null) for (i in 0 until only.length()) ids.add(only.optLong(i))
                val cf = co.optJSONArray("custom_fields_values")
                if (cf != null) for (i in 0 until cf.length()) {
                    val f = cf.optJSONObject(i) ?: continue
                    if (!ids.contains(f.optLong("field_id"))) continue
                    val v = values(f)
                    if (v.isNotEmpty()) lines.add(str(f, "field_name") + ": " + v)
                }
            }
        }

        val leads = emb?.optJSONArray("leads")
        if (leads != null && leads.length() > 0) {
            val q = (0 until minOf(leads.length(), 50)).joinToString("&") {
                "filter%5Bid%5D%5B$it%5D=" + (leads.optJSONObject(it)?.optLong("id") ?: 0L)
            }
            val arr = get(host, token, "/api/v4/leads?$q&limit=50")
                ?.optJSONObject("_embedded")?.optJSONArray("leads")
            var last: JSONObject? = null
            if (arr != null) for (i in 0 until arr.length()) {
                val l = arr.optJSONObject(i) ?: continue
                val cur = last
                if (cur == null || l.optLong("created_at") > cur.optLong("created_at")) last = l
            }
            val l = last
            if (l != null) lines.add("Сделка: " + str(l, "name"))
        }
        if (lines.isNotEmpty()) post(ctx, s, name, lines)
    }

    private fun post(ctx: Context, s: Int, title: String, lines: List<String>) {
        val copy = ArrayList(lines)
        main.post { if (s == session) display(ctx, title, copy) }
    }

    private fun remove() {
        val v = view ?: return
        view = null
        try {
            (v.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (e: Exception) {
        }
    }

    private fun display(ctx: Context, title: String, lines: List<String>) {
        remove()
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = ctx.resources.displayMetrics
        val dp = dm.density
        val box = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val p = (16 * dp).toInt()
            setPadding(p, p, p, p)
            background = GradientDrawable().apply {
                setColor(0xF20F172A.toInt())
                cornerRadius = 20 * dp
            }
            setOnClickListener { hide() }
        }
        box.addView(TextView(ctx).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 20f
            setTypeface(typeface, Typeface.BOLD)
        })
        for (l in lines) {
            box.addView(TextView(ctx).apply {
                text = l
                setTextColor(0xFFCBD5E1.toInt())
                textSize = 15f
                setPadding(0, (4 * dp).toInt(), 0, 0)
            })
        }
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        @Suppress("DEPRECATION")
        val lp = WindowManager.LayoutParams(
            dm.widthPixels - (32 * dp).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.CENTER
        try {
            wm.addView(box, lp)
            view = box
        } catch (e: Exception) {
        }
    }
}
