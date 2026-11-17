package com.example.nona_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NonaActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            NonaPresentation.stopAction -> NonaVpnService.stop(context)
            NonaPresentation.connectAction -> NonaVpnService.startSaved(context)
            NonaPresentation.restartAction -> NonaVpnService.restart(context)
            NonaPresentation.pingAction -> {
                val pending = goAsync()
                val appContext = context.applicationContext
                val generation = NonaVpnService.connectionGeneration()
                Thread({
                    try {
                        val latency = NonaVpnService.measureLatency(appContext)
                        if (generation == NonaVpnService.connectionGeneration() &&
                            NonaVpnService.currentState(appContext) == "connected") {
                            NonaPresentation.setLatency(appContext, latency)
                        }
                    } catch (_: Exception) {
                        if (generation == NonaVpnService.connectionGeneration() &&
                            NonaVpnService.currentState(appContext) == "connected") {
                            NonaPresentation.setLatencyError(appContext)
                        }
                    } finally {
                        pending.finish()
                    }
                }, "nona-notification-ping").start()
            }
        }
    }
}
