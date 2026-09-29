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
        check(showNothingNew = false)
    }

    fun check(showNothingNew: Boolean) {
        Thread {
            val info = available(prefs)
            activity.runOnUiThread {
                if (info == null) {
                    if (showNothingNew) toast("Не удалось проверить обновление — проверь связь с ПК")
                    return@runOnUiThread
                }
                if (info.code > BuildConfig.VERSION_CODE) offer(info.name)
                else if (showNothingNew) toast("Установлена ${BuildConfig.VERSION_NAME}; на ПК доступна ${info.name}")
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

    data class Version(val code: Int, val name: String)

    companion object {
        fun available(prefs: Prefs): Version? = runCatching {
            val host = Prefs.pickReachable(prefs) ?: return null
            if (host != prefs.host) prefs.host = host
            availableAt(host)
        }.getOrNull()

        fun availableAt(host: String): Version? = runCatching {
            val info = JSONObject(get("http://$host:${Prefs.HTTP_PORT}/app/version.json").toString(Charsets.UTF_8))
            val code = info.getInt("versionCode")
            if (code < 1) return null
            Version(code, info.optString("versionName", code.toString()))
        }.getOrNull()

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
    }

    private fun toast(text: String) = Toast.makeText(activity, text, Toast.LENGTH_LONG).show()
}
