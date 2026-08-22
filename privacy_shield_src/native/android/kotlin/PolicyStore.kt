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

    fun isBlocked(packageName: String, sensor: String): Boolean =
        (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()).contains(blockedKey(packageName, sensor))

    fun setBlocked(packageName: String, sensor: String, blocked: Boolean): Boolean {
        val set = (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()).toMutableSet()
        if (blocked) set.add(blockedKey(packageName, sensor)) else set.remove(blockedKey(packageName, sensor))
        return prefs.edit().putStringSet(KEY_BLOCKED, set).commit()
    }

    fun blockedEntries(): List<Pair<String, String>> =
        (prefs.getStringSet(KEY_BLOCKED, emptySet()) ?: emptySet()).mapNotNull { encoded ->
            val parts = encoded.split('\t')
            if (parts.size == 2) parts[0] to parts[1] else null
        }

    private fun sessionKey(packageName: String, sensor: String) = "$packageName\t$sensor"

    fun putSession(session: NativeSession): Boolean {
        val sessions = readSessionMap().toMutableMap()
        sessions[sessionKey(session.packageName, session.sensor)] = session
        return writeSessions(sessions.values)
    }

    fun removeSession(packageName: String, sensor: String): Boolean {
        val sessions = readSessionMap().toMutableMap()
        sessions.remove(sessionKey(packageName, sensor))
        return writeSessions(sessions.values)
    }

    fun sessions(): List<NativeSession> = readSessionMap().values.toList()

    fun clearSessions(): Boolean = prefs.edit().remove(KEY_SESSIONS).commit()

    private fun readSessionMap(): Map<String, NativeSession> {
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

    private fun writeSessions(sessions: Collection<NativeSession>): Boolean {
        val encoded = sessions.map {
            "${it.packageName}\t${it.sensor}\t${it.endElapsed}\t${it.bootCount}"
        }.toSet()
        return prefs.edit().putStringSet(KEY_SESSIONS, encoded).commit()
    }

    var panicEnabled: Boolean
        get() = prefs.getBoolean(KEY_PANIC, false)
        set(value) { prefs.edit().putBoolean(KEY_PANIC, value).commit() }

    var previousLocationEnabled: Boolean
        get() = prefs.getBoolean(KEY_PREVIOUS_LOCATION, false)
        set(value) { prefs.edit().putBoolean(KEY_PREVIOUS_LOCATION, value).commit() }

    companion object {
        private const val KEY_BLOCKED = "blocked"
        private const val KEY_SESSIONS = "sessions"
        private const val KEY_PANIC = "panic"
        private const val KEY_PREVIOUS_LOCATION = "previous_location"
    }
}
