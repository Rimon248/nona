import 'package:flutter/services.dart';

import 'android_app_routing.dart';

enum DirectMode { off, all, essential }

class RussianSite {
  const RussianSite({
    required this.domain,
    required this.label,
    required this.essential,
    required this.zone,
  });
  final String domain;
  final String label;
  final bool essential;
  final bool zone;
}

class RussianApp {
  const RussianApp({required this.packageName, required this.essential});
  final String packageName;
  final bool essential;
}

class InternetPolicy {
  const InternetPolicy({
    required this.sitesMode,
    required this.appsMode,
    required this.siteOverrides,
    required this.appOverrides,
    required this.customSites,
  });

  final DirectMode sitesMode;
  final DirectMode appsMode;
  final Map<String, bool> siteOverrides;
  final Map<String, bool> appOverrides;
  final List<String> customSites;

  bool directSite(RussianSite site) =>
      siteOverrides[site.domain] ??
      (sitesMode == DirectMode.all ||
          (sitesMode == DirectMode.essential && site.essential));

  bool directApp(String id, Map<String, RussianApp> catalogue) =>
      appOverrides[id] ??
      (appsMode == DirectMode.all
          ? id.startsWith('ru.') || catalogue.containsKey(id)
          : appsMode == DirectMode.essential &&
                catalogue[id]?.essential == true);

  InternetPolicy withSitesMode(DirectMode mode) => InternetPolicy(
    sitesMode: mode,
    appsMode: appsMode,
    siteOverrides: siteOverrides,
    appOverrides: appOverrides,
    customSites: customSites,
  );

  InternetPolicy withAppsMode(DirectMode mode) => InternetPolicy(
    sitesMode: sitesMode,
    appsMode: mode,
    siteOverrides: siteOverrides,
    appOverrides: appOverrides,
    customSites: customSites,
  );

  InternetPolicy withSite(RussianSite site, bool direct) {
    final updated = Map<String, bool>.of(siteOverrides);
    final automatic =
        sitesMode == DirectMode.all ||
        (sitesMode == DirectMode.essential && site.essential);
    if (direct == automatic) {
      updated.remove(site.domain);
    } else {
      updated[site.domain] = direct;
    }
    return InternetPolicy(
      sitesMode: sitesMode,
      appsMode: appsMode,
      siteOverrides: updated,
      appOverrides: appOverrides,
      customSites: customSites,
    );
  }

  InternetPolicy withApp(
    String id,
    bool direct,
    Map<String, RussianApp> catalogue,
  ) {
    final updated = Map<String, bool>.of(appOverrides);
    final automatic = appsMode == DirectMode.all
        ? id.startsWith('ru.') || catalogue.containsKey(id)
        : appsMode == DirectMode.essential && catalogue[id]?.essential == true;
    if (direct == automatic) {
      updated.remove(id);
    } else {
      updated[id] = direct;
    }
    return InternetPolicy(
      sitesMode: sitesMode,
      appsMode: appsMode,
      siteOverrides: siteOverrides,
      appOverrides: updated,
      customSites: customSites,
    );
  }

  InternetPolicy withCustomSites(Iterable<String> domains) => InternetPolicy(
    sitesMode: sitesMode,
    appsMode: appsMode,
    siteOverrides: siteOverrides,
    appOverrides: appOverrides,
    customSites: domains.toSet().toList()..sort(),
  );

  Map<String, Object> toChannel() => {
    'sitesMode': sitesMode.name,
    'appsMode': appsMode.name,
    'siteOverrides': siteOverrides,
    'appOverrides': appOverrides,
    'customSites': customSites,
  };

  static InternetPolicy fromChannel(Map<Object?, Object?> raw) {
    DirectMode mode(Object? value) => DirectMode.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => throw const FormatException('Invalid routing mode'),
    );
    Map<String, bool> overrides(Object? value) {
      if (value is! Map) throw const FormatException('Invalid routing rules');
      return value.map((key, value) {
        if (key is! String || value is! bool) {
          throw const FormatException('Invalid routing rule');
        }
        return MapEntry(key, value);
      });
    }

    final custom = raw['customSites'];
    if (custom is! List || custom.any((value) => value is! String)) {
      throw const FormatException('Invalid custom sites');
    }
    return InternetPolicy(
      sitesMode: mode(raw['sitesMode']),
      appsMode: mode(raw['appsMode']),
      siteOverrides: overrides(raw['siteOverrides']),
      appOverrides: overrides(raw['appOverrides']),
      customSites: custom.cast<String>(),
    );
  }
}

class InternetRoutingState {
  const InternetRoutingState({
    required this.apps,
    required this.sites,
    required this.appCatalogue,
    required this.policy,
  });
  final List<LaunchableApp> apps;
  final List<RussianSite> sites;
  final Map<String, RussianApp> appCatalogue;
  final InternetPolicy policy;
}

class InternetRoutingClient {
  InternetRoutingClient([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('nona.app_routing');
  final MethodChannel _channel;

  Future<InternetRoutingState> load() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getState');
    if (raw == null ||
        raw['apps'] is! List ||
        raw['siteCatalogue'] is! List ||
        raw['appCatalogue'] is! List ||
        raw['policy'] is! Map) {
      throw const FormatException('Invalid routing response');
    }
    final apps = (raw['apps'] as List).map((item) {
      if (item is! Map ||
          item['packageName'] is! String ||
          item['label'] is! String) {
        throw const FormatException('Invalid application');
      }
      return LaunchableApp(
        packageName: item['packageName'] as String,
        label: item['label'] as String,
      );
    }).toList();
    final sites = (raw['siteCatalogue'] as List).map((item) {
      if (item is! Map ||
          item['domain'] is! String ||
          item['label'] is! String ||
          item['essential'] is! bool ||
          item['zone'] is! bool) {
        throw const FormatException('Invalid site catalogue');
      }
      return RussianSite(
        domain: item['domain'] as String,
        label: item['label'] as String,
        essential: item['essential'] as bool,
        zone: item['zone'] as bool,
      );
    }).toList();
    final catalogue = <String, RussianApp>{};
    for (final item in raw['appCatalogue'] as List) {
      if (item is! Map ||
          item['packageName'] is! String ||
          item['essential'] is! bool) {
        throw const FormatException('Invalid app catalogue');
      }
      final id = item['packageName'] as String;
      catalogue[id] = RussianApp(
        packageName: id,
        essential: item['essential'] as bool,
      );
    }
    return InternetRoutingState(
      apps: apps,
      sites: sites,
      appCatalogue: catalogue,
      policy: InternetPolicy.fromChannel(
        (raw['policy'] as Map).cast<Object?, Object?>(),
      ),
    );
  }

  Future<void> save(InternetPolicy policy) async {
    await _channel.invokeMethod<void>('saveInternetPolicy', policy.toChannel());
  }

  Future<String> normalizeSite(String input) async {
    final site = await _channel.invokeMethod<String>('normalizeSite', input);
    if (site == null || site.isEmpty) {
      throw const FormatException('Неверный домен');
    }
    return site;
  }
}

/// Returns the host of an HTTPS URL or a bare domain. Rules include subdomains.
String normalizeCustomSite(String input) {
  final value = input.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    throw const FormatException('Введите домен сайта');
  }
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      uri.host.contains(':')) {
    throw const FormatException('Нужен домен или HTTPS-адрес');
  }
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  if (!RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(host) ||
      host.length > 253 ||
      host
          .split('.')
          .any(
            (part) =>
                part.isEmpty ||
                part.length > 63 ||
                part.startsWith('-') ||
                part.endsWith('-'),
          ) ||
      RegExp(r'^\d+(\.\d+){3}$').hasMatch(host)) {
    throw const FormatException('Укажите домен, например example.ru');
  }
  return host;
}
