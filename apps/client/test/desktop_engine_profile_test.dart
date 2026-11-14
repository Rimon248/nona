import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/android_app_routing.dart';
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
    expect(rules[0]['outboundTag'], 'dns-out');
    expect(rules[0]['inboundTag'], ['nona-tun']);
    expect(rules[1]['domain'], ['domain:extra.example']);
    expect(rules[1]['outboundTag'], 'direct');
    expect(rules[2]['domain'], ['domain:example.ru']);
    expect(rules[2]['outboundTag'], 'proxy');
    expect(rules[3]['domain'], ['domain:ru']);
    expect(rules[3]['outboundTag'], 'direct');
    final dns = config['dns'] as Map;
    expect(dns['queryStrategy'], 'UseIPv4');
    expect(
      (dns['servers'] as List).first['domains'],
      containsAll(['domain:ru', 'domain:extra.example']),
    );
    expect(config['fakedns'], [
      {'ipPool': '198.19.0.0/16', 'poolSize': 65535},
    ]);
    final inbound = (config['inbounds'] as List).single as Map;
    expect(inbound['sniffing']['destOverride'], contains('fakedns'));
    expect(inbound['sniffing']['routeOnly'], false);
    final settings = inbound['settings'] as Map;
    expect(settings['mtu'], 1280);
    expect(settings['gateway'], ['10.0.0.1/30']);
    expect(settings['dns'], ['1.1.1.1']);
    expect(settings['autoSystemRoutingTable'], ['0.0.0.0/0']);
    expect(settings['autoSystemWfpBlockLeak'], ['dns', 'misconfigtun']);
  });

  test('Windows without direct sites keeps ordinary DNS and IPv4 routes', () {
    const proxy = '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';
    final config = jsonDecode(DesktopEngineProfile.windowsTun(proxy)) as Map;
    expect(config.containsKey('fakedns'), false);
    expect(config.containsKey('dns'), false);
    expect(
      (config['outbounds'] as List).where((o) => o['tag'] == 'dns-out'),
      isEmpty,
    );
    final inbound = (config['inbounds'] as List).single as Map;
    expect(inbound['sniffing']['routeOnly'], true);
    expect(inbound['settings']['autoSystemRoutingTable'], ['0.0.0.0/0']);
  });

  test(
    'Windows routes a selected process directly, including a closed app',
    () {
      const state = InternetRoutingState(
        apps: [LaunchableApp(packageName: 'chrome', label: 'chrome.exe')],
        sites: [],
        appCatalogue: {},
        policy: InternetPolicy(
          sitesMode: DirectMode.off,
          appsMode: DirectMode.off,
          siteOverrides: {},
          appOverrides: {'chrome': true, 'anotherApp': true, 'bad/path': true},
          customSites: [],
        ),
      );
      const proxy = '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';
      final windows = jsonDecode(
        DesktopEngineProfile.windowsTun(proxy, routing: state),
      ) as Map<String, dynamic>;
      final windowsRules = (windows['routing'] as Map)['rules'] as List;
      expect(
        windowsRules.first['process'],
        containsAll(['chrome', 'anotherApp']),
      );
      expect(windowsRules.first['process'], isNot(contains('bad/path')));

      final mac = jsonDecode(
        DesktopEngineProfile.macOsTun(proxy, tunName: 'utun10', routing: state),
      ) as Map<String, dynamic>;
      final macRules = (mac['routing'] as Map)['rules'] as List;
      expect(macRules.where((rule) => rule.containsKey('process')), isEmpty);
      expect(normalizeWindowsProcessName('chrome.exe'), 'chrome');
      expect(
        () => normalizeWindowsProcessName('C:/chrome.exe'),
        throwsFormatException,
      );
    },
  );
}
