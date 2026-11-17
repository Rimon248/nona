package com.example.nona_client

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Periodic release check. It only reads public release metadata; installation stays in the app. */
class UpdateCheckJob : JobService() {
    companion object {
        private const val jobId = 21410
        private const val period = 6L * 60L * 60L * 1000L

        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            if (scheduler.getPendingJob(jobId) != null) return
            scheduler.schedule(JobInfo.Builder(jobId, ComponentName(context, UpdateCheckJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(period)
                .setPersisted(true)
                .build())
        }

        fun cancel(context: Context) {
            context.getSystemService(JobScheduler::class.java).cancel(jobId)
        }

        private fun newer(candidate: String, installed: String): Boolean {
            val pattern = Regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)(?:\\+\\d+)?$")
            val next = pattern.matchEntire(candidate)?.groupValues?.drop(1)?.map { it.toInt() } ?: return false
            val current = pattern.matchEntire(installed)?.groupValues?.drop(1)?.map { it.toInt() } ?: return false
            for (i in 0..2) {
                if (next[i] != current[i]) return next[i] > current[i]
            }
            return false
        }
    }

    @Volatile private var stopped = false

    override fun onStartJob(params: JobParameters): Boolean {
        stopped = false
        Thread({
            try {
                if (NonaPresentation.updatesEnabled(this)) checkRelease()
            } catch (_: Exception) {
                // The next scheduled check will retry after network failures.
            } finally {
                if (!stopped) jobFinished(params, false)
            }
        }, "nona-update-check").start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopped = true
        return true
    }

    private fun checkRelease() {
        val connection = URL("https://api.github.com/repos/Rimon248/nona/releases/latest")
            .openConnection() as HttpsURLConnection
        connection.connectTimeout = 7000
        connection.readTimeout = 7000
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        connection.setRequestProperty("User-Agent", "Nona-App-Update-Check")
        try {
            if (connection.responseCode != 200) return
            val data = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val tag = data.optString("tag_name")
            val version = tag.removePrefix("v")
            val installed = packageManager.getPackageInfo(packageName, 0).versionName ?: return
            if (!newer(version, installed)) return
            val assets = data.optJSONArray("assets") ?: return
            val expected = "nona-$tag-android.apk"
            for (i in 0 until assets.length()) {
                val asset = assets.optJSONObject(i) ?: continue
                val address = asset.optString("browser_download_url")
                if (asset.optString("name") == expected &&
                    asset.optString("digest").matches(Regex("^sha256:[0-9a-fA-F]{64}$")) &&
                    address.startsWith("https://github.com/Rimon248/nona/releases/download/")) {
                    NonaPresentation.showUpdate(this, version, tag)
                    return
                }
            }
        } finally {
            connection.disconnect()
        }
    }
}
