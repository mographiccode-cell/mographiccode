package com.privacyshield.privacy_shield

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class PrivacyTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val manager = NativePolicyManager(this)
        if (!manager.isDeviceOwner) {
            val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT >= 34) {
                val pi = PendingIntent.getActivity(this, 10, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                startActivityAndCollapse(pi)
            } else {
                startActivityAndCollapse(intent)
            }
            return
        }
        runCatching { manager.setPanic(!manager.panicEnabled) }
        updateTile()
    }

    private fun updateTile() {
        val manager = NativePolicyManager(this)
        qsTile?.apply {
            state = if (manager.isDeviceOwner && manager.panicEnabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            label = if (manager.panicEnabled) "Privacy: LOCKED" else "Privacy Shield"
            updateTile()
        }
    }
}
