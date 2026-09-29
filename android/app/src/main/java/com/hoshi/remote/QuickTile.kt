package com.hoshi.remote

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Плитка «Хоши» в быстрых настройках (шторка). Шесть мест (QuickTile1…6); что
 * делает каждое — выбирается в приложении («Быстрые кнопки телефона»). Горит, если
 * выбранное сейчас включено (звук идёт в это устройство, режим Хоши выбран).
 */
abstract class QuickTile(private val slot: Int) : TileService() {

    private fun item() = QuickActions.tileItems(this).getOrNull(slot - 1)

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val item = item()
        tile.icon = Icon.createWithResource(this, R.drawable.ic_stat_hoshi)
        if (item == null) {
            tile.label = "Хоши $slot"
            if (Build.VERSION.SDK_INT >= 29) tile.subtitle = "не задано"
            tile.state = Tile.STATE_UNAVAILABLE
        } else {
            tile.label = item.optString("title")
            if (Build.VERSION.SDK_INT >= 29) tile.subtitle = "Хоши"
            tile.state = if (QuickActions.isActive(item)) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val item = item() ?: return
        QuickActions.run(this, item)
    }
}

class QuickTile1 : QuickTile(1)
class QuickTile2 : QuickTile(2)
class QuickTile3 : QuickTile(3)
class QuickTile4 : QuickTile(4)
class QuickTile5 : QuickTile(5)
class QuickTile6 : QuickTile(6)
