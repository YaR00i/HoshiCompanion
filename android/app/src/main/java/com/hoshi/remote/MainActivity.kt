package com.hoshi.remote

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        prefs = Prefs(this)
        askNotificationsOnce()
        if (prefs.host.isEmpty()) showSetup(null) else showRemote()
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
        web?.onResume()
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

    /** Экран «Адрес ПК»: один раз, или если Хоши не нашлась. */
    private fun showSetup(problem: String?) {
        web?.destroy()
        web = null
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(56, 56, 56, 56)
            setBackgroundColor(Color.parseColor("#FBF5F1"))
        }
        column.addView(TextView(this).apply {
            text = "✦ Хоши"
            textSize = 30f
            setTextColor(Color.parseColor("#665479"))
            gravity = Gravity.CENTER
        })
        column.addView(TextView(this).apply {
            text = (problem?.let { "$it\n\n" } ?: "") +
                "Адрес ПК с Хоши — как в окне «Пульт с телефона» (например 192.168.0.94)."
            textSize = 15f
            setTextColor(Color.parseColor("#3B3449"))
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 24)
        })
        val address = EditText(this).apply {
            hint = "192.168.0.94"
            setText(prefs.host)
            setSingleLine()
            gravity = Gravity.CENTER
        }
        column.addView(address, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        column.addView(Button(this).apply {
            text = "Подключиться"
            setOnClickListener {
                val host = Prefs.cleanHost(address.text.toString())
                if (host.isNotEmpty()) {
                    prefs.host = host
                    showRemote()
                }
            }
        })
        column.addView(Button(this).apply {
            text = "📷 Сканировать QR с экрана ПК"
            setOnClickListener { scanQr() }
        })
        setContentView(column)
    }

    /** QR из окна «Пульт с телефона»: http://<ПК>:18770/#pair=<код> — адрес и привязка сразу. */
    private fun scanQr() {
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { code -> onScanned(code.rawValue ?: "") }
            .addOnFailureListener { toast("Сканер не запустился — введи адрес вручную") }
    }

    private fun onScanned(text: String) {
        val host = Prefs.cleanHost(text)
        val pair = Regex("pair=(\\d{6})").find(text)?.groupValues?.get(1)
        if (host.isEmpty() || !text.contains(":${Prefs.HTTP_PORT}")) {
            toast("Это не QR Хоши — открой на ПК «Пульт с телефона»")
            return
        }
        // Запасные адреса (другие сети ПК: дом/VPN) — взять тот, что отвечает сейчас.
        val alts = Regex("alt=([0-9.,]+)").find(text)?.groupValues?.get(1)?.split(",")?.map { Prefs.cleanHost(it) }?.filter { it.isNotEmpty() } ?: emptyList()
        prefs.hosts = listOf(host) + alts
        prefs.host = host
        toast("Ищу Хоши…")
        Thread {
            val alive = Prefs.pickReachable(prefs) ?: host
            runOnUiThread {
                prefs.host = alive
                showRemote(pair)
            }
        }.start()
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()

    @SuppressLint("SetJavaScriptEnabled")
    private fun showRemote(pair: String? = null) {
        val view = WebView(this)
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true // страница хранит ключ привязки в localStorage
        view.settings.mediaPlaybackRequiresUserGesture = true
        view.setBackgroundColor(Color.parseColor("#FBF5F1"))
        view.addJavascriptInterface(Bridge(), "HoshiApp")
        view.webChromeClient = WebChromeClient()
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                // Свои страницы Хоши (пульт, картинки /media/…) — внутри; чужие ссылки — в браузере.
                if (url.host == prefs.host && url.port == Prefs.HTTP_PORT) return false
                startActivity(Intent(Intent.ACTION_VIEW, url))
                return true
            }

            override fun onReceivedError(v: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (!request.isForMainFrame) return
                // Основной адрес не отвечает — может, сменилась сеть (дом ↔ VPN): попробовать запасные.
                val failed = prefs.host
                Thread {
                    val alive = Prefs.pickReachable(prefs)
                    runOnUiThread {
                        if (alive != null && alive != failed) {
                            prefs.host = alive
                            showRemote()
                        } else {
                            showSetup("Не достучалась до Хоши по адресу $failed. Хоши запущена и пульт включён?")
                        }
                    }
                }.start()
            }
        }
        web?.destroy()
        web = view
        setContentView(view)
        // С кодом из QR страница привяжется сама (#pair=…) и отдаст приложению ключ.
        view.loadUrl(prefs.pageUrl + (pair?.let { "#pair=$it" } ?: ""))
        Updater(this, prefs).checkLater()
    }

    private fun askNotificationsOnce() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    /** Что страница пульта может сказать приложению (window.HoshiApp). */
    inner class Bridge {
        /** Страница привязалась или поздоровалась ключом — службе он нужен для фоновой связи. */
        @JavascriptInterface
        fun setToken(token: String) {
            if (token.length in 16..128 && token.all { it.isLetterOrDigit() }) {
                prefs.token = token
                runOnUiThread { ensureService() } // только что привязались — служба нужна уже сейчас
            }
        }

        @JavascriptInterface
        fun version(): String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

        /** Сменить адрес ПК (кнопка на странице, когда появится). */
        @JavascriptInterface
        fun changeAddress() {
            runOnUiThread { showSetup(null) }
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
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
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
