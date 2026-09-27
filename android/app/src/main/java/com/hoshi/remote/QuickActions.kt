package com.hoshi.remote

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import org.json.JSONArray
import org.json.JSONObject

/**
 * Быстрые кнопки телефона: до 3 в уведомлении «Хоши на связи» (видно на экране
 * блокировки) и до 6 плиток в шторке. Выбирают их на странице пульта в приложении
 * (вкладка «Компьютер» → «Быстрые кнопки телефона»); это те же команды пульта
 * ({command, title, icon, args}), без «опасных» (с «Точно?»).
 * Нажатие уходит по связи службы (экран пульта скрыт) или через саму страницу.
 */
object QuickActions {
    const val NOTIFY_MAX = 3
    const val TILES_MAX = 6

    fun notifyItems(context: Context): List<JSONObject> = parse(Prefs(context).quickNotify, NOTIFY_MAX)
    fun tileItems(context: Context): List<JSONObject> = parse(Prefs(context).quickTiles, TILES_MAX)

    /** Сохранить выбор со страницы: {"notify": [...], "tiles": [...]}. */
    fun save(context: Context, json: String) {
        val data = runCatching { JSONObject(json) }.getOrNull() ?: return
        val prefs = Prefs(context)
        prefs.quickNotify = clean(data.optJSONArray("notify"), NOTIFY_MAX).toString()
        prefs.quickTiles = clean(data.optJSONArray("tiles"), TILES_MAX).toString()
        refresh(context)
    }

    /** То, что страница видит сейчас: какой звук включён, что выбрано у Хоши. */
    @Volatile var summary: JSONObject = JSONObject()

    fun isActive(item: JSONObject): Boolean {
        val command = item.optString("command")
        if (command.startsWith("sound:")) return summary.optString("sound") == command
        val selected = summary.optJSONArray("selected") ?: return false
        for (i in 0 until selected.length()) if (selected.optString(i) == command) return true
        return false
    }

    /** Выполнить кнопку: связью службы, а если пульт на экране — через страницу. */
    fun run(context: Context, item: JSONObject) {
        val command = item.optString("command")
        if (command.isEmpty()) return
        val args = item.optJSONObject("args") ?: JSONObject()
        if (HoshiService.pageVisible && MainActivity.runOnPage(command, args)) return
        if (!HoshiService.send(command, args)) HoshiService.start(context) // проснётся и отправит
    }

    /** Состояние поменялось или выбор новый — обновить уведомление и плитки. */
    fun refresh(context: Context) {
        HoshiService.refreshQuick()
        for (slot in 1..TILES_MAX) {
            runCatching { TileService.requestListeningState(context, ComponentName(context, "com.hoshi.remote.QuickTile$slot")) }
        }
    }

    private fun parse(text: String, max: Int): List<JSONObject> {
        val array = runCatching { JSONArray(text) }.getOrNull() ?: return emptyList()
        return (0 until minOf(array.length(), max)).mapNotNull { array.optJSONObject(it) }
    }

    private fun clean(array: JSONArray?, max: Int): JSONArray {
        val out = JSONArray()
        if (array == null) return out
        for (i in 0 until array.length()) {
            if (out.length() >= max) break
            val item = array.optJSONObject(i) ?: continue
            val command = item.optString("command")
            if (command.isEmpty() || command.length > 80 || item.optBoolean("confirm")) continue
            val entry = JSONObject().put("command", command)
                .put("title", item.optString("title").take(24)).put("icon", item.optString("icon").take(4))
            item.optJSONObject("args")?.let { entry.put("args", it) }
            out.put(entry)
        }
        return out
    }
}
