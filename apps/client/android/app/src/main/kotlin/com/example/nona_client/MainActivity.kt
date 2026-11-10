package com.example.nona_client

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
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
                            "directPackages" to AndroidAppExclusions.read(this),
                            "apps" to launchableApps(),
                        ),
                    )
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

    private fun launchableApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val matches = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return matches.mapNotNull { entry ->
            val id = entry.activityInfo?.packageName ?: return@mapNotNull null
            if (id == packageName) return@mapNotNull null
            mapOf("packageName" to id, "label" to entry.loadLabel(packageManager).toString())
        }.distinctBy { it["packageName"] }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it["label"] ?: "" })
    }
}
