package com.example.nona_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NonaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            NonaPresentation.stopAction -> NonaVpnService.stop(context)
            NonaPresentation.pingAction -> {
                val pending = goAsync()
                val appContext = context.applicationContext
                Thread({
                    try {
                        NonaPresentation.setLatency(appContext, NonaVpnService.measureLatency(appContext))
                    } catch (_: Exception) {
                        NonaPresentation.setLatency(appContext, null)
                    } finally {
                        pending.finish()
                    }
                }, "nona-notification-ping").start()
            }
        }
    }
}
