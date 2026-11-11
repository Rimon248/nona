package com.example.nona_client

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val vpnPermissionRequestCode = 50773
    private var vpnPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nona.app_routing")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> result.success(
                        mapOf(
                            "ownPackage" to packageName,
                            "directPackages" to InternetRouting.directPackages(this),
                            "apps" to InternetRouting.visibleApps(this),
                            "policy" to InternetRouting.read(this).asMap(),
                            "siteCatalogue" to InternetRouting.siteCatalogue(),
                            "appCatalogue" to InternetRouting.appCatalogue(),
                        ),
                    )
                    "saveInternetPolicy" -> {
                        val raw = call.arguments as? Map<*, *>
                        if (raw == null) result.error("BAD_POLICY", "Routing policy is invalid", null)
                        else try {
                            if (InternetRouting.save(this, raw)) result.success(null)
                            else result.error("SAVE_FAILED", "Could not save routing policy", null)
                        } catch (_: Exception) {
                            result.error("BAD_POLICY", "Routing policy is invalid", null)
                        }
                    }
                    "normalizeSite" -> {
                        val input = call.arguments as? String
                        if (input == null) result.error("BAD_SITE", "Invalid site", null)
                        else try {
                            result.success(InternetRouting.normalizeSiteInput(input))
                        } catch (_: Exception) {
                            result.error("BAD_SITE", "Use a domain or HTTPS address", null)
                        }
                    }
                    "saveDirectPackages" -> {
                        val raw = (call.arguments as? Map<*, *>)?.get("packages") as? List<*>
                        if (raw == null || raw.any { it !is String }) {
                            result.error("BAD_POLICY", "Package list is invalid", null)
                        } else {
                            try {
                                val saved = AndroidAppExclusions.save(this, raw.filterIsInstance<String>())
                                if (saved) result.success(null)
                                else result.error("SAVE_FAILED", "Could not save app policy", null)
                            } catch (error: IllegalArgumentException) {
                                result.error("BAD_POLICY", "Package list is invalid", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nona.vpn")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        if (vpnPermissionResult != null) {
                            result.error("BUSY", "VPN permission request is already open", null)
                        } else {
                            val permission = VpnService.prepare(this)
                            if (permission == null) result.success(true)
                            else {
                                vpnPermissionResult = result
                                startActivityForResult(permission, vpnPermissionRequestCode)
                            }
                        }
                    }
                    "start" -> {
                        val config = (call.arguments as? Map<*, *>)?.get("config") as? String
                        if (config == null || VpnService.prepare(this) != null) {
                            result.error("NOT_READY", "VPN permission or profile is missing", null)
                        } else {
                            try {
                                NonaVpnService.start(this, config)
                                result.success(null)
                            } catch (_: Exception) {
                                result.error("START_FAILED", "Could not start VPN service", null)
                            }
                        }
                    }
                    "status" -> result.success(NonaVpnService.currentState(this))
                    "measureLatency" -> {
                        Thread({
                            try {
                                val milliseconds = NonaVpnService.measureLatency(this)
                                runOnUiThread { result.success(milliseconds) }
                            } catch (_: Exception) {
                                runOnUiThread {
                                    result.error("LATENCY_FAILED", "Could not measure VPN latency", null)
                                }
                            }
                        }, "nona-latency").start()
                    }
                    "stop" -> {
                        NonaVpnService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnPermissionRequestCode) {
            vpnPermissionResult?.success(resultCode == RESULT_OK && VpnService.prepare(this) == null)
            vpnPermissionResult = null
        }
    }

    override fun onDestroy() {
        vpnPermissionResult?.error("CANCELLED", "VPN permission request was interrupted", null)
        vpnPermissionResult = null
        super.onDestroy()
    }

}
