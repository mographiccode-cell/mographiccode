package com.privacyshield.privacy_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

class PackageChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.data?.schemeSpecificPart ?: return
        if (packageName == context.packageName) return
        val action = intent.action
        val replacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
        val pending = goAsync()
        thread(name = "privacy-package-repair") {
            try {
                val manager = NativePolicyManager(context)
                when (action) {
                    Intent.ACTION_PACKAGE_REMOVED -> {
                        if (!replacing) runCatching { manager.removePackage(packageName) }
                    }
                    Intent.ACTION_PACKAGE_ADDED,
                    Intent.ACTION_PACKAGE_REPLACED -> runCatching { manager.repairPackage(packageName) }
                }
            } finally {
                pending.finish()
            }
        }
    }
}
