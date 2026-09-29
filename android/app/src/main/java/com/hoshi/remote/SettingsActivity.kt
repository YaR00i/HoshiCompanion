package com.hoshi.remote

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

/** Настройки оболочки остаются доступны, даже если страница пульта с ПК не загрузилась. */
class SettingsActivity : AppCompatActivity() {
    private lateinit var prefs: Prefs
    private lateinit var connection: TextView
    private lateinit var addresses: TextView
    private lateinit var update: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = Prefs(this)
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.rgb(251, 245, 241)) }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(28), dp(20), dp(36))
        }
        scroll.addView(content)
        setContentView(scroll)

        button(content, "← Вернуться к пульту") { finish() }
        content.addView(label("Настройки Хоши", 27f, "#665479", true))
        content.addView(label("Приложение на телефоне", 13f, "#8B8198"))

        val versionCard = card(content)
        versionCard.addView(label("Версия приложения", 13f, "#8B8198"))
        versionCard.addView(label("${BuildConfig.VERSION_NAME} · сборка ${BuildConfig.VERSION_CODE}", 21f, "#3B3449", true))
        update = label("Проверяю доступную версию…", 13f, "#8B8198")
        versionCard.addView(update)
        button(versionCard, "Проверить обновление") {
            Updater(this, prefs).check(showNothingNew = true)
            refreshStatus()
        }

        val connectionCard = card(content)
        connectionCard.addView(label("Компьютер", 13f, "#8B8198"))
        connection = label("Проверяю связь…", 16f, "#3B3449", true)
        connectionCard.addView(connection)
        addresses = label("", 13f, "#8B8198")
        connectionCard.addView(addresses)
        button(connectionCard, "Сменить компьютер") { backToRemote("setup") }

        val actions = card(content)
        actions.addView(label("Приложение", 13f, "#8B8198"))
        button(actions, "Обновить страницу пульта") { backToRemote("reload") }
        button(actions, "Забыть привязку на телефоне") {
            AlertDialog.Builder(this)
                .setTitle("Забыть привязку?")
                .setMessage("Ключ связи с Хоши будет удалён с этого телефона. Для повторного подключения понадобится код или QR с компьютера.")
                .setPositiveButton("Забыть") { _, _ -> backToRemote("disconnect") }
                .setNegativeButton("Отмена", null)
                .show()
        }
        button(actions, "Закрыть Хоши") {
            HoshiService.stop(this)
            finishAffinity()
        }
        refreshStatus()
    }

    private fun refreshStatus() {
        val candidates = ConnectionFlow.candidates(prefs.host, prefs.hosts)
        addresses.text = if (candidates.isEmpty()) "Адреса: не заданы" else "Сохранённые адреса: ${candidates.joinToString(" · ")}"
        if (candidates.isEmpty()) {
            connection.text = "Компьютер ещё не выбран"
            update.text = "Для проверки обновления подключись к ПК"
            return
        }
        Thread {
            val found = ConnectionFlow.resolve(candidates, Prefs::reachable)
            if (found != null) prefs.host = found
            val available = found?.let(Updater::availableAt)
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                connection.text = if (found != null) "Хоши на связи · $found" else "Хоши сейчас недоступна"
                update.text = when {
                    available == null -> "Не удалось узнать версию на ПК"
                    available.code > BuildConfig.VERSION_CODE -> "Доступна версия ${available.name} · нажми «Проверить обновление»"
                    else -> "На ПК доступна версия ${available.name} · обновление не требуется"
                }
            }
        }.start()
    }

    private fun backToRemote(action: String) {
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_SETTINGS_ACTION, action))
        finish()
    }

    private fun card(parent: LinearLayout): LinearLayout {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(15), dp(18), dp(16))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(22).toFloat()
                setStroke(dp(1), Color.rgb(234, 221, 227))
            }
        }
        parent.addView(box, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(18)
        })
        return box
    }

    private fun label(text: String, size: Float, color: String, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(Color.parseColor(color))
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, dp(4), 0, dp(4))
    }

    private fun button(parent: LinearLayout, title: String, action: () -> Unit) {
        parent.addView(Button(this).apply {
            text = title
            isAllCaps = false
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(Color.rgb(102, 84, 121))
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(48)).apply { topMargin = dp(5) })
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()
}
