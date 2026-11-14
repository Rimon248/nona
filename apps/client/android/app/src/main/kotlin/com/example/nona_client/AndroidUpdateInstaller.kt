package com.example.nona_client

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

internal object AndroidUpdateInstaller {
    private const val maxApkBytes = 150L * 1024 * 1024

    fun downloadAndVerify(context: Context, url: String, sha256: String, tag: String): File {
        require(Regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$").matches(tag))
        require(Regex("^[0-9a-f]{64}$").matches(sha256))
        val address = URL(url)
        require(address.protocol == "https" && address.host == "github.com")
        require(address.path == "/Rimon248/nona/releases/download/$tag/nona-$tag-android.apk")

        val directory = File(context.cacheDir, "updates").apply { mkdirs() }
        val temporary = File(directory, "download.part")
        val apk = File(directory, "nona-update.apk")
        temporary.delete()
        val connection = address.openConnection() as HttpURLConnection
        connection.connectTimeout = 10000
        connection.readTimeout = 30000
        connection.setRequestProperty("User-Agent", "Nona-App-Update")
        try {
            require(connection.responseCode == HttpURLConnection.HTTP_OK)
            require(connection.contentLengthLong in 1..maxApkBytes)
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            connection.inputStream.use { input ->
                temporary.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= maxApkBytes)
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                    }
                }
            }
            require(total == connection.contentLengthLong)
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            require(actual == sha256)

            val archive = context.packageManager.getPackageArchiveInfo(temporary.path, 0)
                ?: throw IllegalArgumentException("Downloaded file is not an APK")
            require(archive.packageName == context.packageName)
            val installed = context.packageManager.getPackageInfo(context.packageName, 0)
            require(versionCode(archive) > versionCode(installed))

            apk.delete()
            require(temporary.renameTo(apk))
            return apk
        } finally {
            connection.disconnect()
            temporary.delete()
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    fun installerIntent(context: Context, apk: File): Intent {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.updates",
            apk,
        )
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
}
