package com.privacyshield.privacy_shield

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.os.Bundle

class ProvisioningModeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val action = intent?.action
        if (action != DevicePolicyManager.ACTION_GET_PROVISIONING_MODE) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val result = Intent().apply {
            putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_MODE,
                DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE,
            )
            // Intentionally do NOT set SENSOR_PERMISSION_GRANT_OPT_OUT.
            // Privacy Shield needs device-owner control of camera/mic/location
            // permission grant state for temporary access and fail-closed relock.
        }
        setResult(RESULT_OK, result)
        finish()
    }
}
