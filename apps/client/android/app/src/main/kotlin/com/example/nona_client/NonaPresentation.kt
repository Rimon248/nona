package com.example.nona_client

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal object NonaPresentation {
    private val widgetExecutor = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "nona-widget-refresh").apply { isDaemon = true }
    }
    private var pendingWidgetRefresh: ScheduledFuture<*>? = null

    fun refreshWidgets(context: Context) {
        val app = context.applicationContext
        synchronized(this) {
            pendingWidgetRefresh?.cancel(false)
            pendingWidgetRefresh = widgetExecutor.schedule({
                try { NonaWidgetProvider.updateAll(app) } catch (_: Exception) { }
            }, 35, TimeUnit.MILLISECONDS)
        }
    }

    const val vpnId = 1001
    private const val updateId = 1002
    private const val vpnChannel = "nona_vpn"
    private const val updateChannel = "nona_updates"
    private const val settingsName = "nona_notification_settings"
    private const val presentationName = "nona_vpn_presentation"
    const val restartAction = "com.example.nona_client.RESTART"
    const val connectAction = "com.example.nona_client.CONNECT"
    const val stopAction = "com.example.nona_client.STOP"
    const val pingAction = "com.example.nona_client.PING"

    fun setSettings(context: Context, updates: Boolean, actions: Boolean, ping: Boolean) {
        context.getSharedPreferences(settingsName, Context.MODE_PRIVATE).edit()
            .putBoolean("updates", updates)
            .putBoolean("actions", actions)
            .putBoolean("ping", ping).apply()
        if (!updates) manager(context).cancel(updateId)
        if (NonaVpnService.state == "connected") publishVpn(context)
        refreshWidgets(context)
    }

    fun updatesEnabled(context: Context) =
        context.getSharedPreferences(settingsName, Context.MODE_PRIVATE).getBoolean("updates", true)

    fun setCountry(context: Context, country: String?) {
        val edit = context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).edit()
            .putString("country", country?.take(60))
            .remove("latency").remove("latencyMessage").remove("latencyAt")
        if (country != null) edit.putString("lastCountry", country.take(60))
        edit.apply()
        publishVpn(context)
    }

    fun restoreCountry(context: Context) {
        val last = context.getSharedPreferences(presentationName, Context.MODE_PRIVATE)
            .getString("lastCountry", null)
        setCountry(context, last)
    }

    fun clearCountry(context: Context) {
        context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).edit()
            .remove("country").remove("lastCountry").remove("latency")
            .remove("latencyMessage").remove("latencyAt").apply()
        publishVpn(context)
    }

    fun setLatency(context: Context, milliseconds: Int?) {
        val edit = context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).edit()
        if (milliseconds == null) edit.remove("latency") else edit.putInt("latency", milliseconds.coerceIn(1, 60000))
        edit.remove("latencyMessage").putLong("latencyAt", System.currentTimeMillis())
        edit.apply()
        publishVpn(context)
    }

    fun setLatencyError(context: Context) {
        context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).edit()
            .remove("latency").putString("latencyMessage", "Не удалось измерить задержку. Проверьте VPN и повторите.")
            .putLong("latencyAt", System.currentTimeMillis()).apply()
        publishVpn(context)
    }

    fun country(context: Context): String? =
        context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).getString("country", null)

    fun displayCountry(context: Context): String? =
        context.getSharedPreferences(presentationName, Context.MODE_PRIVATE).let {
            it.getString("country", null) ?: it.getString("lastCountry", null)
        }

    fun latency(context: Context): Int? {
        val prefs = context.getSharedPreferences(presentationName, Context.MODE_PRIVATE)
        return if (prefs.contains("latency")) prefs.getInt("latency", 0) else null
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(presentationName, Context.MODE_PRIVATE)
        return mapOf("country" to country(context), "latency" to latency(context),
            "latencyMessage" to prefs.getString("latencyMessage", null),
            "latencyAt" to prefs.getLong("latencyAt", 0L))
    }

    fun flaggedCountry(context: Context): String? = country(context)?.let {
        "${when (it) { "Нидерланды" -> "🇳🇱"; "Швеция" -> "🇸🇪"; else -> "🌐" }} $it"
    }

    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)

    private fun channels(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            manager(context).createNotificationChannel(
                NotificationChannel(vpnChannel, "Нона VPN", NotificationManager.IMPORTANCE_LOW),
            )
            manager(context).createNotificationChannel(
                NotificationChannel(updateChannel, "Обновления Ноны", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }

    private fun activityIntent(context: Context, action: String? = null, requestCode: Int = 0): PendingIntent =
        PendingIntent.getActivity(context, requestCode,
            Intent(context, MainActivity::class.java).apply {
                if (action != null) this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun receiverIntent(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(context, requestCode,
            Intent(context, NonaActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun connectIntent(context: Context) = receiverIntent(context, connectAction, 10)
    fun restartIntent(context: Context) = receiverIntent(context, restartAction, 11)
    fun stopIntent(context: Context) = receiverIntent(context, stopAction, 12)
    fun pingIntent(context: Context) = receiverIntent(context, pingAction, 13)

    fun vpnNotification(context: Context, state: String): Notification {
        channels(context)
        val prefs = context.getSharedPreferences(settingsName, Context.MODE_PRIVATE)
        val connected = state == "connected"
        val description = when (state) {
            "connected" -> listOfNotNull("VPN подключён", flaggedCountry(context),
                if (prefs.getBoolean("ping", false)) latency(context)?.let { "$it мс" } else null).joinToString(" · ")
            "disconnecting" -> "Отключаем VPN"
            "error" -> "Ошибка запуска VPN"
            else -> "Подключаем VPN"
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, vpnChannel)
            else Notification.Builder(context)
        builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Нона")
            .setContentText(description)
            .setContentIntent(activityIntent(context))
            .setOngoing(state != "error")
            .setOnlyAlertOnce(true)
        if (connected && prefs.getBoolean("actions", true)) {
            builder.addAction(Notification.Action.Builder(null, "Перезапустить", restartIntent(context)).build())
            builder.addAction(Notification.Action.Builder(null, "Отключить", stopIntent(context)).build())
        }
        if (connected && prefs.getBoolean("ping", false)) {
            builder.addAction(Notification.Action.Builder(null, "Проверить пинг", pingIntent(context)).build())
        }
        return builder.build()
    }

    fun publishVpn(context: Context) {
        val state = NonaVpnService.state
        if (state == "connected" || state == "connecting" || state == "disconnecting" || state == "error") {
            manager(context).notify(vpnId, vpnNotification(context, state))
        } else {
            manager(context).cancel(vpnId)
        }
        refreshWidgets(context)
    }

    fun showUpdate(context: Context, version: String, tag: String) {
        if (!updatesEnabled(context) || !Regex("^\\d+\\.\\d+\\.\\d+$").matches(version)) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val prefs = context.getSharedPreferences(settingsName, Context.MODE_PRIVATE)
        if (prefs.getString("lastUpdateTag", null) == tag) return
        channels(context)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, updateChannel)
            else Notification.Builder(context)
        manager(context).notify(updateId, builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Доступна Нона $version")
            .setContentText("Откройте приложение, чтобы обновиться")
            .setContentIntent(activityIntent(context, requestCode = 20))
            .setAutoCancel(true).build())
        prefs.edit().putString("lastUpdateTag", tag).apply()
    }
}
