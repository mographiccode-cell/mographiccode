package com.privacyshield.privacy_shield

import android.content.Context

internal data class NativeSession(
    val packageName: String,
    val sensor: String,
    val endElapsed: Long,
    val bootCount: Int,
)

internal class PolicyStore(context: Context) {
    private val deviceContext = context.createDeviceProtectedStorageContext()
    private val prefs = deviceContext.getSharedPreferences("privacy_shield_policy", Context.MODE_PRIVATE)

    private fun blockedKey(packageName: String, sensor: String) = "$packageName\t$sensor"
    private fun sessionKey(packageName: String, sensor: String) = "$packageName\t$sensor"

    fun isBlocked(packageName: String, sensor: String): Boolean = synchronized(LOCK) {
        (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet())
            .contains(blockedKey(packageName, sensor))
    }

    fun setBlocked(packageName: String, sensor: String, blocked: Boolean): Boolean = synchronized(LOCK) {
        val set = (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()).toMutableSet()
        if (blocked) set.add(blockedKey(packageName, sensor)) else set.remove(blockedKey(packageName, sensor))
        prefs.edit().putStringSet(KEY_BLOCKED, set).commit()
    }

    fun blockedEntries(): List<Pair<String, String>> = synchronized(LOCK) {
        (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()).mapNotNull { encoded ->
            val parts = encoded.split('\t')
            if (parts.size == 2) parts[0] to parts[1] else null
        }
    }

    fun putSession(session: NativeSession): Boolean = synchronized(LOCK) {
        val sessions = readSessionMapLocked().toMutableMap()
        sessions[sessionKey(session.packageName, session.sensor)] = session
        writeSessionsLocked(sessions.values)
    }

    fun removeSession(packageName: String, sensor: String): Boolean = synchronized(LOCK) {
        val sessions = readSessionMapLocked().toMutableMap()
        sessions.remove(sessionKey(packageName, sensor))
        writeSessionsLocked(sessions.values)
    }

    fun sessions(): List<NativeSession> = synchronized(LOCK) {
        readSessionMapLocked().values.toList()
    }

    fun clearSessions(): Boolean = synchronized(LOCK) {
        prefs.edit().remove(KEY_SESSIONS).commit()
    }

    fun removePackage(packageName: String): Boolean = synchronized(LOCK) {
        val blocked = (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet())
            .filterNot { it.startsWith("$packageName\t") }
            .toSet()
        val sessions = readSessionMapLocked().filterValues { it.packageName != packageName }.values
        prefs.edit()
            .putStringSet(KEY_BLOCKED, blocked)
            .putStringSet(KEY_SESSIONS, encodeSessions(sessions))
            .commit()
    }

    private fun readSessionMapLocked(): Map<String, NativeSession> {
        val values = prefs.getStringSet(KEY_SESSIONS, emptySet()) ?: emptySet()
        return values.mapNotNull { encoded ->
            val parts = encoded.split('\t')
            if (parts.size != 4) return@mapNotNull null
            val end = parts[2].toLongOrNull() ?: return@mapNotNull null
            val boot = parts[3].toIntOrNull() ?: return@mapNotNull null
            val session = NativeSession(parts[0], parts[1], end, boot)
            sessionKey(session.packageName, session.sensor) to session
        }.toMap()
    }

    private fun encodeSessions(sessions: Collection<NativeSession>): Set<String> = sessions.map {
        "${it.packageName}\t${it.sensor}\t${it.endElapsed}\t${it.bootCount}"
    }.toSet()

    private fun writeSessionsLocked(sessions: Collection<NativeSession>): Boolean =
        prefs.edit().putStringSet(KEY_SESSIONS, encodeSessions(sessions)).commit()

    var panicEnabled: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PANIC, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PANIC, value).commit()) { "تعذر حفظ حالة Panic Lock." }
        }

    var previousLocationEnabled: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PREVIOUS_LOCATION, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PREVIOUS_LOCATION, value).commit()) { "تعذر حفظ حالة الموقع السابقة." }
        }

    var previousCameraDisabled: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PREVIOUS_CAMERA_DISABLED, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PREVIOUS_CAMERA_DISABLED, value).commit()) { "تعذر حفظ حالة الكاميرا السابقة." }
        }

    var previousMicrophoneRestricted: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PREVIOUS_MIC_RESTRICTION, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PREVIOUS_MIC_RESTRICTION, value).commit()) { "تعذر حفظ حالة الميكروفون السابقة." }
        }

    var previousLocationConfigRestricted: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PREVIOUS_LOCATION_CONFIG_RESTRICTION, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PREVIOUS_LOCATION_CONFIG_RESTRICTION, value).commit()) { "تعذر حفظ قيد الموقع السابق." }
        }

    var previousScreenCaptureDisabled: Boolean
        get() = synchronized(LOCK) { prefs.getBoolean(KEY_PREVIOUS_SCREEN_CAPTURE_DISABLED, false) }
        set(value) = synchronized(LOCK) {
            check(prefs.edit().putBoolean(KEY_PREVIOUS_SCREEN_CAPTURE_DISABLED, value).commit()) { "تعذر حفظ حالة التقاط الشاشة السابقة." }
        }

    companion object {
        private val LOCK = Any()
        private const val KEY_BLOCKED = "blocked"
        private const val KEY_SESSIONS = "sessions"
        private const val KEY_PANIC = "panic"
        private const val KEY_PREVIOUS_LOCATION = "previous_location"
        private const val KEY_PREVIOUS_CAMERA_DISABLED = "previous_camera_disabled"
        private const val KEY_PREVIOUS_MIC_RESTRICTION = "previous_mic_restriction"
        private const val KEY_PREVIOUS_LOCATION_CONFIG_RESTRICTION = "previous_location_config_restriction"
        private const val KEY_PREVIOUS_SCREEN_CAPTURE_DISABLED = "previous_screen_capture_disabled"
    }
}
