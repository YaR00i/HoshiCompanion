package com.hoshi.remote

import android.content.Intent
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Автообновление самого приложения. Интерфейс (пульт) и так всегда свежий — он с ПК;
 * обновлять нужно только «обёртку». Хоши раздаёт http://<ПК>:18770/app/version.json
 * ({"versionCode": N, "versionName": "…"}) и /app/hoshi.apk — их кладёт туда
 * `python tools/dev.py android`. Новее установленной — предложить «Обновить»;
 * Android каждый раз сам спросит «Установить?» (так устроена установка не из магазина).
 */
class Updater(private val activity: AppCompatActivity, private val prefs: Prefs) {

    fun checkLater() {
        Thread { runCatching { check(showNothingNew = false) } }.start()
    }

    fun check(showNothingNew: Boolean) {
        Thread {
            val info = runCatching {
                val text = get("${prefs.pageUrl}app/version.json").toString(Charsets.UTF_8)
                JSONObject(text)
            }.getOrNull()
            activity.runOnUiThread {
                if (info == null) {
                    if (showNothingNew) toast("Хоши пока не раздаёт обновлений")
                    return@runOnUiThread
                }
                val code = info.optInt("versionCode", 0)
                if (code > BuildConfig.VERSION_CODE) offer(info.optString("versionName", code.toString()))
                else if (showNothingNew) toast("У тебя последняя версия")
            }
        }.start()
    }

    private fun offer(name: String) {
        AlertDialog.Builder(activity)
            .setTitle("Новая версия приложения Хоши")
            .setMessage("Есть версия $name. Обновить сейчас?")
            .setPositiveButton("Обновить") { _, _ -> download() }
            .setNegativeButton("Потом", null)
            .show()
    }

    private fun download() {
        if (!activity.packageManager.canRequestPackageInstalls()) {
            toast("Разреши Хоши устанавливать обновления и нажми «Обновить» ещё раз")
            MainActivity.openSettings(activity, Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            return
        }
        toast("Скачиваю обновление…")
        Thread {
            val file = runCatching {
                val folder = File(activity.cacheDir, "updates").apply { mkdirs() }
                File(folder, "hoshi.apk").apply { writeBytes(get("${prefs.pageUrl}app/hoshi.apk")) }
            }.getOrNull()
            activity.runOnUiThread {
                if (file == null) {
                    toast("Не получилось скачать обновление")
                    return@runOnUiThread
                }
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
                activity.startActivity(Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }.start()
    }

    private fun get(url: String): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 4000
        connection.readTimeout = 30000
        try {
            if (connection.responseCode != 200) error("HTTP ${connection.responseCode}")
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    private fun toast(text: String) = Toast.makeText(activity, text, Toast.LENGTH_LONG).show()
}
