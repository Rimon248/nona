package com.example.nona_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
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
        @Volatile private var animatedProgress: Float? = null
        @Volatile private var animationSerial = 0

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, NonaWidgetProvider::class.java))
                .forEach { update(context, manager, it) }
        }

        fun animateToggle(context: Context, turnOn: Boolean, finished: () -> Unit) {
            val serial = synchronized(this) { ++animationSerial }
            Thread({
                try {
                    val start = if (turnOn) 0f else 1f
                    val end = if (turnOn) 1f else 0f
                    for (frame in 0..6) {
                        if (serial != animationSerial) break
                        animatedProgress = start + (end - start) * frame / 6f
                        updateAll(context)
                        if (frame < 6) Thread.sleep(45)
                    }
                } catch (_: Exception) {
                    // Keep the VPN action alive if a launcher rejects a widget update.
                } finally {
                    if (serial == animationSerial) {
                        animatedProgress = null
                        try { updateAll(context) } catch (_: Exception) { }
                    }
                    finished()
                }
            }, "nona-widget-toggle").start()
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val options = manager.getAppWidgetOptions(id)
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val width = options.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 70))
            val height = options.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 70))
            val columns = options.getInt("semAppWidgetColumnSpan", 0).takeIf { it in 1..4 }
                ?: when { width >= 310 -> 4; width >= 230 -> 3; width >= 140 -> 2; else -> 1 }
            val rows = options.getInt("semAppWidgetRowSpan", 0).takeIf { it in 1..3 }
                ?: when { height >= 250 -> 3; height >= 145 -> 2; else -> 1 }
            val kind = when {
                columns == 1 && rows >= 3 -> R.layout.nona_widget_vertical3
                columns == 1 && rows == 2 -> R.layout.nona_widget_vertical2
                columns == 1 -> R.layout.nona_widget
                columns == 2 && rows == 1 -> R.layout.nona_widget_medium
                columns >= 3 && rows == 1 -> R.layout.nona_widget_large
                columns == 2 && rows == 2 -> R.layout.nona_widget_square
                else -> R.layout.nona_widget_spacious
            }
            val state = NonaVpnService.currentState(context)
            val connected = state == "connected"
            val checked = connected || state == "connecting"
            val progress = animatedProgress ?: if (checked) 1f else 0f
            val views = RemoteViews(context.packageName, kind)
            views.setImageViewBitmap(R.id.widget_toggle, NonaWidgetSwitch.bitmap(context, progress, state == "connecting"))
            views.setOnClickPendingIntent(R.id.widget_toggle,
                if (checked) NonaPresentation.stopIntent(context) else NonaPresentation.connectIntent(context))
            views.setContentDescription(R.id.widget_toggle,
                when (state) {
                    "connecting" -> "Подключаем VPN. Нажмите, чтобы отменить"
                    "connected" -> "Нона VPN включён. Нажмите, чтобы отключить"
                    else -> "Нона VPN выключен. Нажмите, чтобы включить"
                })

            val hasCountry = kind != R.layout.nona_widget && kind != R.layout.nona_widget_vertical2
            if (hasCountry) {
                val country = if (connected) NonaPresentation.country(context) else null
                if (kind != R.layout.nona_widget_medium) {
                    views.setTextViewText(R.id.widget_country,
                        country ?: if (connected) "Нона VPN" else "Страна не выбрана")
                }
                if (kind != R.layout.nona_widget_vertical3) {
                    val flag = when (country) {
                        "Нидерланды" -> R.drawable.nona_flag_nl
                        "Швеция" -> R.drawable.nona_flag_se
                        else -> null
                    }
                    views.setViewVisibility(R.id.widget_flag, if (flag == null) View.GONE else View.VISIBLE)
                    if (flag != null) views.setImageViewResource(R.id.widget_flag, flag)
                    if (kind != R.layout.nona_widget_medium) views.setTextViewText(R.id.widget_status, when (state) {
                        "connected" -> "Подключено"
                        "connecting" -> "Подключаем"
                        "disconnecting" -> "Отключаем"
                        "error" -> "Ошибка запуска"
                        else -> "Не подключено"
                    })
                    val padding = if (flag == null) 0 else (23 * context.resources.displayMetrics.density).toInt()
                    if (kind == R.layout.nona_widget_large) {
                        views.setViewPadding(R.id.widget_status, padding, 0, 0, 0)
                    }
                }
            }
            val hasPing = kind == R.layout.nona_widget_vertical2 ||
                kind == R.layout.nona_widget_vertical3 || kind == R.layout.nona_widget_large ||
                kind == R.layout.nona_widget_square || kind == R.layout.nona_widget_spacious
            if (hasPing) {
                views.setTextViewText(R.id.widget_ping_value,
                    if (connected) NonaPresentation.latency(context)?.let { "$it мс" } ?: "— мс" else "— мс")
                if (kind != R.layout.nona_widget_vertical2) {
                    views.setOnClickPendingIntent(R.id.widget_ping, NonaPresentation.pingIntent(context))
                    views.setBoolean(R.id.widget_ping, "setEnabled", connected)
                }
            }
            manager.updateAppWidget(id, views)
        }
    }
}
