package com.hoshi.remote

import android.content.Context

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

        /** Отвечает ли Хоши по этому адресу (быстрая проверка, не на главном потоке). */
        fun reachable(host: String): Boolean = runCatching {
            val connection = java.net.URL("http://$host:$HTTP_PORT/manifest.webmanifest").openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = 1500
            connection.readTimeout = 1500
            try { connection.responseCode == 200 } finally { connection.disconnect() }
        }.getOrDefault(false)

        /** Первый отвечающий адрес из списка (текущий — первым); null — никто. */
        fun pickReachable(prefs: Prefs): String? {
            val candidates = (listOf(prefs.host) + prefs.hosts).filter { it.isNotBlank() }.distinct()
            return candidates.firstOrNull { reachable(it) }
        }

        /** Адрес из того, что ввёл человек: "http://10.8.1.2:18770/#pair=1" -> "10.8.1.2". */
        fun cleanHost(text: String): String {
            var value = text.trim().substringAfter("://").substringBefore("/").substringBefore("#")
            value = value.substringBefore(":")
            return value.filter { it.isLetterOrDigit() || it == '.' || it == '-' }.take(64)
        }
    }
}
