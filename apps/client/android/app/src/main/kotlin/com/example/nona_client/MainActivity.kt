package com.example.nona_client

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
