package com.hoshi.remote

import android.content.Context
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.Proxy
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.io.IOException

/** Что приложение помнит: адрес ПК с Хоши и ключ привязки телефона. */
class Prefs(context: Context) {
    private val store = context.getSharedPreferences("hoshi", Context.MODE_PRIVATE)

    /** Адрес ПК без схемы и порта, например "10.8.1.2" или "192.168.0.94". */
    var host: String
        get() = store.getString("host", "") ?: ""
        set(value) = store.edit().putString("host", value.trim()).apply()

    /** Все известные адреса ПК (из QR: основной и запасные — дом/VPN), через запятую. */
    var hosts: List<String>
        get() = (store.getString("hosts", "") ?: "").split(",").filter { it.isNotBlank() }
        set(value) = store.edit().putString("hosts", value.distinct().take(6).joinToString(",")).apply()

    /** Ключ привязки (тот же, что страница пульта хранит у себя). */
    var token: String
        get() = store.getString("token", "") ?: ""
        set(value) = store.edit().putString("token", value).apply()

    /** Быстрые кнопки телефона (JSON-массивы {command, title, icon, args}). */
    var quickNotify: String
        get() = store.getString("quick_notify", "[]") ?: "[]"
        set(value) = store.edit().putString("quick_notify", value).apply()

    var quickTiles: String
        get() = store.getString("quick_tiles", "[]") ?: "[]"
        set(value) = store.edit().putString("quick_tiles", value).apply()

    val pageUrl: String get() = "http://$host:$HTTP_PORT/"
    val socketUrl: String get() = "ws://$host:$WS_PORT/hoshi-remote-v1"

    companion object {
        const val HTTP_PORT = 18770
        const val WS_PORT = 18771

        /** null — Хоши ответила; иначе безопасная причина для экрана восстановления. */
        fun probeHost(host: String): String? = try {
            val connection = URL("http://$host:$HTTP_PORT/manifest.webmanifest").openConnection(Proxy.NO_PROXY) as HttpURLConnection
            connection.connectTimeout = 4000
            connection.readTimeout = 4000
            try {
                val status = connection.responseCode
                if (status == 200) null else "HTTP $status"
            } finally {
                connection.disconnect()
            }
        } catch (_: SocketTimeoutException) {
            "истекло время ожидания"
        } catch (_: NoRouteToHostException) {
            "нет маршрута к адресу"
        } catch (_: ConnectException) {
            "соединение отклонено"
        } catch (_: UnknownHostException) {
            "адрес не найден"
        } catch (_: SecurityException) {
            "Android запретил соединение"
        } catch (_: IOException) {
            "ошибка сети"
        }

        /** Проверка для фоновой службы и экрана настроек. */
        fun reachable(host: String): Boolean = probeHost(host) == null

        /** Первый отвечающий адрес из списка (текущий — первым); null — никто. */
        fun pickReachable(prefs: Prefs): String? {
            return ConnectionFlow.resolve(ConnectionFlow.candidates(prefs.host, prefs.hosts), ::reachable)
        }

        /** Адрес из того, что ввёл человек: "http://10.8.1.2:18770/#pair=1" -> "10.8.1.2". */
        fun cleanHost(text: String): String {
            var value = text.trim().substringAfter("://").substringBefore("/").substringBefore("#")
            value = value.substringBefore(":")
            return value.filter { it.isLetterOrDigit() || it == '.' || it == '-' }.take(64)
        }
    }
}
