package com.hoshi.remote

import android.content.Context

/** Что приложение помнит: адрес ПК с Хоши и ключ привязки телефона. */
class Prefs(context: Context) {
    private val store = context.getSharedPreferences("hoshi", Context.MODE_PRIVATE)

    /** Адрес ПК без схемы и порта, например "10.8.1.2" или "192.168.0.94". */
    var host: String
        get() = store.getString("host", "") ?: ""
        set(value) = store.edit().putString("host", value.trim()).apply()

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

        /** Адрес из того, что ввёл человек: "http://10.8.1.2:18770/#pair=1" -> "10.8.1.2". */
        fun cleanHost(text: String): String {
            var value = text.trim().substringAfter("://").substringBefore("/").substringBefore("#")
            value = value.substringBefore(":")
            return value.filter { it.isLetterOrDigit() || it == '.' || it == '-' }.take(64)
        }
    }
}
