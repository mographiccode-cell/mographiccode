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

    val panicDegraded: Boolean
        get() = isDeviceOwner && store.panicEnabled && !isPanicFullyEnforced()

    fun blockedPolicies(): List<Map<String, String>> {
        if (!isDeviceOwner) return emptyList()
        return store.blockedEntries()
            .filter { (packageName, sensor) ->
                if (!isInstalled(packageName)) return@filter false
                val permissions = runCatching { requestedSensorPermissions(packageName, sensor) }.getOrDefault(emptyList())
                permissions.isNotEmpty() && permissions.all {
                    dpm.getPermissionGrantState(admin, packageName, it) == DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED
                }
            }
            .map { (packageName, sensor) -> mapOf("packageName" to packageName, "sensor" to sensor) }
    }

    fun policyDriftCount(): Int {
        if (!isDeviceOwner) return 0
        return store.blockedEntries().count { (packageName, sensor) ->
            if (!isInstalled(packageName)) return@count true
            val permissions = runCatching { requestedSensorPermissions(packageName, sensor) }.getOrDefault(emptyList())
            permissions.isEmpty() || permissions.any {
                dpm.getPermissionGrantState(admin, packageName, it) != DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED
            }
        }
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
                forceDenied(packageName, permissions)
                store.setBlocked(packageName, sensor, true)
                throw IllegalStateException("تعذر حفظ DEFAULT؛ تمت العودة إلى DENIED.")
            }
        }
    }

    fun temporaryGrant(packageName: String, sensor: String, durationMs: Long) {
        requireOwner()
        if (!canGrantSensors) throw IllegalStateException("تهيئة Device Owner الحالية لا تسمح بمنح صلاحيات الحساسات.")
        if (store.panicEnabled) throw IllegalStateException("ألغِ Panic Lock قبل فتح أي حساس.")
        if (!store.isBlocked(packageName, sensor)) throw IllegalStateException("الحساس يجب أن يكون محميًا DENIED قبل الفتح المؤقت.")
        if (durationMs !in 10_000L..180_000L) throw IllegalArgumentException("مدة الجلسة غير صالحة.")

        val boot = readBootCount()
        if (boot < 0) throw IllegalStateException("تعذر تثبيت BOOT_COUNT؛ تم رفض الجلسة بنمط Fail-Closed.")
        val permissions = requestedSensorPermissions(packageName, sensor)
        if (permissions.isEmpty()) throw IllegalArgumentException("التطبيق لا يطلب هذه الصلاحية.")

        forceDenied(packageName, permissions)
        val session = NativeSession(packageName, sensor, SystemClock.elapsedRealtime() + durationMs, boot)
        if (!store.putSession(session)) throw IllegalStateException("تعذر حفظ الجلسة الآمنة.")

        try {
            scheduleSession(session)
            SessionWatchdogService.ensureRunning(context)
        } catch (t: Throwable) {
            cancelSession(packageName, sensor)
            throw IllegalStateException("تعذر تشغيل شبكة إعادة القفل؛ لم يتم فتح الحساس.", t)
        }

        try {
            applyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
            verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED)
        } catch (t: Throwable) {
            runCatching { forceDenied(packageName, permissions) }
            cancelSession(packageName, sensor)
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

    fun revokeFromAlarm(packageName: String, sensor: String, attempt: Int) {
        try {
            revokeNow(packageName, sensor)
        } catch (t: Throwable) {
            if (attempt < MAX_REVOKE_RETRIES) scheduleRetry(packageName, sensor, attempt + 1)
            throw t
        }
    }

    fun activeSessions(): List<Map<String, Any>> {
        if (!isDeviceOwner) return emptyList()
        val now = SystemClock.elapsedRealtime()
        val boot = readBootCount()
        val output = mutableListOf<Map<String, Any>>()
        for (session in store.sessions()) {
            if (boot < 0 || session.bootCount != boot || session.endElapsed <= now) {
                val revoked = runCatching { revokeNow(session.packageName, session.sensor) }.isSuccess
                if (!revoked) {
                    scheduleRetry(session.packageName, session.sensor, 1)
                    output += mapOf(
                        "packageName" to session.packageName,
                        "sensor" to session.sensor,
                        "remainingMs" to 0L,
                        "revocationPending" to true,
                    )
                }
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
                "revocationPending" to false,
            )
        }
        return output
    }

    fun repairPolicies(): Int {
        requireOwner()
        if (isPanicFullyEnforced() && !store.panicEnabled) store.panicEnabled = true

        reconcileSessionsAfterBootOrClockChange()
        val activeKeys = validSessionKeys()
        var count = 0
        val stale = mutableListOf<Pair<String, String>>()

        for ((packageName, sensor) in store.blockedEntries()) {
            if (!isInstalled(packageName)) {
                stale += packageName to sensor
                continue
            }
            if ("$packageName\t$sensor" in activeKeys) continue
            val permissions = requestedSensorPermissions(packageName, sensor)
            if (permissions.isEmpty()) continue
            forceDenied(packageName, permissions)
            count++
        }
        stale.forEach { store.setBlocked(it.first, it.second, false) }

        count += recoverDpmState(activeKeys)
        if (store.panicEnabled) forcePanicLocked()
        SessionWatchdogService.refresh(context)
        return count
    }

    fun repairPackage(packageName: String) {
        if (!isDeviceOwner) return
        if (!isInstalled(packageName)) {
            cancelAllForPackage(packageName)
            store.removePackage(packageName)
            return
        }
        for (sensor in SENSOR_NAMES) {
            cancelSession(packageName, sensor)
            val permissions = requestedSensorPermissions(packageName, sensor)
            if (permissions.isEmpty()) continue
            val states = permissions.map { dpm.getPermissionGrantState(admin, packageName, it) }
            if (store.isBlocked(packageName, sensor) || states.any { it == DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED }) {
                forceDenied(packageName, permissions)
                check(store.setBlocked(packageName, sensor, true)) { "تعذر حفظ سياسة $packageName:$sensor" }
            } else if (states.any { it == DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED }) {
                forceDenied(packageName, permissions)
                check(store.setBlocked(packageName, sensor, true)) { "تعذر استعادة سياسة $packageName:$sensor" }
            }
        }
        SessionWatchdogService.refresh(context)
    }

    fun removePackage(packageName: String) {
        cancelAllForPackage(packageName)
        store.removePackage(packageName)
        SessionWatchdogService.refresh(context)
    }

    fun reconcileSessionsAfterBootOrClockChange() {
        if (!isDeviceOwner) {
            store.clearSessions()
            SessionWatchdogService.refresh(context)
            return
        }
        val boot = readBootCount()
        val now = SystemClock.elapsedRealtime()
        for (session in store.sessions()) {
            if (boot < 0 || session.bootCount != boot || session.endElapsed <= now) {
                runCatching { revokeNow(session.packageName, session.sensor) }
                    .onFailure { scheduleRetry(session.packageName, session.sensor, 1) }
            }
        }
        SessionWatchdogService.refresh(context)
    }

    fun revokeAllSessionsFailClosed() {
        if (!isDeviceOwner) {
            store.clearSessions()
            SessionWatchdogService.refresh(context)
            return
        }
        val failures = mutableListOf<String>()
        for (session in store.sessions()) {
            runCatching { revokeNow(session.packageName, session.sensor) }
                .onFailure {
                    scheduleRetry(session.packageName, session.sensor, 1)
                    failures += "${session.packageName}:${session.sensor}"
                }
        }
        SessionWatchdogService.refresh(context)
        if (failures.isNotEmpty()) throw IllegalStateException("تعذر سحب جلسات: ${failures.joinToString()}")
    }

    fun setPanic(enabled: Boolean) {
        requireOwner()
        if (enabled) enablePanic() else disablePanic()
    }

    private fun enablePanic() {
        revokeAllSessionsFailClosed()
        if (!store.panicEnabled) {
            snapshotPanicState()
            store.panicEnabled = true
        }
        forcePanicLocked()
        if (!isPanicFullyEnforced()) {
            runCatching { forcePanicLocked() }
            throw IllegalStateException("تعذر تأكيد Panic Lock بالكامل؛ بقيت حالة الطوارئ مفعلة.")
        }
    }

    private fun disablePanic() {
        if (!store.panicEnabled) return
        try {
            restorePanicSnapshot()
            verifyPanicSnapshotRestored()
            store.panicEnabled = false
        } catch (t: Throwable) {
            runCatching { forcePanicLocked() }
            runCatching { store.panicEnabled = true }
            throw IllegalStateException("تعذر فك Panic بأمان؛ تمت العودة تلقائيًا إلى LOCKED.", t)
        }
    }

    private fun snapshotPanicState() {
        val restrictions = dpm.getUserRestrictions(admin)
        store.previousCameraDisabled = dpm.getCameraDisabled(admin)
        store.previousMicrophoneRestricted = restrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false)
        store.previousLocationConfigRestricted = restrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false)
        store.previousLocationEnabled = locationManager.isLocationEnabled
        store.previousScreenCaptureDisabled = dpm.getScreenCaptureDisabled(admin)
    }

    private fun forcePanicLocked() {
        val failures = mutableListOf<String>()
        runCatching { dpm.setCameraDisabled(admin, true) }.onFailure { failures += "camera" }
        runCatching { dpm.addUserRestriction(admin, UserManager.DISALLOW_UNMUTE_MICROPHONE) }.onFailure { failures += "microphone" }
        runCatching { dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_LOCATION) }.onFailure { failures += "location-config" }
        runCatching { dpm.setLocationEnabled(admin, false) }.onFailure { failures += "location" }
        runCatching { dpm.setScreenCaptureDisabled(admin, true) }.onFailure { failures += "screen-capture" }
        if (failures.isNotEmpty() || !isPanicFullyEnforced()) {
            throw IllegalStateException("Panic Lock جزئي. فشل: ${failures.joinToString()}")
        }
    }

    private fun restorePanicSnapshot() {
        dpm.setCameraDisabled(admin, store.previousCameraDisabled)
        if (store.previousMicrophoneRestricted) {
            dpm.addUserRestriction(admin, UserManager.DISALLOW_UNMUTE_MICROPHONE)
        } else {
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_UNMUTE_MICROPHONE)
        }
        dpm.setLocationEnabled(admin, store.previousLocationEnabled)
        if (store.previousLocationConfigRestricted) {
            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_LOCATION)
        } else {
            dpm.clearUserRestriction(admin, UserManager.DISALLOW_CONFIG_LOCATION)
        }
        dpm.setScreenCaptureDisabled(admin, store.previousScreenCaptureDisabled)
    }

    private fun verifyPanicSnapshotRestored() {
        val restrictions = dpm.getUserRestrictions(admin)
        check(dpm.getCameraDisabled(admin) == store.previousCameraDisabled) { "camera restore drift" }
        check(restrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false) == store.previousMicrophoneRestricted) { "microphone restore drift" }
        check(restrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false) == store.previousLocationConfigRestricted) { "location restriction restore drift" }
        check(locationManager.isLocationEnabled == store.previousLocationEnabled) { "location restore drift" }
        check(dpm.getScreenCaptureDisabled(admin) == store.previousScreenCaptureDisabled) { "screen capture restore drift" }
    }

    private fun isPanicFullyEnforced(): Boolean {
        if (!isDeviceOwner) return false
        val restrictions = dpm.getUserRestrictions(admin)
        return dpm.getCameraDisabled(admin) &&
            restrictions.getBoolean(UserManager.DISALLOW_UNMUTE_MICROPHONE, false) &&
            restrictions.getBoolean(UserManager.DISALLOW_CONFIG_LOCATION, false) &&
            !locationManager.isLocationEnabled &&
            dpm.getScreenCaptureDisabled(admin)
    }

    private fun recoverDpmState(activeKeys: Set<String>): Int {
        var repaired = 0
        for (packageName in installedPackageNames()) {
            if (packageName == context.packageName) continue
            for (sensor in SENSOR_NAMES) {
                val key = "$packageName\t$sensor"
                if (key in activeKeys) continue
                val permissions = runCatching { requestedSensorPermissions(packageName, sensor) }.getOrDefault(emptyList())
                if (permissions.isEmpty()) continue
                val states = permissions.map { dpm.getPermissionGrantState(admin, packageName, it) }
                when {
                    states.any { it == DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED } -> {
                        forceDenied(packageName, permissions)
                        check(store.setBlocked(packageName, sensor, true)) { "تعذر حفظ orphan grant recovery" }
                        repaired++
                    }
                    states.any { it == DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED } && !store.isBlocked(packageName, sensor) -> {
                        forceDenied(packageName, permissions)
                        check(store.setBlocked(packageName, sensor, true)) { "تعذر إعادة بناء DPM policy" }
                        repaired++
                    }
                }
            }
        }
        return repaired
    }

    private fun validSessionKeys(): Set<String> {
        val boot = readBootCount()
        val now = SystemClock.elapsedRealtime()
        if (boot < 0) return emptySet()
        return store.sessions()
            .filter { it.bootCount == boot && it.endElapsed > now }
            .map { "${it.packageName}\t${it.sensor}" }
            .toSet()
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
        "location" -> listOf(
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        else -> throw IllegalArgumentException("حساس غير معروف: $sensor")
    }

    private fun sensorLabel(sensor: String) = when (sensor) {
        "camera" -> "الكاميرا"
        "microphone" -> "الميكروفون"
        "location" -> "الموقع"
        else -> sensor
    }

    private fun applyState(packageName: String, permissions: List<String>, state: Int) {
        val previous = permissions.associateWith { dpm.getPermissionGrantState(admin, packageName, it) }
        val changed = mutableListOf<String>()
        try {
            for (permission in permissions) {
                if (!dpm.setPermissionGrantState(admin, packageName, permission, state)) {
                    throw IllegalStateException("Android رفض تغيير $permission")
                }
                changed += permission
            }
        } catch (t: Throwable) {
            var rollbackOk = true
            for (permission in changed.asReversed()) {
                val restored = runCatching {
                    dpm.setPermissionGrantState(admin, packageName, permission, previous.getValue(permission))
                }.getOrDefault(false)
                rollbackOk = rollbackOk && restored
            }
            if (!rollbackOk || state == DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED) {
                runCatching { forceDenied(packageName, permissions) }
            }
            throw t
        }
    }

    private fun forceDenied(packageName: String, permissions: List<String>) {
        for (permission in permissions) {
            if (!dpm.setPermissionGrantState(
                    admin,
                    packageName,
                    permission,
                    DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED,
                )
            ) throw IllegalStateException("Android رفض DENIED لـ $permission")
        }
        verifyState(packageName, permissions, DevicePolicyManager.PERMISSION_GRANT_STATE_DENIED)
    }

    private fun verifyState(packageName: String, permissions: List<String>, state: Int) {
        for (permission in permissions) {
            val actual = dpm.getPermissionGrantState(admin, packageName, permission)
            if (actual != state) throw IllegalStateException("Policy drift: $permission=$actual expected=$state")
        }
    }

    private fun scheduleSession(session: NativeSession) {
        val triggerElapsed = session.endElapsed.coerceAtLeast(SystemClock.elapsedRealtime() + 1L)
        if (canScheduleExactAlarms) {
            alarm.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerElapsed,
                alarmIntent(session.packageName, session.sensor, KIND_PRIMARY, 0),
            )
        } else {
            alarm.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerElapsed,
                alarmIntent(session.packageName, session.sensor, KIND_PRIMARY, 0),
            )
        }
        alarm.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            triggerElapsed + 60_000L,
            alarmIntent(session.packageName, session.sensor, KIND_FALLBACK, 0),
        )
    }

    private fun scheduleRetry(packageName: String, sensor: String, attempt: Int) {
        val delay = (15_000L * attempt.coerceAtMost(4)).coerceAtMost(60_000L)
        runCatching {
            alarm.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delay,
                alarmIntent(packageName, sensor, KIND_RETRY, attempt),
            )
        }
    }

    private fun alarmIntent(packageName: String, sensor: String, kind: String, attempt: Int): PendingIntent {
        val intent = Intent(context, PermissionAlarmReceiver::class.java).apply {
            action = "com.privacyshield.REVOKE_PERMISSION"
            data = Uri.parse("privacyshield://revoke/$kind/${Uri.encode(packageName)}/${Uri.encode(sensor)}")
            putExtra("packageName", packageName)
            putExtra("sensor", sensor)
            putExtra("attempt", attempt)
        }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun cancelAlarms(packageName: String, sensor: String) {
        alarm.cancel(alarmIntent(packageName, sensor, KIND_PRIMARY, 0))
        alarm.cancel(alarmIntent(packageName, sensor, KIND_FALLBACK, 0))
        for (attempt in 1..MAX_REVOKE_RETRIES) {
            alarm.cancel(alarmIntent(packageName, sensor, KIND_RETRY, attempt))
        }
    }

    private fun cancelSession(packageName: String, sensor: String) {
        cancelAlarms(packageName, sensor)
        store.removeSession(packageName, sensor)
        SessionWatchdogService.refresh(context)
    }

    private fun cancelAllForPackage(packageName: String) {
        for (sensor in SENSOR_NAMES) cancelSession(packageName, sensor)
    }

    private fun readBootCount(): Int = runCatching {
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
    }.getOrDefault(-1)

    private fun installedPackageNames(): List<String> = runCatching {
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0)).map { it.packageName }
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstalledApplications(0).map { it.packageName }
        }
    }.getOrDefault(emptyList())

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

    companion object {
        private val SENSOR_NAMES = listOf("camera", "microphone", "location")
        private const val KIND_PRIMARY = "primary"
        private const val KIND_FALLBACK = "fallback"
        private const val KIND_RETRY = "retry"
        private const val MAX_REVOKE_RETRIES = 6
    }
}
