package com.example.nona_client

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.IDN

/** Local routing settings. The two catalogues are suggestions, never proof of origin. */
internal object InternetRouting {
    private const val preferences = "nona_internet_routing_v2"
    private const val policyKey = "policy"
    private val packagePattern = Regex("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$")
    private val domainPattern = Regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$")

    data class Site(val domain: String, val label: String, val essential: Boolean = false, val zone: Boolean = false)
    data class App(val id: String, val essential: Boolean = false)

    val sites = (listOf(
        Site("ru", ".ru — сайты в российской зоне", zone = true),
        Site("xn--p1ai", ".рф — сайты в российской зоне", zone = true),
        Site("su", ".su — сайты в зоне .su", zone = true),
        Site("moscow", ".moscow — сайты в зоне Москвы", zone = true),
        Site("tatar", ".tatar — сайты в зоне Татарстана", zone = true),
        Site("xn--80adxhks", ".москва — сайты в зоне Москвы", zone = true),
        Site("gosuslugi.ru", "Госуслуги", essential = true),
        Site("nalog.gov.ru", "ФНС", essential = true),
        Site("government.ru", "Правительство России", essential = true),
        Site("sberbank.ru", "Сбер", essential = true),
        Site("vtb.ru", "ВТБ", essential = true),
        Site("tbank.ru", "Т-Банк", essential = true),
        Site("alfabank.ru", "Альфа-Банк", essential = true),
        Site("nspk.ru", "НСПК", essential = true),
        Site("pochta.ru", "Почта России", essential = true),
        Site("yandex.ru", "Яндекс"),
        Site("yandex.com", "Яндекс — международный домен"),
        Site("vk.com", "ВКонтакте"),
        Site("vk.ru", "ВКонтакте — основной адрес", essential = true),
        Site("max.ru", "MAX", essential = true),
        Site("mail.ru", "Почта Mail"),
        Site("ozon.ru", "Ozon"),
        Site("wildberries.ru", "Wildberries"),
        Site("avito.ru", "Авито"),
        Site("2gis.ru", "2ГИС"),
    ) + BankSites.domains.map { (domain, bank) ->
        Site(domain, "Банк: $bank", essential = true)
    }).distinctBy { it.domain }
    val apps = listOf(
        App("ru.rostel", essential = true),
        App("ru.oneme.app", essential = true),
        App("ru.sberbankmobile", essential = true),
        App("ru.vtb24.mobilebanking.android", essential = true),
        App("ru.alfabank.mobile.android", essential = true),
        App("com.idamob.tinkoff.android", essential = true),
        App("ru.gosuslugi.goskey", essential = true),
        App("com.gnivts.selfemployed", essential = true),
        App("ru.sigma.gisgkh", essential = true),
        App("ru.gosuslugi.auto", essential = true),
        App("ru.gosuslugi.pos", essential = true),
        App("ru.rtlabs.mobile.ebs.gosuslugi.android", essential = true),
        App("ru.rosreestr.mobile", essential = true),
        App("ru.sitesoft.fssp", essential = true),
        App("io.citizens.security", essential = true),
        App("ru.gazprombank.android.mobilebank.app", essential = true),
        App("ru.sovcomcard.halva.v1", essential = true),
        App("ru.ozon.fintech.finance", essential = true),
        App("ru.wildberries.bank", essential = true),
        App("logo.com.mbanking", essential = true),
        App("ru.yandex.taxi"),
        App("ru.mail.mailapp"),
        App("com.vkontakte.android", essential = true),
        App("com.vk.im"),
    )

    data class Policy(
        val sitesMode: String = "all",
        val appsMode: String = "all",
        val siteOverrides: Map<String, Boolean> = emptyMap(),
        val appOverrides: Map<String, Boolean> = emptyMap(),
        val customSites: List<String> = emptyList(),
    ) {
        fun asMap(): Map<String, Any> = mapOf(
            "sitesMode" to sitesMode,
            "appsMode" to appsMode,
            "siteOverrides" to siteOverrides,
            "appOverrides" to appOverrides,
            "customSites" to customSites,
        )
        fun asJson(): JSONObject = JSONObject(asMap())
    }

    private fun normalizedDomain(value: String): String {
        val ascii = IDN.toASCII(value.trim().trimEnd('.'), IDN.USE_STD3_ASCII_RULES).lowercase()
        require(ascii.length in 3..253 && domainPattern.matches(ascii) &&
            ascii.split('.').all { it.length in 1..63 && !it.startsWith('-') && !it.endsWith('-') }) {
            "Invalid domain"
        }
        return ascii
    }

    fun normalizeSiteInput(input: String): String {
        val value = input.trim()
        require(value.isNotEmpty() && value.none { it.isWhitespace() }) { "Invalid site" }
        val url = Uri.parse(if (value.contains("://")) value else "https://$value")
        require(url.scheme == "https" && url.userInfo == null && url.host != null && url.port == -1) {
            "HTTPS domain required"
        }
        val host = url.host!!.removePrefix("www.")
        val ascii = normalizedDomain(host)
        require(!Regex("^\\d+(\\.\\d+){3}$").matches(ascii)) { "IP address is not a site" }
        return ascii
    }

    private fun parsed(raw: Map<*, *>): Policy {
        require(raw.keys == setOf("sitesMode", "appsMode", "siteOverrides", "appOverrides", "customSites"))
        val sitesMode = raw["sitesMode"] as? String ?: error("Invalid site mode")
        val appsMode = raw["appsMode"] as? String ?: error("Invalid app mode")
        require(sitesMode in setOf("off", "all", "essential") && appsMode in setOf("off", "all", "essential"))
        val siteRaw = raw["siteOverrides"] as? Map<*, *> ?: error("Invalid site overrides")
        val appRaw = raw["appOverrides"] as? Map<*, *> ?: error("Invalid app overrides")
        val customRaw = raw["customSites"] as? List<*> ?: error("Invalid custom sites")
        // "Select all" can include every launchable package on a device; keep a
        // generous bound to reject malformed payloads without blocking that use.
        require(siteRaw.size <= sites.size && appRaw.size <= 2000 && customRaw.size <= 200)
        val siteIds = sites.map { it.domain }.toSet()
        val siteOverrides = siteRaw.map { (key, value) ->
            require(key is String && key in siteIds && value is Boolean)
            key to value
        }.toMap()
        val appOverrides = appRaw.map { (key, value) ->
            require(key is String && packagePattern.matches(key) && value is Boolean)
            key to value
        }.toMap()
        val custom = customRaw.map {
            require(it is String)
            normalizedDomain(it)
        }.distinct().sorted()
        return Policy(sitesMode, appsMode, siteOverrides, appOverrides, custom)
    }

    fun read(context: Context): Policy {
        val saved = context.getSharedPreferences(preferences, Context.MODE_PRIVATE).getString(policyKey, null)
        if (saved == null) {
            // Preserve existing manually excluded applications during migration.
            return Policy(appOverrides = AndroidAppExclusions.readLegacy(context).associateWith { true })
        }
        val json = JSONObject(saved)
        val siteOverrides = json.getJSONObject("siteOverrides")
        val appOverrides = json.getJSONObject("appOverrides")
        val raw = mapOf(
            "sitesMode" to json.getString("sitesMode"),
            "appsMode" to json.getString("appsMode"),
            "siteOverrides" to siteOverrides.keys().asSequence().associateWith { siteOverrides.getBoolean(it) },
            "appOverrides" to appOverrides.keys().asSequence().associateWith { appOverrides.getBoolean(it) },
            "customSites" to (0 until json.getJSONArray("customSites").length()).map {
                json.getJSONArray("customSites").getString(it)
            },
        )
        return parsed(raw)
    }

    fun save(context: Context, raw: Map<*, *>): Boolean {
        val policy = parsed(raw)
        return context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            .edit().putString(policyKey, policy.asJson().toString()).commit()
    }

    fun visibleApps(context: Context): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val matches = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.queryIntentActivities(intent, 0)
        }
        val launchable = matches.mapNotNull { it.activityInfo?.packageName }.toSet()
        val installed = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstalledApplications(0)
        }
        return installed.asSequence()
            .filter { it.packageName != context.packageName }
            .filter { it.flags and ApplicationInfo.FLAG_SYSTEM == 0 || it.packageName in launchable }
            .map { mapOf("packageName" to it.packageName, "label" to it.loadLabel(context.packageManager).toString()) }
            .distinctBy { it["packageName"] }
            .toList()
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it["label"] ?: "" })
    }

    fun directPackages(context: Context): List<String> {
        val policy = read(context)
        val catalogue = apps.associateBy { it.id }
        // Only pass installed packages to VpnService.Builder. Stale saved rules
        // for apps the user removed can make addDisallowedApplication fail.
        val candidates = visibleApps(context).mapNotNull { it["packageName"] }.toSet()
        return candidates.filter { id ->
            policy.appOverrides[id] ?: when (policy.appsMode) {
                "all" -> id.startsWith("ru.") || catalogue.containsKey(id)
                "essential" -> catalogue[id]?.essential == true
                else -> false
            }
        }.sorted()
    }

    fun decorateProfile(context: Context, profile: JSONObject): JSONObject {
        val policy = read(context)
        val custom = policy.customSites.map { "domain:$it" }
        val blocked = policy.siteOverrides.filterValues { !it }.keys.map { "domain:$it" }
        val automatic = sites.filter { site ->
            policy.siteOverrides[site.domain] ?: when (policy.sitesMode) {
                "all" -> true
                "essential" -> site.essential
                else -> false
            }
        }.map { "domain:${it.domain}" }
        val direct = (custom + automatic).distinct()
        if (direct.isEmpty()) return profile
        profile.getJSONArray("outbounds").put(JSONObject().put("tag", "direct").put("protocol", "freedom"))
        val rules = JSONArray()
        if (custom.isNotEmpty()) rules.put(rule(custom, "direct"))
        if (blocked.isNotEmpty()) rules.put(rule(blocked, "proxy"))
        if (automatic.isNotEmpty()) rules.put(rule(automatic, "direct"))
        profile.put("routing", JSONObject().put("domainStrategy", "AsIs").put("rules", rules))
        return profile
    }

    private fun rule(domains: List<String>, outbound: String) = JSONObject()
        .put("type", "field")
        .put("domain", JSONArray(domains))
        .put("outboundTag", outbound)

    fun siteCatalogue(): List<Map<String, Any>> = sites.map {
        mapOf("domain" to it.domain, "label" to it.label, "essential" to it.essential, "zone" to it.zone)
    }

    fun appCatalogue(): List<Map<String, Any>> = apps.map {
        mapOf("packageName" to it.id, "essential" to it.essential)
    }
}
