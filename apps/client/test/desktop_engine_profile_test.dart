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
    expect(rules[0]['outboundTag'], 'proxy');
    expect(rules[0]['domain'], contains('domain:example.ru'));
    expect(rules[1]['outboundTag'], 'direct');
    expect(
      rules[1]['domain'],
      containsAll(['domain:ru', 'domain:extra.example']),
    );
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
