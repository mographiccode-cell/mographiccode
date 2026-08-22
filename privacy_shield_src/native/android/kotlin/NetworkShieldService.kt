package com.privacyshield.privacy_shield

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.concurrent.thread

class NetworkShieldService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var running = false
    private val executor = Executors.newCachedThreadPool()
    private val writeLock = Any()

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopShield()
            return START_NOT_STICKY
        }
        if (!running) {
            try {
                startShield()
            } catch (t: Throwable) {
                prefs().edit()
                    .putBoolean(KEY_ENABLED, false)
                    .putString(KEY_LAST_ERROR, t.message ?: t.javaClass.simpleName)
                    .apply()
                stopShield()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    override fun onRevoke() {
        prefs().edit().putString(KEY_LAST_ERROR, "VPN authorization revoked by Android").apply()
        stopShield()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopShield()
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startShield() {
        val configure = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = android.app.Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_secure)
            .setContentTitle("Privacy Shield")
            .setContentText("Network Shield يعمل محليًا")
            .setContentIntent(configure)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)

        tunnel = Builder()
            .setSession("Privacy Shield DNS")
            .setConfigureIntent(configure)
            .addAddress(CLIENT_IP, 32)
            .addDnsServer(DNS_IP)
            .addRoute(DNS_IP, 32)
            .allowFamily(OsConstants.AF_INET6)
            .addDisallowedApplication(packageName)
            .setBlocking(true)
            .establish()
            ?: throw IllegalStateException("تعذر إنشاء Local VPN")

        running = true
        prefs().edit()
            .putBoolean(KEY_ENABLED, true)
            .remove(KEY_LAST_ERROR)
            .apply()

        val fd = tunnel!!.fileDescriptor
        val input = FileInputStream(fd)
        val output = FileOutputStream(fd)
        thread(name = "privacy-dns-loop", isDaemon = true) {
            val buffer = ByteArray(32767)
            while (running) {
                try {
                    val length = input.read(buffer)
                    if (length > 0) processPacket(buffer.copyOf(length), output)
                } catch (_: Throwable) {
                    if (running) continue else break
                }
            }
            runCatching { input.close() }
            runCatching { output.close() }
        }
    }

    private fun processPacket(packet: ByteArray, output: FileOutputStream) {
        if (packet.size < 28 || (packet[0].toInt() ushr 4) != 4) return
        val ipHeaderLength = (packet[0].toInt() and 0x0F) * 4
        if (ipHeaderLength < 20 || packet.size < ipHeaderLength + 8) return
        if ((packet[9].toInt() and 0xFF) != 17) return
        val udp = ipHeaderLength
        val destinationPort = u16(packet, udp + 2)
        if (destinationPort != 53) return
        val dnsOffset = udp + 8
        if (packet.size <= dnsOffset + 12) return
        val dnsQuery = packet.copyOfRange(dnsOffset, packet.size)
        val domain = parseQuestionName(dnsQuery) ?: return
        if (isBlockedDomain(domain)) {
            incrementBlocked()
            writeDnsResponse(packet, buildNxDomain(dnsQuery), output)
            return
        }

        val network = underlyingNetwork()
        if (network == null) {
            writeDnsResponse(packet, buildServFail(dnsQuery), output)
            return
        }
        DnsResolver.getInstance().rawQuery(
            network,
            dnsQuery,
            DnsResolver.FLAG_EMPTY,
            executor,
            CancellationSignal(),
            object : DnsResolver.Callback<ByteArray> {
                override fun onAnswer(answer: ByteArray, rcode: Int) {
                    if (answer.size <= MAX_DNS_PAYLOAD) {
                        writeDnsResponse(packet, answer, output)
                    } else {
                        writeDnsResponse(packet, buildServFail(dnsQuery), output)
                    }
                }

                override fun onError(error: DnsResolver.DnsException) {
                    writeDnsResponse(packet, buildServFail(dnsQuery), output)
                }
            },
        )
    }

    private fun writeDnsResponse(requestPacket: ByteArray, dnsResponse: ByteArray, output: FileOutputStream) {
        val ipHeaderLength = (requestPacket[0].toInt() and 0x0F) * 4
        val requestUdp = ipHeaderLength
        val totalLength = 20 + 8 + dnsResponse.size
        if (totalLength > 65535) return
        val response = ByteArray(totalLength)
        response[0] = 0x45
        response[1] = 0
        putU16(response, 2, totalLength)
        response[4] = requestPacket[4]
        response[5] = requestPacket[5]
        response[6] = 0x40
        response[7] = 0
        response[8] = 64
        response[9] = 17
        System.arraycopy(requestPacket, 16, response, 12, 4)
        System.arraycopy(requestPacket, 12, response, 16, 4)
        putU16(response, 20, 53)
        putU16(response, 22, u16(requestPacket, requestUdp))
        putU16(response, 24, 8 + dnsResponse.size)
        putU16(response, 26, 0)
        System.arraycopy(dnsResponse, 0, response, 28, dnsResponse.size)
        putU16(response, 10, ipv4HeaderChecksum(response))
        synchronized(writeLock) {
            runCatching { output.write(response); output.flush() }
        }
    }

    private fun underlyingNetwork(): Network? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val active = cm.activeNetwork
        if (active != null) {
            val caps = cm.getNetworkCapabilities(active)
            if (caps != null && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return active
        }
        return cm.allNetworks.firstOrNull { network ->
            val caps = cm.getNetworkCapabilities(network) ?: return@firstOrNull false
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        }
    }

    private fun parseQuestionName(dns: ByteArray): String? {
        if (dns.size < 13) return null
        var index = 12
        val labels = mutableListOf<String>()
        while (index < dns.size) {
            val length = dns[index].toInt() and 0xFF
            index++
            if (length == 0) break
            if (length > 63 || index + length > dns.size) return null
            labels += dns.copyOfRange(index, index + length).toString(Charsets.UTF_8)
            index += length
        }
        return labels.joinToString(".").lowercase(Locale.US).takeIf { it.isNotBlank() }
    }

    private fun isBlockedDomain(domain: String): Boolean = BLOCKLIST.any { suffix ->
        domain == suffix || domain.endsWith(".$suffix")
    }

    private fun buildNxDomain(query: ByteArray): ByteArray = buildError(query, 0x83)
    private fun buildServFail(query: ByteArray): ByteArray = buildError(query, 0x82)

    private fun buildError(query: ByteArray, flagsLow: Int): ByteArray {
        val out = query.copyOf()
        if (out.size >= 12) {
            out[2] = 0x81.toByte()
            out[3] = flagsLow.toByte()
            out[6] = 0; out[7] = 0
            out[8] = 0; out[9] = 0
            out[10] = 0; out[11] = 0
        }
        return out
    }

    private fun incrementBlocked() {
        val prefs = prefs()
        val today = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
        val storedDay = prefs.getString(KEY_DAY, null)
        val current = if (storedDay == today) prefs.getInt(KEY_BLOCKED_TODAY, 0) else 0
        prefs.edit().putString(KEY_DAY, today).putInt(KEY_BLOCKED_TODAY, current + 1).apply()
    }

    private fun stopShield() {
        running = false
        runCatching { tunnel?.close() }
        tunnel = null
        prefs().edit().putBoolean(KEY_ENABLED, false).apply()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Network Shield", NotificationManager.IMPORTANCE_LOW),
        )
    }

    private fun prefs() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    companion object {
        const val ACTION_STOP = "com.privacyshield.NETWORK_STOP"
        private const val CLIENT_IP = "10.88.0.2"
        private const val DNS_IP = "10.88.0.1"
        private const val CHANNEL_ID = "network_shield"
        private const val NOTIFICATION_ID = 2001
        private const val PREFS = "network_shield"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_DAY = "day"
        private const val KEY_BLOCKED_TODAY = "blocked_today"
        private const val MAX_DNS_PAYLOAD = 1400

        private val BLOCKLIST = setOf(
            "doubleclick.net",
            "google-analytics.com",
            "googletagmanager.com",
            "app-measurement.com",
            "facebook.net",
            "appsflyer.com",
            "adjust.com",
            "branch.io",
            "mixpanel.com",
            "amplitude.com",
            "firebase-settings.crashlytics.com",
            "crashlytics.com",
            "segment.io",
            "segment.com",
            "hotjar.com",
            "fullstory.com",
            "newrelic.com",
            "bugsnag.com",
            "sentry.io",
        )

        fun isActuallyRunning(context: Context): Boolean {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            return cm.allNetworks.any { network ->
                val caps = cm.getNetworkCapabilities(network) ?: return@any false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && caps.ownerUid == Process.myUid()
            }
        }

        fun hasOtherVpn(context: Context): Boolean {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            return cm.allNetworks.any { network ->
                val caps = cm.getNetworkCapabilities(network) ?: return@any false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && caps.ownerUid != Process.myUid()
            }
        }

        fun lastError(context: Context): String? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_LAST_ERROR, null)

        fun blockedToday(context: Context): Int {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val today = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
            return if (prefs.getString(KEY_DAY, null) == today) prefs.getInt(KEY_BLOCKED_TODAY, 0) else 0
        }

        private fun u16(bytes: ByteArray, offset: Int): Int =
            ((bytes[offset].toInt() and 0xFF) shl 8) or (bytes[offset + 1].toInt() and 0xFF)

        private fun putU16(bytes: ByteArray, offset: Int, value: Int) {
            bytes[offset] = ((value ushr 8) and 0xFF).toByte()
            bytes[offset + 1] = (value and 0xFF).toByte()
        }

        private fun ipv4HeaderChecksum(packet: ByteArray): Int {
            var sum = 0L
            var i = 0
            while (i < 20) {
                if (i == 10) { i += 2; continue }
                sum += u16(packet, i).toLong()
                while ((sum and 0xFFFF0000L) != 0L) sum = (sum and 0xFFFFL) + (sum ushr 16)
                i += 2
            }
            return sum.inv().toInt() and 0xFFFF
        }
    }
}
