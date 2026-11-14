package com.example.nona_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import libXray.DialerController
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Android VPN service for Xray VLESS+REALITY and Hysteria2.
 * It never establishes a TUN unless a validated in-memory profile is supplied.
 * Android always-on is disabled until encrypted recovery is implemented.
 */
class NonaVpnService : VpnService() {
    companion object {
        private const val notificationChannel = "nona_vpn"
        private const val notificationId = 1001
        private const val stopAction = "com.example.nona_client.STOP_VPN"
        private val pendingLock = Any()
        private var pendingProfile: String? = null
        @Volatile var state: String = "idle"
            private set

        fun currentState(context: Context): String {
            if (Build.VERSION.SDK_INT < 30) return state
            val active = try {
                val manager = context.getSystemService(ConnectivityManager::class.java)
                manager.allNetworks.any { network ->
                    val capabilities = manager.getNetworkCapabilities(network)
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                        capabilities.ownerUid == context.applicationInfo.uid
                }
            } catch (_: SecurityException) {
                return state
            }
            return when {
                active && state == "idle" -> "error"
                !active && state == "connected" -> "error"
                else -> state
            }
        }

        fun measureLatency(context: Context): Int {
            check(currentState(context) == "connected") { "VPN is not connected" }
            val connectivity = context.getSystemService(ConnectivityManager::class.java)
            val vpnNetwork = connectivity.activeNetwork ?: throw IllegalStateException("No active VPN network")
            fun isCurrentVpn(): Boolean {
                val capabilities = connectivity.getNetworkCapabilities(vpnNetwork)
                return connectivity.activeNetwork == vpnNetwork &&
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                    (Build.VERSION.SDK_INT < 30 || capabilities.ownerUid == context.applicationInfo.uid) &&
                    state == "connected"
            }
            check(isCurrentVpn()) { "VPN is not the default network" }
            val samples = ArrayList<Int>(3)
            repeat(3) {
                check(isCurrentVpn()) { "VPN changed during measurement" }
                val started = SystemClock.elapsedRealtimeNanos()
                val probe = URL("https://1.1.1.1/").openConnection() as HttpURLConnection
                try {
                    probe.connectTimeout = 5000
                    probe.readTimeout = 5000
                    probe.instanceFollowRedirects = false
                    probe.useCaches = false
                    if (probe.responseCode !in 200..399) {
                        throw IllegalStateException("VPN traffic check failed")
                    }
                    check(isCurrentVpn()) { "VPN changed during measurement" }
                    samples.add(((SystemClock.elapsedRealtimeNanos() - started) / 1_000_000L)
                        .coerceIn(1L, Int.MAX_VALUE.toLong()).toInt())
                } finally {
                    probe.disconnect()
                }
            }
            samples.sort()
            return samples[1]
        }

        fun start(context: Context, profileJson: String) {
            require(profileJson.length in 1..(1 shl 20)) { "Invalid profile size" }
            synchronized(pendingLock) {
                check(pendingProfile == null && state != "connecting" && state != "connected") {
                    "VPN is already starting or connected"
                }
                pendingProfile = profileJson
            }
            val intent = Intent(context, NonaVpnService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                synchronized(pendingLock) { pendingProfile = null }
                throw error
            }
        }

        fun stop(context: Context) {
            synchronized(pendingLock) { pendingProfile = null }
            // Android keeps VpnService bound while its TUN is open. A plain
            // stopService() only removes the started state and leaves the
            // bound service (and VPN interface) alive.
            context.startService(Intent(context, NonaVpnService::class.java).setAction(stopAction))
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var cancelled = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == stopAction) {
            cancelled = true
            state = "disconnecting"
            worker.execute {
                cleanup()
                state = "idle"
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelfResult(startId)
            }
            return START_NOT_STICKY
        }
        val profile = synchronized(pendingLock) {
            pendingProfile.also { pendingProfile = null }
        }
        if (profile == null && state == "connected") return START_NOT_STICKY
        if (profile == null || prepare(this) != null) {
            state = "idle"
            stopSelf(startId)
            return START_NOT_STICKY
        }
        try {
            startVpnForeground()
        } catch (_: Exception) {
            state = "error"
            stopSelf(startId)
            return START_NOT_STICKY
        }
        state = "connecting"
        cancelled = false
        worker.execute { connect(profile, startId) }
        return START_NOT_STICKY
    }

    private fun startVpnForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(notificationChannel, "Нона VPN", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, notificationChannel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Нона")
            .setContentText("Подготовка VPN-подключения")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun invoke(method: String, config: String? = null): JSONObject {
        val request = JSONObject()
            .put("apiVersion", 3)
            .put("method", method)
        if (config != null) request.put("payload", JSONObject().put("xrayJson", config))
        return JSONObject(LibXray.invoke(request.toString()))
    }

    private fun requireSuccess(response: JSONObject) {
        if (!response.optBoolean("success", false)) {
            val raw = response.optString("error", "").lowercase()
            val markers = listOf(
                "tun", "fd", "/dev/tun", "/dev/net/tun", "permission denied",
                "operation not permitted", "network", "dns", "outbound", "inbound",
                "unsupported", "unknown", "already running", "failed to start",
                "failed to load", "failed to listen", "failed to open", "no such file",
                "invalid", "gateway", "bind", "device or resource busy",
            ).filter { raw.contains(it) }
            Log.e("NonaVpnService", "Xray rejected startup; categories=${markers.joinToString(",")}; errorLength=${raw.length}")
            if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                val safeWords = setOf(
                    "failed", "to", "start", "proxy", "tun", "inbound", "permission", "denied",
                    "set", "socket", "options", "bind", "interface", "file", "open", "build",
                    "config", "system", "route", "connect", "protect", "fd", "listen", "device",
                    "get", "network", "operation", "not", "found", "all", "create", "android",
                    "cannot", "could", "service", "settings", "necessary", "the", "for", "on",
                    "is", "in", "error", "from", "core", "internal", "transport", "read", "write",
                )
                val shape = Regex("[a-z]+").findAll(raw).take(100)
                    .joinToString(" ") { if (it.value in safeWords) it.value else "_" }
                Log.e("NonaVpnService", "Xray error shape: $shape")
            }
            throw IllegalStateException("Xray rejected configuration")
        }
    }

    private fun connect(profile: String, startId: Int) {
        var stage = "profile"
        try {
            if (cancelled) throw IllegalStateException("VPN was stopped")
            val config = JSONObject(profile)
            val inbounds = config.getJSONArray("inbounds")
            val outbounds = config.getJSONArray("outbounds")
            require(inbounds.length() == 1 && outbounds.length() == 1)
            val inbound = inbounds.getJSONObject(0)
            val outbound = outbounds.getJSONObject(0)
            require(inbound.getString("protocol") == "socks" && inbound.getString("listen") == "127.0.0.1")
            val outboundProtocol = outbound.getString("protocol")
            val streamSettings = outbound.getJSONObject("streamSettings")
            require(
                (outboundProtocol == "vless" && streamSettings.getString("security") == "reality") ||
                    (outboundProtocol == "hysteria" && streamSettings.getString("security") == "tls" &&
                        streamSettings.getJSONObject("hysteriaSettings").getInt("version") == 2),
            )
            InternetRouting.decorateProfile(this, config)
            // Validate before Android routes any packet to the app.
            stage = "xray-validation"
            requireSuccess(invoke("testXray", config.toString()))
            if (cancelled) throw IllegalStateException("VPN was stopped")

            stage = "underlying-network"
            val connectivity = getSystemService(ConnectivityManager::class.java)
            val network = connectivity.activeNetwork ?: throw IllegalStateException("No underlying network")
            val dns = connectivity.getLinkProperties(network)?.dnsServers?.firstOrNull()?.hostAddress
                ?: throw IllegalStateException("No underlying DNS")
            val builder = Builder()
                .setSession("Нона")
                .setMtu(1280)
                .addAddress("198.18.0.2", 30)
                .addAddress("fd00:6e6f:6e61::2", 126)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("2606:4700:4700::1111")
            AndroidAppExclusions.applySaved(builder, this)
            if (cancelled) throw IllegalStateException("VPN was stopped")
            stage = "vpn-interface"
            tunnel = builder.establish() ?: throw IllegalStateException("Android refused VPN interface")

            val controller = object : DialerController {
                override fun protectFd(fd: Long): Boolean {
                    return protect(fd.toInt())
                }
            }
            LibXray.registerDialerController(controller)
            LibXray.setDNS(controller, "${if (dns.contains(':')) "[$dns]" else dns}:53")
            val tunConfig = JSONObject(config.toString())
            val nativeInbound = JSONObject()
                .put("tag", "tun-in")
                .put("protocol", "tun")
                // A nonempty name keeps Xray's config builder from calling
                // net.Interfaces(), which Android denies to this app. The
                // actual interface is the fd supplied by VpnService.
                .put("settings", JSONObject().put("name", "tun0").put("mtu", 1280))
            if (tunConfig.has("routing")) {
                nativeInbound.put("sniffing", JSONObject().put("enabled", true)
                    .put("destOverride", JSONArray(listOf("fakedns", "http", "tls", "quic")))
                    // Fake IPs must be replaced by their original domain.
                    // With routeOnly=true, Freedom would try to dial the fake IP.
                    .put("routeOnly", false))
            }
            val nativeInbounds = JSONArray().put(nativeInbound)
            tunConfig.put("inbounds", nativeInbounds)
            tunConfig.put("env", JSONObject().put("xray.tun.fd", tunnel!!.fd.toString()))
            stage = "xray-start"
            requireSuccess(invoke("runXray", tunConfig.toString()))
            if (cancelled) throw IllegalStateException("VPN was stopped")
            stage = "xray-state"
            val running = invoke("getXrayState").optJSONObject("data")?.optBoolean("running") == true
            if (!running) throw IllegalStateException("Xray did not start")
            stage = "traffic-check"
            val vpnNetwork = (0 until 15).firstNotNullOfOrNull {
                connectivity.allNetworks.firstOrNull { candidate ->
                    val capabilities = connectivity.getNetworkCapabilities(candidate)
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true &&
                        (Build.VERSION.SDK_INT < 30 || capabilities.ownerUid == applicationInfo.uid) &&
                        connectivity.activeNetwork == candidate
                }.also { if (it == null) Thread.sleep(200) }
            } ?: throw IllegalStateException("Android VPN network is unavailable")
            if (connectivity.activeNetwork != vpnNetwork) {
                throw IllegalStateException("VPN is not the application's default network")
            }
            val probe = URL("https://1.1.1.1/").openConnection() as HttpURLConnection
            try {
                probe.connectTimeout = 5000
                probe.readTimeout = 5000
                probe.instanceFollowRedirects = false
                if (probe.responseCode !in 200..399) throw IllegalStateException("VPN traffic check failed")
            } finally {
                probe.disconnect()
            }
            state = "connected"
            val notificationBuilder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, notificationChannel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = notificationBuilder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Нона")
                .setContentText("VPN-подключение активно")
                .setOngoing(true)
                .build()
            getSystemService(NotificationManager::class.java).notify(notificationId, notification)
        } catch (error: Exception) {
            // Only the stage and exception type are logged. Native errors may
            // contain credential material and must never reach Android logs.
            Log.e("NonaVpnService", "VPN setup failed at $stage (${error.javaClass.simpleName})")
            state = "error"
            cleanup()
            stopSelf(startId)
        }
    }

    private fun cleanup() {
        try { invoke("stopXray") } catch (_: Exception) { }
        try { LibXray.resetDNS() } catch (_: Exception) { }
        try { tunnel?.close() } catch (_: Exception) { }
        tunnel = null
    }

    override fun onRevoke() {
        cancelled = true
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        cancelled = true
        worker.execute {
            cleanup()
            if (state != "error") state = "idle"
        }
        worker.shutdown()
        super.onDestroy()
    }
}
