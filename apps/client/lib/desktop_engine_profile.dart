import 'dart:convert';

import 'internet_routing.dart';

/// Builds system-tunnel configurations for desktop builds.
///
/// The server profile is generated and signature-checked by the existing
/// profile pipeline. This transforms only its local Xray config in memory;
/// configuration secrets must never be written to logs or preferences.
class DesktopEngineProfile {
  const DesktopEngineProfile._();

  static String windowsTun(
    String proxyConfigJson, {
    InternetRoutingState? routing,
  }) {
    return _tun(
      proxyConfigJson,
      routing: routing,
      settings: {
        'name': 'Nona',
        'desc': 'Nona VPN',
        'mtu': 1400,
        'gateway': ['10.0.0.1/30', 'fd00::1/126'],
        'dns': ['1.1.1.1', '2606:4700:4700::1111'],
        'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
        'autoOutboundsInterface': 'auto',
        'autoSystemWfpBlockLeak': ['dns', 'misconfigtun'],
      },
    );
  }

  static String macOsTun(
    String proxyConfigJson, {
    required String tunName,
    InternetRoutingState? routing,
  }) {
    if (!RegExp(r'^utun(?:[1-9]|[1-9][0-9]{1,2}|10[0-1][0-9]|102[0-4])$')
        .hasMatch(tunName)) {
      throw const FormatException('Invalid macOS tunnel interface name');
    }
    return _tun(
      proxyConfigJson,
      routing: routing,
      settings: {
        'name': tunName,
        'mtu': 1400,
        'gateway': ['10.0.0.1/30', 'fd00::1/126'],
        'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'],
        'autoOutboundsInterface': 'auto',
      },
    );
  }

  static String _tun(
    String proxyConfigJson, {
    required Map<String, Object?> settings,
    InternetRoutingState? routing,
  }) {
    final decoded = jsonDecode(proxyConfigJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['outbounds'] is! List ||
        (decoded['outbounds'] as List).isEmpty) {
      throw const FormatException('Invalid desktop proxy profile');
    }

    final outbounds = (decoded['outbounds'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Invalid desktop outbound');
      return Map<String, Object?>.from(raw);
    }).toList();
    if (outbounds.any((outbound) => outbound['tag'] != 'proxy')) {
      throw const FormatException('Unexpected desktop outbound');
    }

    final directDomains = <String>{};
    final proxyDomains = <String>{};
    if (routing != null) {
      final policy = routing.policy;
      for (final site in routing.sites) {
        final rule = 'domain:${site.domain}';
        if (policy.directSite(site)) {
          directDomains.add(rule);
        } else if (policy.siteOverrides[site.domain] == false) {
          proxyDomains.add(rule);
        }
      }
      directDomains.addAll(policy.customSites.map((site) => 'domain:$site'));
    }

    return jsonEncode({
      'log': {'loglevel': 'warning', 'access': 'none'},
      'inbounds': [
        {
          'tag': 'nona-tun',
          'protocol': 'tun',
          'settings': settings,
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': true,
          },
        },
      ],
      'outbounds': [
        ...outbounds,
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          if (proxyDomains.isNotEmpty)
            {
              'type': 'field',
              'domain': proxyDomains.toList(),
              'outboundTag': 'proxy',
            },
          if (directDomains.isNotEmpty)
            {
              'type': 'field',
              'domain': directDomains.toList(),
              'outboundTag': 'direct',
            },
          {
            'type': 'field',
            'ip': [
              '0.0.0.0/8',
              '10.0.0.0/8',
              '100.64.0.0/10',
              '127.0.0.0/8',
              '169.254.0.0/16',
              '172.16.0.0/12',
              '192.0.0.0/24',
              '192.168.0.0/16',
              '198.18.0.0/15',
              '224.0.0.0/4',
              '240.0.0.0/4',
              '::1/128',
              'fc00::/7',
              'fe80::/10',
            ],
            'outboundTag': 'direct',
          },
        ],
      },
    });
  }
}
