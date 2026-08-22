package com.privacyshield.privacy_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PermissionAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.getStringExtra("packageName") ?: return
        val sensor = intent.getStringExtra("sensor") ?: return
        runCatching { NativePolicyManager(context).revokeNow(packageName, sensor) }
    }
}
