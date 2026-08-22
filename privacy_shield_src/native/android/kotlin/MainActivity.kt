package com.privacyshield.privacy_shield

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.telecom.TelecomManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "privacy_shield/native"
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                val manager = NativePolicyManager(this)
                when (call.method) {
                    "getStatus" -> runAsync(result) { statusMap(manager) }
                    "getSetupDiagnostics" -> result.success(setupDiagnostics(manager))
                    "listApps" -> runAsync(result) { listApps() }
                    "getBlockedPolicies" -> runAsync(result) { manager.blockedPolicies() }
                    "setBlocked" -> runAsync(result) {
                        manager.setBlocked(call.arg("packageName"), call.arg("sensor"), call.arg("blocked"))
                        null
                    }
                    "temporaryGrant" -> runAsync(result) {
                        manager.temporaryGrant(
                            call.arg("packageName"),
                            call.arg("sensor"),
                            (call.argument<Number>("durationMs") ?: 120000).toLong(),
                        )
                        null
                    }
                    "revokeNow" -> runAsync(result) {
                        manager.revokeNow(call.arg("packageName"), call.arg("sensor"))
                        null
                    }
                    "getActiveSessions" -> runAsync(result) { manager.activeSessions() }
                    "setPanic" -> runAsync(result) {
                        manager.setPanic(call.arg("enabled"))
                        null
                    }
                    "repairPolicies" -> runAsync(result) { manager.repairPolicies() }
                    "launchApp" -> result.success(launchTarget(call.arg("packageName")))
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "openPrivacySettings" -> {
                        startActivity(Intent(Settings.ACTION_PRIVACY_SETTINGS))
                        result.success(null)
                    }
                    "openDeviceAdminSettings" -> {
                        openDeviceAdminActivation()
                        result.success(null)
                    }
                    "startNetworkShield" -> result.success(startNetworkShield())
                    "stopNetworkShield" -> {
                        stopService(Intent(this, NetworkShieldService::class.java))
                        result.success(null)
                    }
                    "trackerStats" -> result.success(mapOf("blockedToday" to NetworkShieldService.blockedToday(this)))
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null)
            }
        }
    }

    override fun onDestroy() {
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun statusMap(manager: NativePolicyManager): Map<String, Any> = mapOf(
        "isDeviceOwner" to manager.isDeviceOwner,
        "canGrantSensors" to manager.canGrantSensors,
        "canScheduleExactAlarms" to manager.canScheduleExactAlarms,
        "panicEnabled" to manager.panicEnabled,
        "panicDegraded" to manager.panicDegraded,
        "policyDriftCount" to manager.policyDriftCount(),
        "watchdogRunning" to SessionWatchdogService.isRunning(),
        "networkShieldEnabled" to NetworkShieldService.isActuallyRunning(this),
        "otherVpnActive" to NetworkShieldService.hasOtherVpn(this),
        "vpnPrepared" to (VpnService.prepare(this) == null),
    )

    @Suppress("DEPRECATION")
    private fun setupDiagnostics(manager: NativePolicyManager): Map<String, Any> {
        val dpm = getSystemService(DevicePolicyManager::class.java)
        val admin = ComponentName(this, PrivacyAdminReceiver::class.java)
        val deviceProvisioned = Settings.Global.getInt(contentResolver, Settings.Global.DEVICE_PROVISIONED, 0) != 0
        val provisioningAllowed = runCatching {
            dpm.isProvisioningAllowed(DevicePolicyManager.ACTION_PROVISION_MANAGED_DEVICE)
        }.getOrDefault(false)
        return mapOf(
            "isAdminActive" to dpm.isAdminActive(admin),
            "isDeviceOwner" to manager.isDeviceOwner,
            "deviceProvisioned" to deviceProvisioned,
            "provisioningAllowed" to provisioningAllowed,
            "canGrantSensors" to manager.canGrantSensors,
            "canScheduleExactAlarms" to manager.canScheduleExactAlarms,
            "adminComponent" to "${packageName}/.PrivacyAdminReceiver",
            "adbCommand" to "adb shell dpm set-device-owner ${packageName}/.PrivacyAdminReceiver",
        )
    }

    private fun listApps(): List<Map<String, Any>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val launcherPackages = packageManager.queryIntentActivities(launcher, PackageManager.MATCH_ALL)
            .map { it.activityInfo.packageName }
            .toSet()

        val telecom = getSystemService(TelecomManager::class.java)
        val defaultDialer = runCatching { telecom.defaultDialerPackage }.getOrNull()
        val systemDialer = runCatching { telecom.systemDialerPackage }.getOrNull()

        val installed = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(0)
        }

        return installed.asSequence()
            .filter { it.packageName != packageName }
            .mapNotNull { appInfo ->
                val target = appInfo.packageName
                runCatching {
                    val requested = requestedPermissions(target)
                    val hasCamera = requested.contains(Manifest.permission.CAMERA)
                    val hasMicrophone = requested.contains(Manifest.permission.RECORD_AUDIO)
                    val hasLocation = requested.contains(Manifest.permission.ACCESS_COARSE_LOCATION) ||
                        requested.contains(Manifest.permission.ACCESS_FINE_LOCATION) ||
                        requested.contains(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                    if (!hasCamera && !hasMicrophone && !hasLocation) return@runCatching null

                    val systemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    val critical = appInfo.uid < Process.FIRST_APPLICATION_UID ||
                        target == defaultDialer ||
                        target == systemDialer ||
                        target in CORE_CRITICAL_PACKAGES ||
                        (systemApp && target !in launcherPackages)

                    mapOf(
                        "packageName" to target,
                        "label" to packageManager.getApplicationLabel(appInfo).toString(),
                        "hasCamera" to hasCamera,
                        "hasMicrophone" to hasMicrophone,
                        "hasLocation" to hasLocation,
                        "systemApp" to systemApp,
                        "criticalSystem" to critical,
                        "enabled" to appInfo.enabled,
                    )
                }.getOrNull()
            }
            .filterNotNull()
            .sortedBy { (it["label"] as String).lowercase() }
            .toList()
    }

    private fun requestedPermissions(target: String): Set<String> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(target, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(target, PackageManager.GET_PERMISSIONS)
        }
        return info.requestedPermissions?.toSet() ?: emptySet()
    }

    private fun launchTarget(target: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(target) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    private fun openDeviceAdminActivation() {
        val admin = ComponentName(this, PrivacyAdminReceiver::class.java)
        startActivity(
            Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Privacy Shield يحتاج Device Admin كخطوة إدارة فقط. Full Device Owner يحتاج provisioning نظامي أو جهاز اختبار نظيف.",
                )
            },
        )
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= 31) {
            startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                },
            )
        }
    }

    private fun startNetworkShield(): Boolean {
        if (NetworkShieldService.hasOtherVpn(this) && !NetworkShieldService.isActuallyRunning(this)) {
            throw IllegalStateException("يوجد VPN آخر فعال. أوقفه أولًا حتى لا يتم قطع اتصاله دون قصد.")
        }
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivity(prepare)
            return false
        }
        val intent = Intent(this, NetworkShieldService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        return true
    }

    private fun <T> runAsync(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (t: Throwable) {
                runOnUiThread { result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null) }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> io.flutter.plugin.common.MethodCall.arg(key: String): T =
        argument<T>(key) ?: throw IllegalArgumentException("Missing argument: $key")

    companion object {
        private val CORE_CRITICAL_PACKAGES = setOf(
            "com.android.systemui",
            "com.android.settings",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.phone",
            "com.android.shell",
            "com.google.android.gms",
        )
    }
}
