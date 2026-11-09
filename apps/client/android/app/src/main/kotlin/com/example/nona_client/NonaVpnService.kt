package com.example.nona_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import libXray.DialerController
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** Android VPN service for the Xray VLESS+REALITY path.
 * It never establishes a TUN unless a validated in-memory profile is supplied.
 * Android always-on is disabled until encrypted recovery is implemented.
 */
class NonaVpnService : VpnService() {
    companion object {
        private const val notificationChannel = "nona_vpn"
        private const val notificationId = 1001
        private val pendingLock = Any()
        private var pendingProfile: String? = null
        @Volatile var state: String = "idle"
            private set

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
            context.stopService(Intent(context, NonaVpnService::class.java))
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var cancelled = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
        if (!response.optBoolean("success", false)) throw IllegalStateException("Xray rejected configuration")
    }

    private fun connect(profile: String, startId: Int) {
        try {
            if (cancelled) throw IllegalStateException("VPN was stopped")
            val config = JSONObject(profile)
            val inbounds = config.getJSONArray("inbounds")
            val outbounds = config.getJSONArray("outbounds")
            require(inbounds.length() == 1 && outbounds.length() == 1)
            val inbound = inbounds.getJSONObject(0)
            val outbound = outbounds.getJSONObject(0)
            require(inbound.getString("protocol") == "socks" && inbound.getString("listen") == "127.0.0.1")
            require(outbound.getString("protocol") == "vless")
            require(outbound.getJSONObject("streamSettings").getString("security") == "reality")
            // Validate before Android routes any packet to the app.
            requireSuccess(invoke("testXray", profile))
            if (cancelled) throw IllegalStateException("VPN was stopped")

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
            tunnel = builder.establish() ?: throw IllegalStateException("Android refused VPN interface")

            val controller = object : DialerController {
                override fun protectFd(fd: Long): Boolean = protect(fd.toInt())
            }
            LibXray.registerDialerController(controller)
            LibXray.setDNS(controller, "${if (dns.contains(':')) "[$dns]" else dns}:53")
            val tunConfig = JSONObject(profile)
            tunConfig.put("inbounds", JSONArray().put(
                JSONObject()
                    .put("tag", "tun-in")
                    .put("protocol", "tun")
                    .put("settings", JSONObject().put("mtu", 1280)),
            ))
            tunConfig.put("env", JSONObject().put("xray.tun.fd", tunnel!!.fd.toString()))
            requireSuccess(invoke("runXray", tunConfig.toString()))
            if (cancelled) throw IllegalStateException("VPN was stopped")
            val running = invoke("getXrayState").optJSONObject("data")?.optBoolean("running") == true
            if (!running) throw IllegalStateException("Xray did not start")
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
        } catch (_: Exception) {
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
