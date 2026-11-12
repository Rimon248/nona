import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nona_client/desktop_engine_profile.dart';
import 'package:nona_client/desktop_routing.dart';

void main() {
  test('site names and process names are normalized for Xray', () {
    expect(normalizeDesktopSite('https://www.рефлаб.рф/'), 'xn--80ackyxz.xn--p1ai');
    expect(normalizeDesktopSite('example.ru'), 'example.ru');
    expect(() => normalizeDesktopSite('http://example.ru'), throwsFormatException);
    expect(normalizeWindowsProcess('chrome.exe'), 'chrome');
    expect(() => normalizeWindowsProcess('C:/Windows/System32/curl.exe'), throwsFormatException);
  });

  test('site exceptions outrank broad zones and Windows process rules outrank sites', () {
    final policy = DesktopRoutingPolicy.defaults().copyWith(
      vpnSites: {'youtube.ru'},
      directSites: {'example.com'},
      directProcesses: {'chrome'},
    );
    final saved = DesktopRoutingPolicy.fromJson(policy.toJson());
    expect(saved.directZones, contains('xn--p1ai'));

    const profile = '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}';
    final windows = jsonDecode(DesktopEngineProfile.windowsTun(profile, routing: saved)) as Map;
    final rules = (windows['routing'] as Map)['rules'] as List;
    expect((rules[0] as Map)['process'], ['chrome']);
    expect((rules[1] as Map)['domain'], ['domain:youtube.ru']);
    expect((rules[2] as Map)['domain'], ['domain:example.com']);
    expect((rules[3] as Map)['domain'], contains('domain:ru'));

    final mac = jsonDecode(DesktopEngineProfile.macOsTun(profile, tunName: 'utun10', routing: saved)) as Map;
    final macRules = (mac['routing'] as Map)['rules'] as List;
    expect(macRules.any((item) => (item as Map).containsKey('process')), isFalse);
    expect((macRules[0] as Map)['domain'], ['domain:youtube.ru']);
  });

  test('running Windows process list omits helper and system processes', () {
    final names = WindowsProcessCatalog.parseTasklist(
      '"chrome.exe","123","Console","1","10 K"\r\n'
      '"svchost.exe","321","Services","0","1 K"\r\n'
      '"Telegram.exe","222","Console","1","15 K"\r\n',
    );
    expect(names, ['chrome', 'Telegram']);
  });
}
