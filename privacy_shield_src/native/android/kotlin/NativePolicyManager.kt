package com.privacyshield.privacy_shield

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.os.UserManager
import android.provider.Settings

internal class NativePolicyManager(private val context: Context) {
    private val dpm = context.getSystemService(DevicePolicyManager::class.java)
    private val alarm = context.getSystemService(AlarmManager::class.java)
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val admin = ComponentName(context, PrivacyAdminReceiver::class.java)
    private val store = PolicyStore(context)

    val isDeviceOwner: Boolean
        get() = dpm.isDeviceOwnerApp(context.packageName)

    val canGrantSensors: Boolean
        get() = isDeviceOwner && (Build.VERSION.SDK_INT < 31 || dpm.canAdminGrantSensorsPermissions())

    val canScheduleExactAlarms: Boolean
        get() = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()

    val panicEnabled: Boolean
        get() = store.panicEnabled

    fun blockedPolicies(): List<Map<String, String>> =
        store.blockedEntries()
            .filter { (packageName, _) -> isInstalled(packageName) }
            .map { (packageName, sensor) ->
                mapOf("packageName" to packageName, "sensor" to sensor)
            }

    fun setBlocked(packageName: String, sensor: String, blocked: Boolean) {
        requireOwner()
        requireInstalled(packageName)
        val permissions = requestedSensorPermissions(packageName, sensor)
        if (permissions.isEmpty()) throw IllegalArgumentException("التطبيق لا يطلب صلاحية ${sensorLabel(sensor)}")

        if (blocked) {
            applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
            verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
            if (!store.setBlocked(packageName, sensor, true)) {
                throw IllegalStateException("تعذر حفظ سياسة الحظر محليًا؛ أبقينا الإذن DENIED للأمان.")
            }
            cancelSession(packageName, sensor)
        } else {
            if (store.sessions().any { it.packageName == packageName && it.sensor == sensor }) {
                revokeNow(packageName, sensor)
            }
            applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT)
            verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT)
            if (!store.setBlocked(packageName, sensor, false)) {
                applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
                store.setBlocked(packageName, sensor, true)
                throw IllegalStateException("تعذر حفظ DEFAULT؛ تمت العودة إلى DENIED.")
            }
        }
    }

    fun temporaryGrant(packageName: String, sensor: String, durationMs: Long) {
        requireOwner()
        if (!canGrantSensors) throw IllegalStateException("تهيئة Device Owner الحالية لا تسمح بمنح صلاحيات الحساسات.")
        if (!canScheduleExactAlarms) throw IllegalStateException("فعّل Alarms & reminders قبل الفتح المؤقت.")
        if (store.panicEnabled) throw IllegalStateException("ألغِ Panic Lock قبل فتح أي حساس.")
        if (!store.isBlocked(packageName, sensor)) throw IllegalStateException("الحساس يجب أن يكون محميًا DENIED قبل الفتح المؤقت.")
        if (durationMs !in 10_000L..300_000L) throw IllegalArgumentException("مدة الجلسة غير صالحة.")

        val boot = readBootCount()
        if (boot < 0) throw IllegalStateException("تعذر تثبيت BOOT_COUNT؛ تم رفض الجلسة بنمط Fail-Closed.")
        val permissions = requestedSensorPermissions(packageName, sensor)
        if (permissions.isEmpty()) throw IllegalArgumentException("التطبيق لا يطلب هذه الصلاحية.")

        applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
        verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)

        val session = NativeSession(packageName, sensor, SystemClock.elapsedRealtime() + durationMs, boot)
        if (!store.putSession(session)) throw IllegalStateException("تعذر حفظ الجلسة الآمنة.")
        try {
            scheduleSession(session)
        } catch (t: Throwable) {
            store.removeSession(packageName, sensor)
            throw t
        }

        try {
            applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
            verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
        } catch (t: Throwable) {
            runCatching { applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED) }
            cancelAlarms(packageName, sensor)
            store.removeSession(packageName, sensor)
            throw IllegalStateException("فشل GRANT وتمت العودة إلى DENIED.", t)
        }
    }

    fun revokeNow(packageName: String, sensor: String) {
        requireOwner()
        if (!isInstalled(packageName)) {
            cancelSession(packageName, sensor)
            store.setBlocked(packageName, sensor, false)
            return
        }
        val permissions = requestedSensorPermissions(packageName, sensor)
        if (permissions.isNotEmpty()) {
            val targetState = if (store.isBlocked(packageName, sensor)) {
                DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED
            } else {
                DevicePolicyManager.PERMISSION_GRANT_STATE_DEFAULT
            }
            applyState(packageName, permissions, targetState)
            verifyState(packageName, permissions, targetState)
        }
        cancelSession(packageName, sensor)
    }

    fun activeSessions(): List<Map<String, Any>> {
        if (!isDeviceOwner) return emptyList()
        val now = SystemClock.elapsedRealtime()
        val boot = readBootCount()
        val output = mutableListOf<Map<String, Any>>()
        for (session in store.sessions()) {
            if (boot < 0 || session.bootCount != boot || session.endElapsed <= now) {
                runCatching { revokeNow(session.packageName, session.sensor) }
                continue
            }
            val permissions = runCatching { requestedSensorPermissions(session.packageName, session.sensor) }.getOrDefault(emptyList())
            val stillGranted = permissions.isNotEmpty() && permissions.all {
                dpm.getPermissionGrantState(admin, session.packageName, it) == DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
            }
            if (!stillGranted) {
                cancelSession(session.packageName, session.sensor)
                continue
            }
            output += mapOf(
                "packageName" to session.packageName,
                "sensor" to session.sensor,
                "remainingMs" to (session.endElapsed - now),
            )
        }
        return output
    }

    fun repairPolicies(): Int {
        requireOwner()
        var count = 0
        val stale = mutableListOf<Pair<String, String>>()
        for ((packageName, sensor) in store.blockedEntries()) {
            if (!isInstalled(packageName)) {
                stale += packageName to sensor
                continue
            }
            val permissions = requestedSensorPermissions(packageName, sensor)
            if (permissions.isEmpty()) continue
            applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
            verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
            count++
        }
        stale.forEach { store.setBlocked(it.first, it.second, false) }
        reconcileSessionsAfterBootOrClockChange()
        if (store.panicEnabled) applyPanic(true, savePreviousLocation = false)
        return count
    }

    fun reconcileSessionsAfterBootOrClockChange() {
        if (!isDeviceOwner) {
            store.clearSessions()
            return
        }
        val boot = readBootCount()
        val now = SystemClock.elapsedRealtime()
        for (session in store.sessions()) {
            if (boot < 0 || session.bootCount != boot || session.endElapsed <= now) {
                runCatching { revokeNow(session.packageName, session.sensor) }
            }
        }
    }

    fun revokeAllSessionsFailClosed() {
        if (!isDeviceOwner) {
            store.clearSessions()
            return
        }
        val failures = mutableListOf<String>()
        for (session in store.sessions()) {
            runCatching { revokeNow(session.packageName, session.sensor) }
                .onFailure { failures += "${session.packageName}:${session.sensor}" }
        }
        if (failures.isNotEmpty()) throw IllegalStateException("تعذر سحب جلسات: ${failures.joinToString()}")
    }

    fun setPanic(enabled: Boolean) {
        requireOwner()
        if (enabled) {
            revokeAllSessionsFailClosed()
            store.previousLocationEnabled = locationManager.isLocationEnabled
            store.panicEnabled = true
            applyPanic(true, savePreviousLocation = false)
        } else {
            applyPanic(false, savePreviousLocation = false)
            store.panicEnabled = false
        }
    }

    private fun applyPanic(enabled: Boolean, savePreviousLocation: Boolean) {
        if (savePreviousLocation && enabled) store.previousLocationEnabled = locationManager.isLocationEnabled
        val failures = mutableListOf<String>()
        runCatching { dpm.setCameraDisabled(admin, enabled) }.onFailure { failures += "camera" }
        runCatching {
            if (enabled) dpm.addUserRestriction(admin, UserManager.DISALLOW_UNMUTE_MICROPHONE)
            else dpm.clearUserRestriction(admin, UserManager.DISALLOW_UNMUTE_MICROPHONE)
        }.onFailure { failures += "microphone" }
        runCatching {
            dpm.setLocationEnabled(admin, if (enabled) false else store.previousLocationEnabled)
        }.onFailure { failures += "location" }
        if (failures.isNotEmpty()) {
            if (enabled) store.panicEnabled = true
            throw IllegalStateException("Panic Lock جزئي؛ أعد المحاولة. فشل: ${failures.joinToString()}")
        }
    }

    private fun requestedSensorPermissions(packageName: String, sensor: String): List<String> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }
        val requested = info.requestedPermissions?.toSet() ?: emptySet()
        return sensorPermissions(sensor).filter { it in requested }
    }

    private fun sensorPermissions(sensor: String): List<String> = when (sensor) {
        "camera" -> listOf(Manifest.permission.CAMERA)
        "microphone" -> listOf(Manifest.permission.RECORD_AUDIO)
        "location" -> listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)
        else -> throw IllegalArgumentException("حساس غير معروف: $sensor")
    }

    private fun sensorLabel(sensor: String) = when (sensor) {
        "camera" -> "الكاميرا"
        "microphone" -> "الميكروفون"
        "location" -> "الموقع"
        else -> sensor
    }

    private fun applyState(packageName: String, permissions: List<String>, state: Int) {
        val changed = mutableListOf<String>()
        try {
            for (permission in permissions) {
                if (!dpm.setPermissionGrantState(admin, packageName, permission, state)) {
                    throw IllegalStateException("Android رفض تغيير $permission")
                }
                changed += permission
            }
        } catch (t: Throwable) {
            if (state == DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED) {
                changed.forEach { permission ->
                    runCatching {
                        dpm.setPermissionGrantState(
                            admin,
                            packageName,
                            permission,
                            DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
                        )
                    }
                }
            }
            throw t
        }
    }

    private fun verifyState(packageName: String, permissions: List<String>, state: Int) {
        for (permission in permissions) {
            val actual = dpm.getPermissionGrantState(admin, packageName, permission)
            if (actual != state) throw IllegalStateException("Policy drift: $permission=$actual expected=$state")
        }
    }

    private fun scheduleSession(session: NativeSession) {
        if (!canScheduleExactAlarms) throw IllegalStateException("Exact Alarm غير متاح.")
        val triggerElapsed = session.endElapsed.coerceAtLeast(SystemClock.elapsedRealtime() + 1L)
        alarm.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            triggerElapsed,
            alarmIntent(session.packageName, session.sensor, false),
        )
        alarm.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            triggerElapsed + 60_000L,
            alarmIntent(session.packageName, session.sensor, true),
        )
    }

    private fun alarmIntent(packageName: String, sensor: String, fallback: Boolean): PendingIntent {
        val kind = if (fallback) "fallback" else "exact"
        val intent = Intent(context, PermissionAlarmReceiver::class.java).apply {
            action = "com.privacyshield.REVOKE_PERMISSION"
            data = Uri.parse("privacyshield://revoke/$kind/${Uri.encode(packageName)}/${Uri.encode(sensor)}")
            putExtra("packageName", packageName)
            putExtra("sensor", sensor)
        }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun cancelAlarms(packageName: String, sensor: String) {
        alarm.cancel(alarmIntent(packageName, sensor, false))
        alarm.cancel(alarmIntent(packageName, sensor, true))
    }

    private fun cancelSession(packageName: String, sensor: String) {
        cancelAlarms(packageName, sensor)
        store.removeSession(packageName, sensor)
    }

    private fun readBootCount(): Int = runCatching {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
    }.getOrDefault(-1)

    private fun requireOwner() {
        if (!isDeviceOwner) throw SecurityException("Privacy Shield ليس Device Owner بعد.")
    }

    private fun requireInstalled(packageName: String) {
        if (!isInstalled(packageName)) throw PackageManager.NameNotFoundException(packageName)
    }

    private fun isInstalled(packageName: String): Boolean = runCatching {
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationInfo(packageName, 0)
        }
        true
    }.getOrDefault(false)
}
