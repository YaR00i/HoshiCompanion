package com.hoshi.remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.widget.RemoteViews
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import org.json.JSONArray
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Связь с Хоши, пока экран пульта не на виду (телефон заблокирован, другое приложение).
 * Служба запускается, пока приложение ещё на экране (из фона Android её запускать
 * не даёт), и живёт всё время; пока пульт на виду (pageVisible), она молчит —
 * связь держит страница (у Хоши один телефон = одно соединение).
 * Тот же протокол, что у страницы (remote_bus.gd): hello с ключом, ping раз в 10 с,
 * сообщения state. Следит только за карточкой Claude и присылает уведомления:
 * «закончил ✓», «ждёт ответа ?», «прервался ⚠». Постоянное тихое уведомление
 * «Хоши на связи» — требование Android для такой службы.
 *
 * Плееры (MPC-BE, YouTube): одна «плеерная» карточка с кнопками ⏪ ⏯ ⏩ ⏭ в шторке
 * и на экране блокировки (HyperOS и др. показывают только одну). Карточка
 * «приклеена» к своему плееру: пауза её не переключает; другой плеер начал
 * играть — переключается на него; кнопка ⇄ — переключить вручную. Нажатие — та же команда, что
 * кнопка на пульте ({"op":"run","command":"app:mpc:toggle"} и т.п.); сама служба
 * команд не придумывает — берёт их из карточки плеера.
 */
class HoshiService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private var socket: WebSocket? = null
    private var running = false
    private var retry = 2000L
    private var lastClaude = ""
    /** Открытые плееры: id ("mpc", "youtube") -> его уведомление и сессия. */
    private val players = mutableMapOf<String, Player>()

    /** Какой плеер сейчас на карточке. */
    private var front = ""
    private var frontKey = ""

    private class Player(val session: MediaSessionCompat) {
        /** back/toggle/forward/next -> {command, args} из карточки плеера. */
        var commands: Map<String, JSONObject> = emptyMap()
        var app = ""
        var title = ""
        var subtitle = ""
        var playing = false
        var durationMs = 0L
        var positionMs = 0L
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        channels()
        startForeground(ONGOING_ID, ongoing("Хоши на связи"))
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        val quick = intent?.getIntExtra(EXTRA_QUICK, -1) ?: -1
        if (quick >= 0) QuickActions.notifyItems(this).getOrNull(quick)?.let { QuickActions.run(this, it) }
        intent?.getStringExtra(EXTRA_PLAYER)?.let { press(intent.getStringExtra(EXTRA_APP) ?: "", it) }
        if (!running) {
            running = true
            main.postDelayed(pinger, PING_EVERY)
        }
        pageChanged()
        return START_STICKY
    }

    /** Пульт появился/скрылся: на виду — молчать; скрылся — держать связь самой. */
    fun pageChanged() {
        if (pageVisible) {
            socket?.close(1000, "page on screen")
            socket = null
            notifyOngoing("Хоши на связи")
        } else if (socket == null) {
            retry = 2000L
            connect()
        }
    }

    override fun onDestroy() {
        running = false
        if (instance === this) instance = null
        for (player in players.values) player.session.release()
        players.clear()
        manager().cancel(PLAYER_ID)
        main.removeCallbacksAndMessages(null)
        socket?.close(1000, "app on screen")
        socket = null
        super.onDestroy()
    }

    private val pinger = object : Runnable {
        override fun run() {
            if (!running) return
            socket?.send("{\"op\":\"ping\"}")
            main.postDelayed(this, PING_EVERY)
        }
    }

    private fun connect() {
        val prefs = Prefs(this)
        if (!running || pageVisible || socket != null || prefs.host.isEmpty() || prefs.token.isEmpty()) return
        val request = Request.Builder().url(prefs.socketUrl).build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                retry = 2000L
                failures = 0
                webSocket.send(JSONObject().put("op", "hello").put("token", prefs.token).toString())
                // Кнопка, нажатая, пока связи не было, — сразу после приветствия.
                pending?.let { webSocket.send(it) }
                pending = null
                main.post { notifyOngoing("Хоши на связи") }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                val message = runCatching { JSONObject(text) }.getOrNull() ?: return
                when (message.optString("op")) {
                    "state" -> main.post { onState(message); onPlayer(message); onSummary(message) }
                    "error" -> if (message.optString("reason") == "need_pairing") main.post { notifyOngoing("Нужно заново привязать телефон") }
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = reconnect(webSocket)
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = reconnect(webSocket)
        })
    }

    private var failures = 0

    private fun reconnect(closed: WebSocket) {
        main.post {
            if (socket !== closed) return@post // это старое соединение (пульт на виду закрыл его сам)
            socket = null
            if (!running || pageVisible) return@post
            notifyOngoing("Хоши не на связи — жду…")
            failures++
            if (failures % 3 == 0) {
                // Может, сменилась сеть (дом ↔ VPN): проверить запасные адреса ПК.
                Thread {
                    val prefs = Prefs(this)
                    Prefs.pickReachable(prefs)?.let { if (it != prefs.host) prefs.host = it }
                }.start()
            }
            main.postDelayed({ connect() }, retry)
            retry = (retry * 2).coerceAtMost(60_000L)
        }
    }

    /** Карточка Claude поменялась — сказать об этом уведомлением (только о переменах). */
    private fun onState(message: JSONObject) {
        val apps = message.optJSONArray("apps") ?: return
        for (i in 0 until apps.length()) {
            val app = apps.optJSONObject(i) ?: continue
            if (app.optString("id") != "claude") continue
            val state = app.optJSONObject("state") ?: return
            val ask = state.optJSONObject("ask")
            val status = when {
                ask != null -> "ask:" + ask.optString("id")
                else -> state.optString("subtitle")
            }
            if (status == lastClaude) return
            val first = lastClaude.isEmpty()
            lastClaude = status
            if (first) return // сразу после подключения — не звенеть о старом
            val folder = state.optString("title", "Claude")
            when {
                ask != null && ask.optString("kind") == "permission" ->
                    alert("Claude просит разрешение", "$folder: ${ask.optString("tool")} · код ${ask.optString("id")}")
                ask != null -> alert("Claude спрашивает", folder + ": " + firstQuestion(ask))
                status.startsWith("✓") -> alert("Claude закончил ✓", folder + ": " + state.optString("text").take(140))
                status.startsWith("⚠") -> alert("Claude прервался ⚠", "$folder: лимит или ошибка — можно нажать «Продолжай»")
            }
            return
        }
    }

    /** Нажали кнопку плеера app (уведомление, экран блокировки, гарнитура). */
    private fun press(app: String, name: String) {
        if (name == "switch") { // ⇄ — показать другой плеер
            val ids = players.keys.sorted()
            if (ids.size > 1) {
                front = ids[(ids.indexOf(app) + 1) % ids.size]
                renderFront()
            }
            return
        }
        val command = players[app]?.commands?.get(name) ?: return
        val message = JSONObject().put("op", "run").put("command", command.optString("command"))
        command.optJSONObject("args")?.let { message.put("args", it) }
        socket?.send(message.toString())
    }

    /** Плееры на пульте: запомнить каждый, решить, какой на карточке, и показать его. */
    private fun onPlayer(message: JSONObject) {
        val apps = message.optJSONArray("apps") ?: JSONArray()
        val seen = mutableSetOf<String>()
        var started = ""
        // Видео YouTube уже есть своей карточкой — та же вкладка из «Вкладок Chrome» не дублируется.
        var youtubePlaying = false
        for (i in 0 until apps.length()) {
            val app = apps.optJSONObject(i) ?: continue
            if (app.optString("id") == "youtube" && app.optJSONObject("state")?.optBoolean("playing") == true) youtubePlaying = true
        }
        for (i in 0 until apps.length()) {
            val app = apps.optJSONObject(i) ?: continue
            val id = app.optString("id")
            val state = app.optJSONObject("state") ?: continue
            if (id !in PLAYERS || state.optString("title").isEmpty()) continue
            // «Вкладки Chrome» — только когда во вкладке есть видео (иначе там подсказка).
            if (id == "tabs" && (state.has("hint") ||
                    (youtubePlaying && state.optString("subtitle").startsWith("youtube.com")))) continue
            seen.add(id)
            val player = players.getOrPut(id) { Player(newSession(id)) }
            val commands = mutableMapOf<String, JSONObject>()
            val list = app.optJSONArray("commands") ?: JSONArray()
            for (j in 0 until list.length()) {
                val c = list.optJSONObject(j) ?: continue
                val name = c.optString("command").substringAfterLast(":")
                if (name in BUTTONS) commands[name] = c
            }
            val playing = state.optBoolean("playing")
            if (playing && !player.playing) started = id // этот плеер только что заиграл
            player.commands = commands
            player.app = app.optString("title")
            player.title = state.optString("title")
            player.subtitle = state.optString("subtitle")
            player.playing = playing
            player.durationMs = state.optLong("duration") * 1000L
            player.positionMs = state.optLong("time") * 1000L
        }
        for (id in players.keys - seen) players.remove(id)?.session?.release()
        front = when {
            started.isNotEmpty() -> started
            front in seen -> front
            else -> seen.firstOrNull { players[it]?.playing == true } ?: seen.sortedDescending().firstOrNull() ?: ""
        }
        renderFront()
    }

    /** Показать плеер front (или убрать карточку, если плееров нет). */
    private fun renderFront() {
        val player = players[front]
        if (player == null) {
            if (frontKey.isNotEmpty()) manager().cancel(PLAYER_ID)
            frontKey = ""
            return
        }
        val key = listOf(front, player.title, player.playing, player.commands.keys.sorted(), players.size).toString()
        if (key == frontKey) return
        frontKey = key
        for ((id, other) in players) if (id != front) other.session.isActive = false
        showPlayer(front, player, player.app, player.title, player.subtitle, player.playing, player.durationMs, player.positionMs)
    }

    private fun newSession(app: String) = MediaSessionCompat(this, "hoshi_$app").apply {
        setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() = press(app, "toggle")
            override fun onPause() = press(app, "toggle")
            override fun onSkipToNext() = press(app, "next")
            override fun onFastForward() = press(app, "forward")
            override fun onRewind() = press(app, "back")
        })
    }

    private fun showPlayer(id: String, player: Player, app: String, title: String, subtitle: String, playing: Boolean,
                           durationMs: Long, positionMs: Long) {
        val media = player.session
        media.setMetadata(MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "$app · $subtitle")
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .build())
        media.setPlaybackState(PlaybackStateCompat.Builder()
            .setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE or PlaybackStateCompat.ACTION_PLAY or PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or PlaybackStateCompat.ACTION_FAST_FORWARD or PlaybackStateCompat.ACTION_REWIND)
            .setState(if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED, positionMs, if (playing) 1f else 0f)
            .build())
        media.isActive = true
        val builder = NotificationCompat.Builder(this, PLAYER)
            .setSmallIcon(R.drawable.ic_stat_hoshi)
            .setContentTitle(title)
            .setContentText("$app · $subtitle")
            .setContentIntent(openApp())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // кнопки видны на экране блокировки
            .setOngoing(playing)
            .setSilent(true)
        val shown = mutableListOf<Int>()
        var added = 0
        for ((name, icon, label) in listOf(
            Triple("back", android.R.drawable.ic_media_rew, "−10 с"),
            Triple("toggle", if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, "Пауза"),
            Triple("forward", android.R.drawable.ic_media_ff, "+10 с"),
            Triple("next", android.R.drawable.ic_media_next, "Дальше"))) {
            if (!player.commands.containsKey(name)) continue
            builder.addAction(icon, label, pressIntent(id, name))
            if (name != "next") shown.add(added)
            added++
        }
        if (players.size > 1) {
            // ⇄ — на другой плеер; в компактном виде вместо «+10 с», чтобы было видно на экране блокировки.
            val other = players.keys.sorted().let { it[(it.indexOf(id) + 1) % it.size] }
            builder.addAction(android.R.drawable.ic_menu_rotate, "⇄ " + (players[other]?.app ?: ""), pressIntent(id, "switch"))
            if (shown.size >= 3) shown.removeAt(2)
            shown.add(added)
        }
        builder.setStyle(MediaStyle().setMediaSession(media.sessionToken).setShowActionsInCompactView(*shown.take(3).toIntArray()))
        manager().notify(PLAYER_ID, builder.build())
    }

    private fun pressIntent(app: String, name: String): PendingIntent = PendingIntent.getService(
        this, (PLAYERS.indexOf(app) + 1) * 10 + BUTTONS.indexOf(name) + 1,
        Intent(this, HoshiService::class.java).putExtra(EXTRA_APP, app).putExtra(EXTRA_PLAYER, name),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    /** Что сейчас включено (для быстрых кнопок и плиток): звук и выбранное у Хоши. */
    private fun onSummary(message: JSONObject) {
        val summary = JSONObject()
            .put("sound", message.optJSONObject("sound")?.optString("current") ?: "")
            .put("selected", message.optJSONObject("hoshi")?.optJSONArray("selected") ?: JSONArray())
        if (summary.toString() == QuickActions.summary.toString()) return
        QuickActions.summary = summary
        QuickActions.refresh(this)
    }

    private fun firstQuestion(ask: JSONObject): String =
        ask.optJSONArray("questions")?.optJSONObject(0)?.optString("question")?.take(140) ?: ""

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun alert(title: String, text: String) {
        val notification = NotificationCompat.Builder(this, ALERTS)
            .setSmallIcon(R.drawable.ic_stat_hoshi)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(openApp())
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        manager().notify(ALERT_ID, notification)
    }

    private var ongoingText = "Хоши на связи"

    /** «Хоши на связи» + быстрые кнопки (до 3; видны на экране блокировки). */
    private fun ongoing(text: String): Notification {
        ongoingText = text
        val builder = NotificationCompat.Builder(this, QUICK)
            .setSmallIcon(R.drawable.ic_stat_hoshi)
            .setContentTitle("Хоши")
            .setContentText(text)
            .setContentIntent(openApp())
            .setOngoing(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        val items = QuickActions.notifyItems(this)
        if (items.isNotEmpty()) {
            // Кнопки нарисованы прямо в теле уведомления (своё оформление): обычные кнопки
            // уведомления HyperOS прячет, пока его не развернуть.
            val views = RemoteViews(packageName, R.layout.quick_bar)
            views.setTextViewText(R.id.quick_status, text)
            val slots = listOf(R.id.quick_1, R.id.quick_2, R.id.quick_3)
            slots.forEachIndexed { index, id ->
                val item = items.getOrNull(index)
                if (item == null) {
                    views.setViewVisibility(id, android.view.View.INVISIBLE)
                    return@forEachIndexed
                }
                views.setViewVisibility(id, android.view.View.VISIBLE)
                views.setTextViewText(id, (item.optString("icon") + " " + item.optString("title")).trim())
                views.setInt(id, "setBackgroundResource", if (QuickActions.isActive(item)) R.drawable.quick_chip_on else R.drawable.quick_chip)
                views.setOnClickPendingIntent(id, PendingIntent.getService(
                    this, 100 + index, Intent(this, HoshiService::class.java).putExtra(EXTRA_QUICK, index),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle())
                .setCustomContentView(views)
                .setCustomBigContentView(views)
        }
        return builder.build()
    }

    private fun notifyOngoing(text: String) = manager().notify(ONGOING_ID, ongoing(text))

    private fun manager() = getSystemService(NotificationManager::class.java)

    private fun channels() {
        manager().createNotificationChannel(NotificationChannel(ONGOING, "Хоши на связи", NotificationManager.IMPORTANCE_MIN))
        manager().createNotificationChannel(NotificationChannel(ALERTS, "Claude и приложения", NotificationManager.IMPORTANCE_HIGH))
        manager().createNotificationChannel(NotificationChannel(PLAYER, "Плеер (MPC-BE, YouTube)", NotificationManager.IMPORTANCE_LOW))
        // Отдельный канал «Быстрые кнопки»: у старого «Хоши на связи» важность MIN — такие не видны на экране блокировки.
        manager().createNotificationChannel(NotificationChannel(QUICK, "Хоши на связи и быстрые кнопки", NotificationManager.IMPORTANCE_LOW))
    }

    companion object {
        private const val ONGOING = "hoshi_ongoing"
        private const val ALERTS = "hoshi_alerts"
        private const val PLAYER = "hoshi_player"
        private const val PLAYER_ID = 3
        private const val QUICK = "hoshi_quick"
        private const val EXTRA_QUICK = "quick_button"
        /** Кнопка, нажатая без связи: уйдёт сразу после приветствия. */
        @Volatile private var pending: String? = null
        private const val EXTRA_PLAYER = "player_button"
        private const val EXTRA_APP = "player_app"
        private val PLAYERS = listOf("mpc", "youtube", "tabs")
        private val BUTTONS = listOf("back", "toggle", "forward", "next")
        private const val ONGOING_ID = 1
        private const val ALERT_ID = 2
        private const val PING_EVERY = 10_000L

        /** Пульт на экране (ставит MainActivity; общий на всё приложение). */
        @Volatile var pageVisible = false
        private var instance: HoshiService? = null

        /** Запустить (только пока приложение на экране — из фона Android не даёт). */
        fun start(context: Context) {
            runCatching { ContextCompat.startForegroundService(context, Intent(context, HoshiService::class.java)) }
        }

        /** Отправить команду пульта связью службы; нет связи — запомнить до подключения. */
        fun send(command: String, args: JSONObject): Boolean {
            val message = JSONObject().put("op", "run").put("command", command).put("args", args).toString()
            val service = instance ?: run { pending = message; return false }
            val socket = service.socket
            if (socket != null && socket.send(message)) return true
            pending = message
            service.main.post { service.pageChanged() }
            return true
        }

        /** Быстрые кнопки поменялись — перерисовать уведомление. */
        fun refreshQuick() {
            val service = instance ?: return
            service.main.post { service.notifyOngoing(service.ongoingText) }
        }

        /** Пульт появился или скрылся. */
        fun pageShown(visible: Boolean) {
            pageVisible = visible
            instance?.pageChanged()
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, HoshiService::class.java))
        }
    }
}
