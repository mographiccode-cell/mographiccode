package com.privacyshield.privacy_shield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.math.ceil

class SessionWatchdogService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var stoppingNormally = false

    private val tick = object : Runnable {
        override fun run() {
            if (stoppingNormally) return
            try {
                val sessions = NativePolicyManager(this@SessionWatchdogService).activeSessions()
                if (sessions.isEmpty()) {
                    stoppingNormally = true
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return
                }
                val remaining = sessions.minOfOrNull { (it["remainingMs"] as? Number)?.toLong() ?: 0L } ?: 0L
                val pending = sessions.any { it["revocationPending"] == true }
                getSystemService(NotificationManager::class.java).notify(
                    NOTIFICATION_ID,
                    buildNotification(sessions.size, remaining, pending),
                )
            } catch (_: Throwable) {
                // Keep the watchdog alive and retry. Alarm receivers are a second independent layer.
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        running = true
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stoppingNormally = false
        startForeground(NOTIFICATION_ID, buildNotification(1, 0L, false))
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        running = false
        if (!stoppingNormally) {
            runCatching { NativePolicyManager(this).revokeAllSessionsFailClosed() }
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(count: Int, remainingMs: Long, pending: Boolean): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            401,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val seconds = ceil(remainingMs.coerceAtLeast(0L) / 1000.0).toInt()
        val text = when {
            pending -> "جارٍ سحب إذن حساس متأخر — Fail-Closed retry يعمل"
            remainingMs > 0 -> "$count جلسة مؤقتة • إعادة القفل خلال $seconds ثانية"
            else -> "$count جلسة مؤقتة تحت المراقبة"
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Privacy Shield — Temporary Access")
            .setContentText(text)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun createChannel() {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Temporary sensor access",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    companion object {
        private const val CHANNEL_ID = "temporary_sensor_watchdog"
        private const val NOTIFICATION_ID = 2401
        private const val TICK_MS = 1_000L

        @Volatile
        private var running = false

        fun ensureRunning(context: Context) {
            val intent = Intent(context, SessionWatchdogService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }

        fun refresh(context: Context) {
            val hasSessions = runCatching { PolicyStore(context).sessions().isNotEmpty() }.getOrDefault(false)
            if (hasSessions) {
                ensureRunning(context)
            } else {
                context.stopService(Intent(context, SessionWatchdogService::class.java))
            }
        }

        fun isRunning(): Boolean = running
    }
}
