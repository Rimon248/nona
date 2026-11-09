package com.example.nona_client

import android.net.VpnService

/**
 * Applies explicit direct-route exceptions before VpnService.Builder.establish().
 * A missing package raises NameNotFoundException; the future VPN service must
 * stop connection setup rather than silently omit a requested exception.
 */
internal object AndroidAppExclusions {
    private val packageName = Regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$")

    fun apply(
        builder: VpnService.Builder,
        ownPackage: String,
        directPackages: Collection<String>,
    ) {
        require(packageName.matches(ownPackage)) { "Invalid VPN package ID" }
        for (id in directPackages.toSortedSet()) {
            require(packageName.matches(id) && id != ownPackage) { "Invalid direct-route package ID" }
            builder.addDisallowedApplication(id)
        }
    }
}
