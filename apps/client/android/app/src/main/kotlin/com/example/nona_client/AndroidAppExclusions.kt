package com.example.nona_client

import android.content.Context
import android.net.VpnService

/**
 * Applies explicit direct-route exceptions before VpnService.Builder.establish().
 * A missing package raises NameNotFoundException; the future VPN service must
 * stop connection setup rather than silently omit a requested exception.
 */
internal object AndroidAppExclusions {
    private const val preferencesName = "nona_app_routing_v1"
    private const val directPackagesKey = "direct_packages"
    private val packagePattern = Regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$")

    fun readLegacy(context: Context): List<String> =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getStringSet(directPackagesKey, emptySet())
            .orEmpty()
            .toSortedSet()
            .toList()

    fun save(context: Context, directPackages: Collection<String>): Boolean {
        val packages = normalized(context.packageName, directPackages)
        return context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(directPackagesKey, packages.toSet())
            .commit()
    }

    private fun normalized(ownPackage: String, directPackages: Collection<String>): List<String> {
        require(packagePattern.matches(ownPackage)) { "Invalid VPN package ID" }
        val packages = directPackages.toSortedSet()
        for (id in packages) {
            require(packagePattern.matches(id) && id != ownPackage) { "Invalid direct-route package ID" }
        }
        return packages.toList()
    }

    /** Called by the VPN service before establish(), even if the UI is closed. */
    fun applySaved(builder: VpnService.Builder, context: Context) {
        apply(builder, context.packageName, InternetRouting.directPackages(context))
    }

    fun apply(
        builder: VpnService.Builder,
        ownPackage: String,
        directPackages: Collection<String>,
    ) {
        for (id in normalized(ownPackage, directPackages)) {
            builder.addDisallowedApplication(id)
        }
    }
}
