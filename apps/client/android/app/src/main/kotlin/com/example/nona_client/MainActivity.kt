package com.example.nona_client

import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val vpnPermissionRequestCode = 50773
    private val updatePermissionRequestCode = 50774
    private var vpnPermissionResult: MethodChannel.Result? = null
    private var updatePermissionResult: MethodChannel.Result? = null
    private var pendingUpdateFile: File? = null
    private val routingExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "nona-routing-loader")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nona.app_update")
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val args = call.arguments as? Map<*, *>
                val url = args?.get("url") as? String
                val sha256 = args?.get("sha256") as? String
                val tag = args?.get("tag") as? String
                if (url == null || sha256 == null || tag == null) {
                    result.error("BAD_APK", "Update information is incomplete", null)
                    return@setMethodCallHandler
                }
                Thread({
                    try {
                        val apk = AndroidUpdateInstaller.downloadAndVerify(
                            applicationContext, url, sha256, tag,
                        )
                        runOnUiThread { openUpdateInstaller(apk, result) }
                    } catch (error: IllegalArgumentException) {
                        runOnUiThread {
                            result.error("BAD_APK", "Downloaded update did not pass verification", null)
                        }
                    } catch (_: Exception) {
                        runOnUiThread {
                            result.error("DOWNLOAD_FAILED", "Could not download update", null)
                        }
                    }
                }, "nona-app-update").start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nona.app_routing")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> routingExecutor.execute {
                        try {
                            val context = applicationContext
                            val apps = InternetRouting.visibleApps(context)
                            val state = mapOf(
                                "ownPackage" to packageName,
                                "directPackages" to InternetRouting.directPackages(
                                    context,
                                    apps.mapNotNull { it["packageName"] },
                                ),
                                "apps" to apps,
                                "policy" to InternetRouting.read(context).asMap(),
                                "siteCatalogue" to InternetRouting.siteCatalogue(),
                                "appCatalogue" to InternetRouting.appCatalogue(),
                            )
                            runOnUiThread { result.success(state) }
                        } catch (_: Exception) {
                            runOnUiThread {
                                result.error(
                                    "ROUTING_LOAD_FAILED",
                                    "Could not load routing data",
                                    null,
                                )
                            }
                        }
                    }
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

    private fun openUpdateInstaller(apk: File, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            if (updatePermissionResult != null) {
                result.error("INSTALL_PERMISSION", "Update permission request is already open", null)
                return
            }
            updatePermissionResult = result
            pendingUpdateFile = apk
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                    },
                    updatePermissionRequestCode,
                )
            } catch (_: Exception) {
                updatePermissionResult = null
                pendingUpdateFile = null
                result.error("INSTALL_PERMISSION", "Could not open update permission settings", null)
            }
            return
        }
        try {
            startActivity(AndroidUpdateInstaller.installerIntent(this, apk))
            result.success(null)
        } catch (_: Exception) {
            result.error("INSTALL_FAILED", "Could not open Android package installer", null)
        }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnPermissionRequestCode) {
            vpnPermissionResult?.success(resultCode == RESULT_OK && VpnService.prepare(this) == null)
            vpnPermissionResult = null
        } else if (requestCode == updatePermissionRequestCode) {
            val result = updatePermissionResult
            val apk = pendingUpdateFile
            updatePermissionResult = null
            pendingUpdateFile = null
            if (result != null) {
                if (apk != null && (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())) {
                    openUpdateInstaller(apk, result)
                } else {
                    result.error("INSTALL_PERMISSION", "Update installation was not allowed", null)
                }
            }
        }
    }

    override fun onDestroy() {
        vpnPermissionResult?.error("CANCELLED", "VPN permission request was interrupted", null)
        vpnPermissionResult = null
        updatePermissionResult?.error("CANCELLED", "Update permission request was interrupted", null)
        updatePermissionResult = null
        pendingUpdateFile = null
        super.onDestroy()
    }

}
