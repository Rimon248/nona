import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/desktop_engine_profile.dart';
import 'package:nona_client/internet_routing.dart';

void main() {
  test('desktop route exceptions precede a broad direct zone', () {
    const state = InternetRoutingState(
      apps: [],
      sites: [
        RussianSite(domain: 'ru', label: '.ru', essential: false, zone: true),
        RussianSite(
          domain: 'example.ru',
          label: 'Example',
          essential: false,
          zone: false,
        ),
      ],
      appCatalogue: {},
      policy: InternetPolicy(
        sitesMode: DirectMode.all,
        appsMode: DirectMode.off,
        siteOverrides: {'example.ru': false},
        appOverrides: {},
        customSites: ['extra.example'],
      ),
    );
    const proxy = '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';
    final config = jsonDecode(
      DesktopEngineProfile.windowsTun(proxy, routing: state),
    ) as Map<String, dynamic>;
    final rules = (config['routing'] as Map)['rules'] as List;
    expect(rules[0]['outboundTag'], 'proxy');
    expect(rules[0]['domain'], contains('domain:example.ru'));
    expect(rules[1]['outboundTag'], 'direct');
    expect(
      rules[1]['domain'],
      containsAll(['domain:ru', 'domain:extra.example']),
    );
  });
}
