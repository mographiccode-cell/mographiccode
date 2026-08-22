package com.privacyshield.privacy_shield

import android.Manifest
import android.app.AlarmManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "privacy_shield/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                val manager = NativePolicyManager(this)
                when (call.method) {
                    "getStatus" -> result.success(statusMap(manager))
                    "listApps" -> result.success(listApps())
                    "getBlockedPolicies" -> result.success(manager.blockedPolicies())
                    "setBlocked" -> {
                        manager.setBlocked(call.arg("packageName"), call.arg("sensor"), call.arg("blocked"))
                        result.success(null)
                    }
                    "temporaryGrant" -> {
                        manager.temporaryGrant(
                            call.arg("packageName"), call.arg("sensor"),
                            (call.argument<Number>("durationMs") ?: 120000).toLong(),
                        )
                        result.success(null)
                    }
                    "revokeNow" -> {
                        manager.revokeNow(call.arg("packageName"), call.arg("sensor"))
                        result.success(null)
                    }
                    "getActiveSessions" -> result.success(manager.activeSessions())
                    "setPanic" -> {
                        manager.setPanic(call.arg("enabled"))
                        result.success(null)
                    }
                    "repairPolicies" -> result.success(manager.repairPolicies())
                    "launchApp" -> result.success(launchTarget(call.arg("packageName")))
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings(); result.success(null)
                    }
                    "openPrivacySettings" -> {
                        startActivity(Intent(Settings.ACTION_PRIVACY_SETTINGS)); result.success(null)
                    }
                    "startNetworkShield" -> result.success(startNetworkShield())
                    "stopNetworkShield" -> {
                        stopService(Intent(this, NetworkShieldService::class.java)); result.success(null)
                    }
                    "trackerStats" -> result.success(mapOf("blockedToday" to NetworkShieldService.blockedToday(this)))
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("NATIVE_ERROR", t.message ?: t.javaClass.simpleName, null)
            }
        }
    }

    private fun statusMap(manager: NativePolicyManager): Map<String, Any> = mapOf(
        "isDeviceOwner" to manager.isDeviceOwner,
        "canGrantSensors" to manager.canGrantSensors,
        "canScheduleExactAlarms" to manager.canScheduleExactAlarms,
        "panicEnabled" to manager.panicEnabled,
        "networkShieldEnabled" to NetworkShieldService.isEnabled(this),
        "vpnPrepared" to (VpnService.prepare(this) == null),
    )

    private fun listApps(): List<Map<String, Any>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val packages = packageManager.queryIntentActivities(launcher, PackageManager.MATCH_ALL)
            .map { it.activityInfo.packageName }
            .filter { it != packageName }
            .distinct()
        return packages.mapNotNull { target ->
            runCatching {
                val appInfo = if (Build.VERSION.SDK_INT >= 33) {
                    packageManager.getApplicationInfo(target, PackageManager.ApplicationInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION") packageManager.getApplicationInfo(target, 0)
                }
                val requested = requestedPermissions(target)
                mapOf(
                    "packageName" to target,
                    "label" to packageManager.getApplicationLabel(appInfo).toString(),
                    "hasCamera" to requested.contains(Manifest.permission.CAMERA),
                    "hasMicrophone" to requested.contains(Manifest.permission.RECORD_AUDIO),
                    "hasLocation" to (requested.contains(Manifest.permission.ACCESS_COARSE_LOCATION) || requested.contains(Manifest.permission.ACCESS_FINE_LOCATION)),
                    "systemApp" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }.getOrNull()
        }.filter { it["hasCamera"] == true || it["hasMicrophone"] == true || it["hasLocation"] == true }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    private fun requestedPermissions(target: String): Set<String> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(target, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            @Suppress("DEPRECATION") packageManager.getPackageInfo(target, PackageManager.GET_PERMISSIONS)
        }
        return info.requestedPermissions?.toSet() ?: emptySet()
    }

    private fun launchTarget(target: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(target) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
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
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivity(prepare)
            return false
        }
        val intent = Intent(this, NetworkShieldService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        return true
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> io.flutter.plugin.common.MethodCall.arg(key: String): T =
        argument<T>(key) ?: throw IllegalArgumentException("Missing argument: $key")
}
