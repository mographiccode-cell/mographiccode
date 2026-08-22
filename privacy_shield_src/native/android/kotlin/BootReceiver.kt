package com.privacyshield.privacy_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(
                Intent.ACTION_LOCKED_BOOT_COMPLETED,
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
            )
        ) return

        val pending = goAsync()
        thread(name = "privacy-boot-repair") {
            try {
                runCatching { NativePolicyManager(context).repairPolicies() }
            } finally {
                pending.finish()
            }
        }
    }
}
