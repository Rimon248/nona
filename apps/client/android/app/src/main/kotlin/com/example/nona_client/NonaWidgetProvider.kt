package com.example.nona_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class NonaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NonaWidgetProvider::class.java))
            ids.forEach { update(context, manager, it) }
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val width = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 70)
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 70)
            val state = NonaVpnService.currentState(context)
            val connected = state == "connected"
            val vertical = height >= 110 && height > width * 1.3
            val views = RemoteViews(context.packageName,
                if (vertical) R.layout.nona_widget_vertical else R.layout.nona_widget)
            val countryVisible = width >= 110 || height >= 110
            val pingVisible = width >= 180 || height >= 180
            val extraVisible = width >= 250 || (width >= 110 && height >= 110)
            if (!vertical) views.setViewVisibility(R.id.widget_details,
                if (countryVisible) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_toggle, if (connected) "Выкл" else "Вкл")
            views.setOnClickPendingIntent(R.id.widget_toggle,
                if (connected) NonaPresentation.stopIntent(context) else NonaPresentation.connectIntent(context))
            views.setViewVisibility(R.id.widget_country, if (countryVisible) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_country,
                if (connected) NonaPresentation.country(context) ?: "VPN подключён" else "Нона VPN")
            views.setViewVisibility(R.id.widget_ping, if (pingVisible) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_ping_value, if (pingVisible) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_ping_value,
                if (connected) NonaPresentation.latency(context)?.let { "$it мс" } ?: "— мс" else "— мс")
            views.setOnClickPendingIntent(R.id.widget_ping, NonaPresentation.pingIntent(context))
            views.setViewVisibility(R.id.widget_restart, if (extraVisible && connected) View.VISIBLE else View.GONE)
            views.setOnClickPendingIntent(R.id.widget_restart, NonaPresentation.restartIntent(context))
            views.setViewVisibility(R.id.widget_status, if (extraVisible) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.widget_status, when (state) {
                "connected" -> "Подключено · нажмите, чтобы отключить"
                "connecting" -> "Подключаем VPN"
                "disconnecting" -> "Отключаем VPN"
                else -> "Не подключено · нажмите, чтобы включить"
            })
            manager.updateAppWidget(id, views)
        }
    }
}
