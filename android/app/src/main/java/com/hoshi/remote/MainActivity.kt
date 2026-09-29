package com.hoshi.remote

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceResponse
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebStorage
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import android.widget.Toast
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import org.json.JSONArray
import org.json.JSONObject

/**
 * Главный экран: наш пульт (remote/remote.html) прямо с ПК в WebView — поэтому
 * интерфейс обновляется сам, без переустановки. Первый запуск — спросить адрес ПК.
 * Пока экран открыт, связь держит сама страница; ушли с экрана — HoshiService.
 */
class MainActivity : AppCompatActivity() {
    private lateinit var prefs: Prefs
    private var web: WebView? = null
    private var remoteLoaded = false
    private var pendingAssistant: Pair<String, String>? = null
    private var pendingPairCode: String? = null
    private var connectGeneration = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastUpdateCheck = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        prefs = Prefs(this)
        rememberAssistant(intent)
        askNotificationsOnce()
        beginConnection()
        handleSettingsAction(intent)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val view = web
                if (view != null && view.canGoBack()) view.goBack() else moveTaskToBack(true)
            }
        })
    }

    override fun onResume() {
        super.onResume()
        // Экран на виду: связь держит страница; служба молчит, но работает — запускать её
        // надо сейчас, пока приложение на экране (при блокировке Android уже не даст).
        HoshiService.pageShown(true)
        ensureService()
        val pageHost = web?.url?.let { Uri.parse(it).host }
        if (remoteLoaded && pageHost != null && pageHost != prefs.host) beginConnection()
        else web?.onResume()
        maybeCheckUpdate()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberAssistant(intent)
        handleSettingsAction(intent)
    }

    private fun handleSettingsAction(source: Intent?) {
        when (source?.getStringExtra(EXTRA_SETTINGS_ACTION)) {
            "setup" -> showSetup(null)
            "reload" -> beginConnection()
            "disconnect" -> {
                prefs.token = ""
                HoshiService.stop(this)
                WebStorage.getInstance().deleteAllData()
                showSetup("Привязка на этом телефоне удалена.")
            }
        }
        source?.removeExtra(EXTRA_SETTINGS_ACTION)
    }

    private fun rememberAssistant(source: Intent?) {
        val app = source?.getStringExtra("assistant_app") ?: return
        val session = source.getStringExtra("assistant_session") ?: return
        if (app !in listOf("claude", "codex") || session.length !in 1..64) return
        pendingAssistant = app to session
        deliverAssistantTarget()
    }

    private fun deliverAssistantTarget() {
        val target = pendingAssistant ?: return
        val view = web ?: return
        if (!remoteLoaded) return
        view.evaluateJavascript(
            "window.showAssistantFromAndroid(${JSONObject.quote(target.first)},${JSONObject.quote(target.second)})",
            null)
        pendingAssistant = null
    }

    override fun onPause() {
        super.onPause()
        web?.onPause()
        // Ушли с экрана или заблокировали телефон: связь и уведомления — на службе.
        HoshiService.pageShown(false)
    }

    private fun ensureService() {
        if (prefs.host.isNotEmpty() && prefs.token.isNotEmpty()) HoshiService.start(this)
    }

    /** Проверяем все адреса до загрузки WebView: плохой IP никогда не становится белым экраном. */
    private fun beginConnection(only: List<String>? = null, replaceComputer: Boolean = false) {
        val step = if (only == null) ConnectionFlow.initial(prefs.host, prefs.hosts)
            else if (only.isEmpty()) EntryStep.Setup else EntryStep.Probe(only)
        if (step == EntryStep.Setup) {
            showSetup("Адрес Хоши пока не задан. Отсканируй QR с компьютера или введи адрес.")
            return
        }
        val candidates = (step as EntryStep.Probe).candidates
        val attempt = ++connectGeneration
        showConnecting(candidates)
        Thread {
            val report = ConnectionFlow.probe(candidates, Prefs::probeHost)
            runOnUiThread {
                if (attempt != connectGeneration || isFinishing || isDestroyed) return@runOnUiThread
                if (report.found == null) {
                    val details = report.checked.joinToString("\n") { "${it.host}: ${it.failure}" }
                    showSetup("Не удалось связаться с Хоши. Проверка адресов:\n$details\n\n" +
                        "Если адрес открывается в браузере, а здесь нет, проверь правила AmneziaVPN для приложения «Хоши».")
                } else {
                    val found = report.found
                    if (replaceComputer) {
                        prefs.token = ""
                        HoshiService.stop(this)
                        prefs.hosts = listOf(found)
                    }
                    prefs.host = found
                    openRemote(found, attempt, candidates)
                }
            }
        }.start()
    }

    private fun replacePage(page: View) {
        setContentView(page)
        web?.let { old -> old.stopLoading(); old.destroy() }
        web = null
        remoteLoaded = false
    }

    private fun nativeColumn(): Pair<ScrollView, LinearLayout> {
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(Color.parseColor("#FBF5F1"))
        }
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(32))
        }
        scroll.addView(column)
        column.addView(ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            contentDescription = "Хоши"
        }, LinearLayout.LayoutParams(dp(84), dp(84)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        column.addView(TextView(this).apply {
            text = "Хоши"
            textSize = 29f
            setTextColor(Color.parseColor("#665479"))
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(8))
        })
        return scroll to column
    }

    private fun nativeMessage(column: LinearLayout, message: String) {
        column.addView(TextView(this).apply {
            text = message
            textSize = 15f
            setTextColor(Color.parseColor("#3B3449"))
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(20))
        })
    }

    private fun nativeButton(column: LinearLayout, title: String, action: () -> Unit) {
        column.addView(Button(this).apply {
            text = title
            isAllCaps = false
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply { topMargin = dp(6) })
    }

    /** Обновление доступно и с родного экрана, когда WebView ещё не загрузился. */
    private fun maybeCheckUpdate() {
        if (ConnectionFlow.candidates(prefs.host, prefs.hosts).isEmpty()) return
        val now = SystemClock.elapsedRealtime()
        if (lastUpdateCheck != 0L && now - lastUpdateCheck < 10 * 60 * 1000L) return
        lastUpdateCheck = now
        Updater(this, prefs).checkLater()
    }

    private fun showConnecting(candidates: List<String>) {
        val (scroll, column) = nativeColumn()
        column.addView(ProgressBar(this), LinearLayout.LayoutParams(dp(32), dp(32)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = dp(12)
        })
        nativeMessage(column, "Ищу Хоши по сохранённым адресам…\n${candidates.joinToString(" · ")}")
        nativeButton(column, "Сканировать QR") { scanQr() }
        nativeButton(column, "Ввести адрес вручную") { showSetup(null) }
        nativeButton(column, "Настройки приложения") { startActivity(Intent(this, SettingsActivity::class.java)) }
        replacePage(scroll)
    }

    /** Экран «Адрес ПК» остаётся доступен и без ответа от WebView или ПК. */
    private fun showSetup(problem: String?) {
        connectGeneration++
        val (scroll, column) = nativeColumn()
        nativeMessage(column, (problem?.let { "$it\n\n" } ?: "") +
            "Открой на компьютере «Пульт с телефона» и отсканируй QR. Адрес также можно ввести вручную.")
        val address = EditText(this).apply {
            hint = "192.168.0.94"
            setText(prefs.host)
            setSingleLine()
            gravity = Gravity.CENTER
        }
        column.addView(address, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        nativeButton(column, "Подключиться") {
            val host = Prefs.cleanHost(address.text.toString())
            if (host.isNotEmpty()) {
                pendingPairCode = null
                val choice = ConnectionFlow.manualAttempt(host, prefs.host, prefs.hosts)
                beginConnection(choice.candidates, replaceComputer = choice.replaceComputer)
            }
        }
        nativeButton(column, "Сканировать QR с экрана ПК") { scanQr() }
        val savedHosts = ConnectionFlow.candidates(prefs.host, prefs.hosts)
        if (savedHosts.isNotEmpty()) {
            nativeButton(column, "Повторить поиск по сохранённым адресам") { beginConnection() }
            nativeButton(column, "Проверить обновление") { Updater(this, prefs).check(showNothingNew = true) }
            nativeMessage(column, "Если проверка обновления здесь не работает, открой APK в браузере телефона:")
            for (host in savedHosts) {
                nativeButton(column, "Скачать через $host") {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("http://$host:${Prefs.HTTP_PORT}/app/hoshi.apk")))
                }
            }
        }
        nativeButton(column, "Настройки приложения") { startActivity(Intent(this, SettingsActivity::class.java)) }
        replacePage(scroll)
        maybeCheckUpdate()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()

    /** QR из окна «Пульт с телефона»: http://<ПК>:18770/#pair=<код> — адрес и привязка сразу. */
    private fun scanQr() {
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { code -> onScanned(code.rawValue ?: "") }
            .addOnFailureListener { toast("Сканер не запустился — введи адрес вручную") }
    }

    private fun onScanned(text: String) {
        val link = ConnectionFlow.pairingLink(text)
        if (link == null) {
            toast("Это не QR Хоши — открой на ПК «Пульт с телефона»")
            return
        }
        prefs.token = ""
        HoshiService.stop(this)
        prefs.hosts = link.hosts
        prefs.host = link.hosts.first()
        pendingPairCode = link.code
        lastUpdateCheck = 0L
        beginConnection()
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()

    @SuppressLint("SetJavaScriptEnabled")
    private fun openRemote(host: String, attempt: Int, candidates: List<String>) {
        val view = WebView(this)
        val frame = FrameLayout(this)
        val (waiting, waitingColumn) = nativeColumn()
        waitingColumn.addView(ProgressBar(this), LinearLayout.LayoutParams(dp(32), dp(32)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = dp(12)
        })
        nativeMessage(waitingColumn, "Открываю пульт по адресу $host…")
        nativeButton(waitingColumn, "Сменить адрес или сканировать QR") { showSetup(null) }
        frame.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        frame.addView(waiting, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        view.visibility = View.INVISIBLE
        setContentView(frame)
        web = view
        remoteLoaded = false
        var failed = false
        var pageLoadVersion = 0

        fun failPage(reason: String) {
            if (failed || attempt != connectGeneration || web !== view) return
            failed = true
            mainHandler.post {
                if (attempt != connectGeneration || web !== view) return@post
                val remaining = candidates.filterNot { it == host }
                if (remaining.isEmpty()) showSetup(reason) else beginConnection(remaining)
            }
        }

        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true // страница хранит ключ привязки в localStorage
        view.settings.mediaPlaybackRequiresUserGesture = true
        view.setBackgroundColor(Color.parseColor("#FBF5F1"))
        view.addJavascriptInterface(Bridge(attempt), "HoshiApp")
        view.webChromeClient = WebChromeClient()
        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(v: WebView, url: String, favicon: Bitmap?) {
                if (failed || attempt != connectGeneration || web !== v) return
                pageLoadVersion++
                val load = pageLoadVersion
                remoteLoaded = false
                v.visibility = View.INVISIBLE
                if (waiting.parent == null) {
                    frame.addView(waiting, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                }
                mainHandler.postDelayed({
                    if (load == pageLoadVersion && !remoteLoaded && !failed && attempt == connectGeneration && web === v) {
                        failPage("Страница Хоши долго не открывается по адресу $host. Попробуй другой адрес или QR.")
                    }
                }, 12_000L)
            }

            override fun onPageFinished(v: WebView, url: String) {
                if (failed || attempt != connectGeneration || web !== v) return
                // An error page can also call onPageFinished. Reveal only Hoshi's real page.
                v.evaluateJavascript("!!(document.getElementById('pair') && document.getElementById('remote'))") { ready ->
                    if (failed || attempt != connectGeneration || web !== v) return@evaluateJavascript
                    if (ready != "true") {
                        failPage("Страница Хоши не загрузилась с адреса $host.")
                        return@evaluateJavascript
                    }
                    frame.removeView(waiting)
                    v.visibility = View.VISIBLE
                    remoteLoaded = true
                    deliverAssistantTarget()
                    maybeCheckUpdate()
                }
            }

            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                // Свои страницы Хоши (пульт, картинки /media/…) — внутри; чужие ссылки — в браузере.
                if (url.host == host && url.port == Prefs.HTTP_PORT) return false
                startActivity(Intent(Intent.ACTION_VIEW, url))
                return true
            }

            override fun onReceivedError(v: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (!request.isForMainFrame) return
                failPage("Не удалось открыть Хоши по адресу $host. Проверь Wi-Fi или VPN.")
            }

            override fun onReceivedHttpError(v: WebView, request: WebResourceRequest, response: WebResourceResponse) {
                if (request.isForMainFrame) failPage("Хоши вернула ошибку ${response.statusCode} по адресу $host.")
            }
        }
        // С кодом из QR страница привяжется сама (#pair=…) и отдаст приложению ключ.
        view.loadUrl("http://$host:${Prefs.HTTP_PORT}/" + (pendingPairCode?.let { "#pair=$it" } ?: ""))
    }

    private fun askNotificationsOnce() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    /** Что страница пульта может сказать приложению (window.HoshiApp). */
    inner class Bridge(private val attempt: Int) {
        /** Страница привязалась или поздоровалась ключом — службе он нужен для фоновой связи. */
        @JavascriptInterface
        fun setToken(token: String) {
            if (token.length in 16..128 && token.all { it.isLetterOrDigit() }) {
                runOnUiThread {
                    if (attempt != connectGeneration) return@runOnUiThread
                    prefs.token = token
                    pendingPairCode = null
                    ensureService()
                } // только что привязались — служба нужна уже сейчас
            }
        }

        @JavascriptInterface
        fun version(): String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

        /** Сменить адрес ПК (кнопка на странице, когда появится). */
        @JavascriptInterface
        fun changeAddress() {
            runOnUiThread { showSetup(null) }
        }

        /** The loaded page lost its socket for long enough to try the saved IPs again. */
        @JavascriptInterface
        fun connectionLost() {
            runOnUiThread {
                if (attempt == connectGeneration && remoteLoaded) beginConnection()
            }
        }

        /** Быстрые кнопки телефона: страница показывает выбор и сохраняет его. */
        @JavascriptInterface
        fun getQuickActions(): String = JSONObject()
            .put("notify", JSONArray(prefs.quickNotify)).put("tiles", JSONArray(prefs.quickTiles)).toString()

        @JavascriptInterface
        fun setQuickActions(json: String) {
            QuickActions.save(this@MainActivity, json)
        }

        /** Страница сообщает, что включено (звук, режимы) — чтобы плитки горели правильно. */
        @JavascriptInterface
        fun onState(json: String) {
            val summary = runCatching { JSONObject(json) }.getOrNull() ?: return
            if (summary.toString() == QuickActions.summary.toString()) return
            QuickActions.summary = summary
            QuickActions.refresh(this@MainActivity)
        }

        /** Кнопка «📷 Сканировать QR» на странице привязки. */
        @JavascriptInterface
        fun scanQr() {
            runOnUiThread { this@MainActivity.scanQr() }
        }

        @JavascriptInterface
        fun checkUpdate() {
            runOnUiThread { Updater(this@MainActivity, prefs).check(showNothingNew = true) }
        }

        @JavascriptInterface
        fun openSettings() {
            runOnUiThread { startActivity(Intent(this@MainActivity, SettingsActivity::class.java)) }
        }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_SETTINGS_ACTION = "settings_action"
        private var instance: MainActivity? = null

        /** Пульт на экране: нажать кнопку через саму страницу (её связь с Хоши). */
        fun runOnPage(command: String, args: JSONObject): Boolean {
            val activity = instance ?: return false
            val view = activity.web ?: return false
            val script = "run(" + JSONObject.quote(command) + ", " + args.toString() + ")"
            activity.runOnUiThread { view.evaluateJavascript(script, null) }
            return true
        }

        fun openSettings(activity: AppCompatActivity, action: String) {
            activity.startActivity(Intent(action, Uri.parse("package:${activity.packageName}")))
        }
    }
}
